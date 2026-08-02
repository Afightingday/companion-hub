import Foundation

// 与 apps/web/src/lib/api.ts + packages/shared 对齐的 DTO。
// 解码原则：宽容 —— 未知字段忽略、拿不准的字段可空、时间戳保留 ISO 字符串由展示层格式化。

public struct ContactConfig: Codable, Identifiable, Sendable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var avatarUrl: String?
    public var signature: String?
    public var provider: String
    public var model: String
    public var personaPrompt: String?
    public var relationshipPrompt: String?
    public var nicknameForUser: String?
    public var webEnabled: Bool?
    public var toolsEnabled: [String]?
    public var memoryEnabled: Bool?
}

public struct LastMessage: Codable, Sendable, Equatable, Hashable {
    /// "user" | "contact"
    public var author: String
    public var text: String
    public var sentAt: String
    /// 群聊里可标记说话的联系人
    public var contactId: String?
}

public struct ContactListItem: Codable, Identifiable, Sendable, Equatable, Hashable {
    public var contact: ContactConfig
    public var conversationId: String
    public var lastMessage: LastMessage?
    public var unreadCount: Int

    public var id: String { contact.id }
}

public struct GroupConversation: Codable, Identifiable, Sendable, Equatable, Hashable {
    public var id: String
    public var title: String?
    public var scenePrompt: String?
    public var speakingMode: String?
}

public struct GroupListItem: Codable, Identifiable, Sendable, Equatable, Hashable {
    public var conversation: GroupConversation
    public var memberIds: [String]
    public var lastMessage: LastMessage?
    public var unreadCount: Int

    public var id: String { conversation.id }
}

/// message_parts.kind（未知值兜底成 raw，不炸解码）
public enum MessagePartKind: String, Codable, Sendable {
    case text
    case reasoningSummary = "reasoning_summary"
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case citation
    case approval
    case plan
    case attachment
    case raw

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = MessagePartKind(rawValue: value) ?? .raw
    }
}

public struct MessagePart: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var seq: Int
    public var kind: MessagePartKind
    public var payload: JSONValue?
}

/// 消息状态（未知值按 done 处理，历史展示不至于炸）
public enum MessageStatus: String, Codable, Sendable {
    case sending, streaming, done, error, aborted

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = MessageStatus(rawValue: value) ?? .done
    }
}

public struct ApiMessage: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var conversationId: String?
    /// "user" | "contact"
    public var author: String
    public var status: MessageStatus
    public var textContent: String
    public var replyTo: String?
    public var isFavorited: Bool?
    public var sentAt: String
    /// 群聊消息的说话人（DM 为空）
    public var contactId: String?
    public var parts: [MessagePart]?

    public var isUser: Bool { author == "user" }
}

/// POST /api/conversations/:id/messages 的 202 响应。
/// assistantMessageId：zod schema 未声明但单聊实返（turn.ts:65）、群聊必无——按可空建模。
public struct SendMessageResponse: Codable, Sendable, Equatable {
    public var userMessageId: String
    public var turnId: String
    public var assistantMessageId: String?
}

public struct ConversationSnapshot: Codable, Sendable, Equatable {
    public var conversationId: String
    public var contact: ContactConfig
    public var messages: [ApiMessage]
}

// MARK: - /api/health（apps/gateway/src/routes/health.ts）

public struct ProviderState: Codable, Sendable, Equatable {
    /// online | offline | not_configured
    public var state: String
    public var detail: String?
}

public struct HealthResponse: Codable, Sendable, Equatable {
    public var gateway: String
    public var version: String?
    public var uptimeSec: Int?
    /// local | supabase
    public var store: String?
    public var providers: [String: ProviderState]?
    public var memoryd: ProviderState?
}
