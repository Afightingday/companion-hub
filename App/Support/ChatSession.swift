import Foundation
import Observation
import YushiKit

/// 聊天页状态机（第 2 批），编排对位 apps/web/src/pages/Chat.tsx：
/// 快照加载 → 乐观发送 → 按 turnId 订阅事件流逐条归约 → 收尾补一次已读。
/// 归约规则在 Core（ChatReducer.swift），这里只管网络回合与消息数组。
@MainActor
@Observable
final class ChatSession {
    private let client: GatewayClient?
    let contactId: String

    private(set) var conversationId: String?
    private(set) var messages: [UiMessage] = []
    private(set) var loadError: String?
    private(set) var activeTurnId: String?
    var isStreaming: Bool { activeTurnId != nil }

    init(client: GatewayClient?, item: ContactListItem) {
        self.client = client
        self.contactId = item.contact.id
        self.conversationId = item.conversationId
    }

    func load() async {
        guard let client else {
            loadError = "还没连上网关 · 去「案头」填地址和令牌"
            return
        }
        do {
            let snapshot = try await client.conversation(contactId: contactId, limit: 50)
            conversationId = snapshot.conversationId
            messages = snapshot.messages.map(UiMessage.init(from:))
            loadError = nil
            // 进门即已读（与网页版一致）
            try? await client.markRead(conversationId: snapshot.conversationId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 乐观发送：先落一条本地 user 气泡，POST 回来换真 id 并插 assistant 占位，随后拉流
    func send(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let client, let conversationId else { return }

        let tempId = "temp-\(UUID().uuidString)"
        let now = ISO8601DateFormatter().string(from: Date())
        messages.append(
            UiMessage(id: tempId, author: "user", status: .sending, text: text, sentAt: now)
        )

        do {
            let res = try await client.sendMessage(conversationId: conversationId, text: text)
            patch(tempId) {
                $0.id = res.userMessageId
                $0.status = .done
            }
            let assistantId = res.assistantMessageId ?? "assistant-\(res.turnId)"
            messages.append(
                UiMessage(id: assistantId, author: "contact", status: .streaming, sentAt: now)
            )
            activeTurnId = res.turnId
            await run(turnId: res.turnId, assistantId: assistantId, client: client)
        } catch {
            patch(tempId) {
                $0.status = .error
                $0.errorText = error.localizedDescription
            }
        }
    }

    /// 停止生成：流内会送 error{code:"aborted"} 收尾帧，气泡状态交给归约器
    func abort() async {
        guard let client, let turnId = activeTurnId else { return }
        try? await client.abortTurn(turnId: turnId)
    }

    /// 审批裁决：本地即时置态（手感），服务端广播兜底纠偏；410=已超时也按本地选择显示
    func decide(approvalId: String, decision: String) async {
        applyApprovalResolved(messages: &messages, approvalId: approvalId, decision: decision)
        guard let client else { return }
        try? await client.decideApproval(approvalId: approvalId, decision: decision)
    }

    private func run(turnId: String, assistantId: String, client: GatewayClient) async {
        do {
            for try await env in TurnStream.events(client: client, turnId: turnId) {
                // 网关自造控制信号先分流，不进归约器（Chat.tsx:110-121 同规则）
                if let resolved = env.event.approvalResolved {
                    applyApprovalResolved(
                        messages: &messages,
                        approvalId: resolved.id,
                        decision: resolved.decision
                    )
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
            // 流式收尾后服务端未读可能又动过，补一次已读（Chat.tsx:122-125）
            try? await client.markRead(conversationId: conversationId)
        }
    }

    private func patch(_ id: String, _ mutate: (inout UiMessage) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[i])
    }
}
