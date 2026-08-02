import Foundation

// packages/shared/src/events.ts 的 Swift 镜像 —— 两边改动需同步。

public struct ToolCall: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    /// starting | running | done | error
    public var status: String
    public var inputPreview: String?
    public var input: JSONValue?
}

public struct ToolResultPayload: Codable, Sendable, Equatable {
    public var toolCallId: String
    public var ok: Bool
    public var preview: String?
    public var payload: JSONValue?
}

public struct ApprovalRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var provider: String
    /// tool_use | command_exec | file_write | network | other
    public var kind: String
    public var title: String
    public var detail: String?
    public var payload: JSONValue?
    /// ISO 时间；超时未答按拒绝处理（设计 §11.3）
    public var expiresAt: String?
}

public struct AgentPlanItem: Codable, Sendable, Equatable {
    public var id: String?
    public var text: String
    /// pending | in_progress | done
    public var status: String
}

public struct AgentPlan: Codable, Sendable, Equatable {
    public var items: [AgentPlanItem]
}

public struct Citation: Codable, Sendable, Equatable {
    public var url: String
    public var title: String?
    public var snippet: String?
}

public struct TokenUsage: Codable, Sendable, Equatable {
    public var inputTokens: Double?
    public var outputTokens: Double?
    public var costEstimate: Double?
}

public struct ProviderErrorInfo: Codable, Sendable, Equatable {
    /// auth / network / rate_limit / timeout / unsupported / tool / aborted / unknown
    public var code: String
    public var message: String
    public var retryable: Bool?
}

/// 统一事件模型。未知 type 不丢弃 → 包成 .raw（R2 原则在客户端同样成立）。
public enum ProviderEvent: Sendable, Equatable {
    case textDelta(String)
    case reasoningSummaryDelta(String)
    case toolCallStarted(ToolCall)
    case toolCallUpdated(ToolCall)
    case toolResult(ToolResultPayload)
    case approvalRequest(ApprovalRequest)
    case planUpdate(AgentPlan)
    case citation(Citation)
    case turnStarted(turnId: String)
    case turnCompleted(turnId: String)
    case usage(TokenUsage)
    case completed
    case error(ProviderErrorInfo)
    case raw(provider: String, payload: JSONValue?)
}

extension ProviderEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, toolCall, result, approval, plan, citation, turnId, usage, error, provider, payload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text_delta":
            self = .textDelta(try c.decode(String.self, forKey: .text))
        case "reasoning_summary_delta":
            self = .reasoningSummaryDelta(try c.decode(String.self, forKey: .text))
        case "tool_call_started":
            self = .toolCallStarted(try c.decode(ToolCall.self, forKey: .toolCall))
        case "tool_call_updated":
            self = .toolCallUpdated(try c.decode(ToolCall.self, forKey: .toolCall))
        case "tool_result":
            self = .toolResult(try c.decode(ToolResultPayload.self, forKey: .result))
        case "approval_request":
            self = .approvalRequest(try c.decode(ApprovalRequest.self, forKey: .approval))
        case "plan_update":
            self = .planUpdate(try c.decode(AgentPlan.self, forKey: .plan))
        case "citation":
            self = .citation(try c.decode(Citation.self, forKey: .citation))
        case "turn_started":
            self = .turnStarted(turnId: try c.decode(String.self, forKey: .turnId))
        case "turn_completed":
            self = .turnCompleted(turnId: try c.decode(String.self, forKey: .turnId))
        case "usage":
            self = .usage(try c.decode(TokenUsage.self, forKey: .usage))
        case "completed":
            self = .completed
        case "error":
            self = .error(try c.decode(ProviderErrorInfo.self, forKey: .error))
        case "raw":
            self = .raw(
                provider: (try? c.decode(String.self, forKey: .provider)) ?? "unknown",
                payload: try? c.decode(JSONValue.self, forKey: .payload)
            )
        default:
            // 未知事件类型：整包保留（不抹平、不丢弃），与 toProviderEvent() 兜底一致
            self = .raw(provider: "unknown", payload: try? JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .textDelta(let t):
            try c.encode("text_delta", forKey: .type)
            try c.encode(t, forKey: .text)
        case .reasoningSummaryDelta(let t):
            try c.encode("reasoning_summary_delta", forKey: .type)
            try c.encode(t, forKey: .text)
        case .toolCallStarted(let call):
            try c.encode("tool_call_started", forKey: .type)
            try c.encode(call, forKey: .toolCall)
        case .toolCallUpdated(let call):
            try c.encode("tool_call_updated", forKey: .type)
            try c.encode(call, forKey: .toolCall)
        case .toolResult(let r):
            try c.encode("tool_result", forKey: .type)
            try c.encode(r, forKey: .result)
        case .approvalRequest(let a):
            try c.encode("approval_request", forKey: .type)
            try c.encode(a, forKey: .approval)
        case .planUpdate(let p):
            try c.encode("plan_update", forKey: .type)
            try c.encode(p, forKey: .plan)
        case .citation(let ci):
            try c.encode("citation", forKey: .type)
            try c.encode(ci, forKey: .citation)
        case .turnStarted(let id):
            try c.encode("turn_started", forKey: .type)
            try c.encode(id, forKey: .turnId)
        case .turnCompleted(let id):
            try c.encode("turn_completed", forKey: .type)
            try c.encode(id, forKey: .turnId)
        case .usage(let u):
            try c.encode("usage", forKey: .type)
            try c.encode(u, forKey: .usage)
        case .completed:
            try c.encode("completed", forKey: .type)
        case .error(let e):
            try c.encode("error", forKey: .type)
            try c.encode(e, forKey: .error)
        case .raw(let provider, let payload):
            try c.encode("raw", forKey: .type)
            try c.encode(provider, forKey: .provider)
            try c.encodeIfPresent(payload, forKey: .payload)
        }
    }
}

public extension ProviderEvent {
    /// 裸事件 JSON → 事件（注意：网关 SSE 的 data 行不是裸事件，是 TurnEventEnvelope 信封——
    /// 聊天层请走 `TurnEventEnvelope.decode(sseData:)`；本方法只用于解信封内层或测试）。
    static func decode(sseData: String, decoder: JSONDecoder = JSONDecoder()) -> ProviderEvent? {
        guard let data = sseData.data(using: .utf8) else { return nil }
        return try? decoder.decode(ProviderEvent.self, from: data)
    }

    /// 网关自造控制信号：审批决议广播（turn.ts 以 raw{payload.approvalResolved:{id,decision}} 发出，
    /// 归约前要先拦截分流——apps/web/src/pages/Chat.tsx 同规则）
    var approvalResolved: (id: String, decision: String)? {
        guard case .raw(_, let payload) = self,
              let obj = payload?["approvalResolved"],
              let id = obj["id"]?.stringValue,
              let decision = obj["decision"]?.stringValue else { return nil }
        return (id, decision)
    }
}

/// SSE data 行的真实形状（packages/shared/src/api.ts TurnEventEnvelope 的镜像）：
/// `{"id":7,"turnId":"…","event":{…ProviderEvent…}}`，id 单调递增供 Last-Event-ID 续传。
public struct TurnEventEnvelope: Codable, Sendable, Equatable {
    public var id: Int
    public var turnId: String
    public var event: ProviderEvent

    public init(id: Int, turnId: String, event: ProviderEvent) {
        self.id = id
        self.turnId = turnId
        self.event = event
    }

    /// SSE 的 data 行 → 信封。整段 JSON 坏才返回 nil（内层未知事件由 ProviderEvent 兜成 .raw，不丢）。
    public static func decode(sseData: String, decoder: JSONDecoder = JSONDecoder()) -> TurnEventEnvelope? {
        guard let data = sseData.data(using: .utf8) else { return nil }
        return try? decoder.decode(TurnEventEnvelope.self, from: data)
    }
}
