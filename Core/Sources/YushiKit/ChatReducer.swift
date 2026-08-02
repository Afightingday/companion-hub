import Foundation

// apps/web/src/lib/applyEvent.ts 的 Swift 移植 + 历史消息（ApiMessage）到 UI 模型的换装。
// 纯逻辑、零 UI 依赖——放 Core 保住 Linux CI 可测线（归约规则改动必须两端同步）。

public enum ApprovalUiStatus: String, Sendable, Equatable {
    case pending, approved, denied
}

/// 一张工具卡片：call 与 result 按 id 汇于同一张卡（applyEvent.ts upsertTool 语义）
public struct UiToolCard: Sendable, Equatable {
    public var call: ToolCall?
    public var result: ToolResultPayload?

    public init(call: ToolCall? = nil, result: ToolResultPayload? = nil) {
        self.call = call
        self.result = result
    }

    /// 匹配主键：call.id 优先，孤儿 result 卡退 toolCallId
    public var matchId: String { call?.id ?? result?.toolCallId ?? "" }
}

/// 过程条目：思考纸条 / 工具卡 / 审批信封 / 引用 / 计划
public struct UiPart: Sendable, Equatable, Identifiable {
    public enum Payload: Sendable, Equatable {
        case reasoningSummary(String)
        case toolCall(UiToolCard)
        case approval(ApprovalRequest, ApprovalUiStatus)
        case citation(Citation)
        case plan(AgentPlan)
    }

    public var id: String
    public var payload: Payload

    public init(id: String, payload: Payload) {
        self.id = id
        self.payload = payload
    }
}

/// 聊天页的可变消息模型。ApiMessage 是不可变宽容 DTO；流式渲染需要这层可累加结构。
public struct UiMessage: Sendable, Equatable, Identifiable {
    public var id: String
    /// "user" | "contact"
    public var author: String
    public var status: MessageStatus
    public var text: String
    public var parts: [UiPart]
    public var errorText: String?
    public var sentAt: String
    /// 群聊说话人（DM 为空；第 3 批用）
    public var contactId: String?

    public var isUser: Bool { author == "user" }

    public init(
        id: String,
        author: String,
        status: MessageStatus,
        text: String = "",
        parts: [UiPart] = [],
        errorText: String? = nil,
        sentAt: String,
        contactId: String? = nil
    ) {
        self.id = id
        self.author = author
        self.status = status
        self.text = text
        self.parts = parts
        self.errorText = errorText
        self.sentAt = sentAt
        self.contactId = contactId
    }
}

// MARK: - 事件归约（applyEvent.ts 逐条对位）

public extension UiMessage {
    /// 把一条统一事件归约进本消息。web 版是纯函数返回新对象；Swift 值语义下 mutating 等价。
    mutating func apply(_ event: ProviderEvent) {
        switch event {
        case .textDelta(let t):
            text += t

        case .reasoningSummaryDelta(let t):
            // 思考纸条永远在 parts 顶部、单例追加
            if let i = parts.firstIndex(where: { $0.isReasoning }) {
                if case .reasoningSummary(let old) = parts[i].payload {
                    parts[i].payload = .reasoningSummary(old + t)
                }
            } else {
                parts.insert(UiPart(id: "reasoning", payload: .reasoningSummary(t)), at: 0)
            }

        case .toolCallStarted(let call), .toolCallUpdated(let call):
            // 按 id upsert：命中则覆盖 call（保留已有 result），未命中新增一张卡
            if let i = toolIndex(matching: call.id) {
                if case .toolCall(var card) = parts[i].payload {
                    card.call = call
                    parts[i].payload = .toolCall(card)
                }
            } else {
                parts.append(UiPart(id: "tool-\(call.id)", payload: .toolCall(UiToolCard(call: call))))
            }

        case .toolResult(let result):
            // result 挂进同一张卡；找不到就落一张只有 result 的孤儿卡
            if let i = toolIndex(matching: result.toolCallId) {
                if case .toolCall(var card) = parts[i].payload {
                    card.result = result
                    parts[i].payload = .toolCall(card)
                }
            } else {
                parts.append(
                    UiPart(id: "tool-\(result.toolCallId)", payload: .toolCall(UiToolCard(result: result)))
                )
            }

        case .approvalRequest(let approval):
            parts.append(UiPart(id: "approval-\(approval.id)", payload: .approval(approval, .pending)))

        case .citation(let citation):
            parts.append(UiPart(id: "citation-\(parts.count)", payload: .citation(citation)))

        case .planUpdate(let plan):
            // 计划单例 upsert
            if let i = parts.firstIndex(where: { $0.isPlan }) {
                parts[i].payload = .plan(plan)
            } else {
                parts.append(UiPart(id: "plan", payload: .plan(plan)))
            }

        case .error(let e):
            status = e.code == "aborted" ? .aborted : .error
            errorText = e.message

        case .completed:
            status = .done

        case .turnStarted, .turnCompleted, .usage, .raw:
            break // 不改状态（raw.approvalResolved 由聊天层在归约前拦截分流）
        }
    }

    private func toolIndex(matching id: String) -> Int? {
        parts.firstIndex { part in
            if case .toolCall(let card) = part.payload { return card.matchId == id }
            return false
        }
    }
}

private extension UiPart {
    var isReasoning: Bool {
        if case .reasoningSummary = payload { return true }
        return false
    }

    var isPlan: Bool {
        if case .plan = payload { return true }
        return false
    }
}

/// 审批决议广播：把所有消息里匹配的信封置为终态（applyEvent.ts applyApprovalResolved）
public func applyApprovalResolved(
    messages: inout [UiMessage],
    approvalId: String,
    decision: String
) {
    let status: ApprovalUiStatus = decision == "approve" ? .approved : .denied
    for m in messages.indices {
        for p in messages[m].parts.indices {
            if case .approval(let request, _) = messages[m].parts[p].payload, request.id == approvalId {
                messages[m].parts[p].payload = .approval(request, status)
            }
        }
    }
}

// MARK: - 历史消息换装（ApiMessage → UiMessage）

private func decodePayload<T: Decodable>(_ value: JSONValue?, as _: T.Type) -> T? {
    guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

/// 历史 tool_call part 的 payload 形状：{call?, result?}（turn.ts pushPart 落库同形）
private struct ToolPartPayload: Decodable {
    var call: ToolCall?
    var result: ToolResultPayload?
}

private struct ReasoningPartPayload: Decodable { var text: String? }

private struct ApprovalPartPayload: Decodable {
    var approval: ApprovalRequest?
    var status: String?
}

private struct PlanPartPayload: Decodable { var items: [AgentPlanItem]? }

public extension UiMessage {
    /// 网关历史消息 → UI 消息。
    /// kind==text/raw 的 part 不进（正文已在 textContent，防双份渲染——Chat.tsx toUi 同规则）。
    init(from api: ApiMessage) {
        var parts: [UiPart] = []
        for part in api.parts ?? [] {
            switch part.kind {
            case .reasoningSummary:
                let text = decodePayload(part.payload, as: ReasoningPartPayload.self)?.text ?? ""
                parts.append(UiPart(id: "reasoning-\(part.id)", payload: .reasoningSummary(text)))
            case .toolCall, .toolResult:
                guard let p = decodePayload(part.payload, as: ToolPartPayload.self) else { break }
                parts.append(
                    UiPart(
                        id: "tool-\(part.id)",
                        payload: .toolCall(UiToolCard(call: p.call, result: p.result))
                    )
                )
            case .approval:
                guard let p = decodePayload(part.payload, as: ApprovalPartPayload.self),
                      let approval = p.approval else { break }
                // "expired" 等未知终态按 denied 展示（不再可操作）
                let status = ApprovalUiStatus(rawValue: p.status ?? "") ?? (p.status == "pending" ? .pending : .denied)
                parts.append(UiPart(id: "approval-\(approval.id)", payload: .approval(approval, status)))
            case .citation:
                guard let c = decodePayload(part.payload, as: Citation.self) else { break }
                parts.append(UiPart(id: "citation-\(part.id)", payload: .citation(c)))
            case .plan:
                guard let p = decodePayload(part.payload, as: PlanPartPayload.self) else { break }
                parts.append(UiPart(id: "plan", payload: .plan(AgentPlan(items: p.items ?? []))))
            case .text, .raw, .attachment:
                break
            }
        }
        self.init(
            id: api.id,
            author: api.author,
            status: api.status,
            text: api.textContent,
            parts: parts,
            errorText: nil,
            sentAt: api.sentAt,
            contactId: api.contactId
        )
    }
}
