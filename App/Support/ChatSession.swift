import Foundation
import Observation
import YushiKit

/// 会话页状态机：快照加载 → 乐观发送 → 按 turnId 订阅事件流逐条归约 → 收尾补一次已读。
/// 归约规则在 Core（ChatReducer.swift）；这里只管网络回合、消息数组，以及派生行的缓存。
@MainActor
@Observable
final class ChatSession {
    private let client: GatewayClient?
    let contactId: String

    private(set) var conversationId: String?
    private(set) var messages: [UiMessage] = []
    /// 卷轴派生行（日界切分）。**存起来**——写成计算属性的话，流式期间每个字符都会重算全表。
    private(set) var rows: [ChatRow] = []
    private(set) var contact: ContactConfig?
    private(set) var loadError: String?
    private(set) var activeTurnId: String?
    /// POST 返回前 activeTurnId 还是 nil；没有这道门闩，两个 Task 会同时穿过发送 guard。
    private var turnStarting = false
    private(set) var loadingMore = false
    private(set) var reachedTop = false

    var isStreaming: Bool { turnStarting || activeTurnId != nil }
    var isEmpty: Bool { messages.isEmpty && loadError == nil }

    init(client: GatewayClient?, item: ContactListItem) {
        self.client = client
        self.contactId = item.contact.id
        self.conversationId = item.conversationId
        self.contact = item.contact
    }

    // MARK: - 加载

    func load() async {
        guard let client else {
            loadError = "还没连上网关 · 去「案头」填地址和令牌"
            return
        }
        do {
            let snapshot = try await client.conversation(contactId: contactId, limit: 50)
            conversationId = snapshot.conversationId
            contact = snapshot.contact
            replaceMessages(snapshot.messages.map(UiMessage.init(from:)))
            loadError = nil
            reachedTop = snapshot.messages.count < 50
            try? await client.markRead(conversationId: snapshot.conversationId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 往上翻历史。`before` 用当前最早一条的 id。
    @discardableResult
    func loadMore() async -> Bool {
        guard let client, let conversationId, !loadingMore, !reachedTop,
              let oldest = messages.first else { return false }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let older = try await client.messages(conversationId: conversationId, before: oldest.id, limit: 30)
            if older.isEmpty { reachedTop = true; return false }
            let known = Set(messages.map(\.id))
            let fresh = older.map(UiMessage.init(from:)).filter { !known.contains($0.id) }
            if fresh.isEmpty { reachedTop = true; return false }
            replaceMessages(fresh + messages)
            reachedTop = older.count < 30
            return true
        } catch {
            return false
        }
    }

    /// 一直往前翻到找着这条为止（搜索命中不在内存时用）。最多回溯 6 页。
    func revealMessage(id: String) async -> Bool {
        if messages.contains(where: { $0.id == id }) { return true }
        for _ in 0..<6 {
            guard await loadMore() else { break }
            if messages.contains(where: { $0.id == id }) { return true }
        }
        return false
    }

    // MARK: - 发送

    /// 乐观发送：先落一条本地气泡，POST 回来换真 id 并插 assistant 占位，随后拉流
    func send(_ rawText: String, replyTo: String? = nil) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let client, let conversationId else { return }

        // @MainActor 上先同步关门，再进入第一个 await；并发 Task 的第二个会在 guard 被挡住。
        turnStarting = true
        defer { turnStarting = false }
        _ = await performSend(text, replyTo: replyTo, client: client, conversationId: conversationId)
    }

    /// 已占住 single-flight 门闩后的实际发送。成功返回新 assistant id，POST 失败返回 nil。
    private func performSend(
        _ text: String,
        replyTo: String?,
        client: GatewayClient,
        conversationId: String
    ) async -> String? {
        let tempId = "temp-\(UUID().uuidString)"
        let now = ChatSession.isoNow()
        appendMessage(
            UiMessage(id: tempId, author: "user", status: .sending, text: text, sentAt: now, replyTo: replyTo)
        )

        do {
            let res = try await client.sendMessage(conversationId: conversationId, text: text, replyTo: replyTo)
            patch(tempId) {
                $0.id = res.userMessageId
                $0.status = .done
            }
            let assistantId = res.assistantMessageId ?? "assistant-\(res.turnId)"
            appendMessage(UiMessage(id: assistantId, author: "contact", status: .streaming, sentAt: now))
            activeTurnId = res.turnId
            await run(turnId: res.turnId, assistantId: assistantId, client: client)
            return assistantId
        } catch {
            patch(tempId) {
                $0.status = .error
                $0.errorText = error.localizedDescription
            }
            return nil
        }
    }

    /// 停止生成：流内会送 error{code:"aborted"} 收尾帧，状态交给归约器
    func abort() async {
        guard let client, let turnId = activeTurnId else { return }
        try? await client.abortTurn(turnId: turnId)
    }

    /// 就地重答。
    /// 网关没有 regenerate 端点，且上下文是从扁平历史组装的——旧那一轮必须先删掉，
    /// 否则新回合会把上一版答案一起喂回去。旧正文留在客户端当历史版本（本次会话内有效）。
    /// 分支树落库是独立一批的事（祐祐 2026-08-03 定）。
    @discardableResult
    func retry(assistantId: String) async -> Bool {
        guard let client, let conversationId, !isStreaming,
              let assistantIndex = messages.firstIndex(where: { $0.id == assistantId }),
              assistantIndex > 0
        else { return false }

        let assistant = messages[assistantIndex]
        let user = messages[assistantIndex - 1]
        guard user.isUser, !user.text.isEmpty else { return false }

        // 删除与重发是一整个临界区；没占门闩前不能跨 await。
        turnStarting = true
        defer { turnStarting = false }

        var history = assistant.priorVersions
        if !assistant.text.isEmpty { history.append(assistant.text) }

        do {
            try await client.deleteMessage(id: assistant.id)
            try await client.deleteMessage(id: user.id)
        } catch {
            // 旧实现吞掉删除错误后仍继续 send，会把旧问题复制一份。失败时以服务端快照纠偏并停下。
            await load()
            return false
        }
        messages.removeAll { $0.id == assistant.id || $0.id == user.id }
        rebuildRows()

        guard let newAssistantId = await performSend(
            user.text,
            replyTo: user.replyTo,
            client: client,
            conversationId: conversationId
        ) else { return false }

        // 新回合落地后，把旧版本挂到新回复上，版本切换器才有得切
        patch(newAssistantId) { $0.priorVersions = history }
        return true
    }

    // MARK: - 编辑 / 删除

    func delete(ids: Set<String>) async {
        guard let client else { return }
        for id in ids where !id.hasPrefix("temp-") {
            try? await client.deleteMessage(id: id)
        }
        messages.removeAll { ids.contains($0.id) }
        rebuildRows()
    }

    /// 审批裁决：本地即时置态（手感），服务端广播兜底纠偏；410=已超时也按本地选择显示。
    /// 本地先按「批准/拒绝」画；工具真跑失败了，网关会再广播一次 `failed` 把它改过来。
    func decide(approvalId: String, decision: String) async {
        applyApprovalResolved(
            messages: &messages,
            approvalId: approvalId,
            status: decision == "approve" ? .approved : .denied
        )
        rebuildRows()
        guard let client else { return }
        try? await client.decideApproval(approvalId: approvalId, decision: decision)
    }

    // MARK: - 搜索

    /// 返回命中的消息 id，按时间正序（和卷轴一个方向）
    func search(_ query: String) async -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let client, let conversationId else { return [] }
        guard let found = try? await client.searchMessages(conversationId: conversationId, query: q, limit: 30)
        else { return [] }
        return found.map(\.id).reversed()
    }

    // MARK: - 联系人

    func updateContact(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, !trimmed.isEmpty, trimmed != contact?.name else { return }
        contact?.name = trimmed      // 先本地生效，手感不等网络
        if let saved = try? await client.patchContact(id: contactId, patch: ContactPatch(name: trimmed)) {
            contact = saved
        }
    }

    // MARK: - 内部

    private func run(turnId: String, assistantId: String, client: GatewayClient) async {
        do {
            for try await env in TurnStream.events(client: client, turnId: turnId) {
                // 网关自造控制信号先分流，不进归约器
                if let resolved = env.event.approvalResolved {
                    applyApprovalResolved(
                        messages: &messages,
                        approvalId: resolved.id,
                        status: resolved.status
                    )
                    rebuildRows()
                    continue
                }
                patch(assistantId) { $0.apply(env.event) }
            }
        } catch {
            patch(assistantId) {
                if $0.status == .streaming {
                    $0.status = .error
                    $0.errorText = "连接中断：\(error.localizedDescription)"
                }
            }
        }
        activeTurnId = nil
        // gone / 漏帧：流结束还挂着 streaming → 拉一次历史校准到服务端真相
        if messages.first(where: { $0.id == assistantId })?.status == .streaming {
            await load()
        } else if let conversationId {
            try? await client.markRead(conversationId: conversationId)
        }
    }

    private func patch(_ id: String, _ mutate: (inout UiMessage) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[i])
        rebuildRows()
    }

    private func appendMessage(_ message: UiMessage) {
        messages.append(message)
        rebuildRows()
    }

    private func replaceMessages(_ next: [UiMessage]) {
        messages = next
        rebuildRows()
    }

    private func rebuildRows() {
        rows = groupRows(messages)
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}
