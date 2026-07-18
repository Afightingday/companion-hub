import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GatewayConfig: Sendable, Equatable {
    public var baseURL: URL
    public var authToken: String?

    public init(baseURL: URL, authToken: String? = nil) {
        self.baseURL = baseURL
        self.authToken = authToken
    }
}

public enum GatewayError: Error, LocalizedError, Sendable {
    case invalidURL
    case http(status: Int, detail: String)
    case transport(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "网关地址不合法"
        case .http(let status, let detail): return detail.isEmpty ? "请求失败（\(status)）" : detail
        case .transport(let message): return message
        case .decoding(let message): return "响应解析失败：\(message)"
        }
    }
}

// 响应信封放文件级：局部类型的 Codable 合成在部分 Swift 工具链上不可用
private struct ContactsResponse: Decodable { let items: [ContactListItem] }
private struct GroupsResponse: Decodable { let items: [GroupListItem] }
private struct MessagesResponse: Decodable { let messages: [ApiMessage] }
private struct OkResponse: Decodable { let ok: Bool? }
private struct ErrorBody: Decodable {
    let detail: String?
    let error: String?
}
private struct EmptyBody: Encodable {}

/// 网关 HTTP 客户端（端点与 apps/web/src/lib/api.ts 一一对应）。
/// 鉴权：Authorization: Bearer <AUTH_TOKEN>（server.ts 也接受 ?token= 供 SSE 用）。
public final class GatewayClient: @unchecked Sendable {
    public let config: GatewayConfig
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(config: GatewayConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - 端点

    public func health() async throws -> HealthResponse {
        try await get("/api/health")
    }

    public func listContacts() async throws -> [ContactListItem] {
        let r: ContactsResponse = try await get("/api/contacts")
        return r.items
    }

    public func listGroups() async throws -> [GroupListItem] {
        let r: GroupsResponse = try await get("/api/groups")
        return r.items
    }

    public func conversation(contactId: String, limit: Int = 50) async throws -> ConversationSnapshot {
        try await get(
            "/api/contacts/\(contactId)/conversation",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    public func messages(
        conversationId: String,
        before: String? = nil,
        limit: Int = 30
    ) async throws -> [ApiMessage] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            query.append(URLQueryItem(name: "before", value: before))
        }
        let r: MessagesResponse = try await get("/api/conversations/\(conversationId)/messages", query: query)
        return r.messages
    }

    public func markRead(conversationId: String) async throws {
        let _: OkResponse = try await post("/api/conversations/\(conversationId)/read", body: EmptyBody())
    }

    // MARK: - 基础设施

    /// 拼完整 URL（供 SSE 层复用；path 以 / 开头）
    public func url(path: String, query: [URLQueryItem] = []) -> URL? {
        guard var comps = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = basePath + path
        comps.queryItems = query.isEmpty ? nil : query
        return comps.url
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(method: "GET", path: path, query: query, bodyData: nil)
    }

    private func post<T: Decodable>(
        _ path: String,
        body: some Encodable,
        query: [URLQueryItem] = []
    ) async throws -> T {
        try await send(method: "POST", path: path, query: query, bodyData: try encoder.encode(body))
    }

    private func send<T: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem],
        bodyData: Data?
    ) async throws -> T {
        guard let url = url(path: path, query: query) else { throw GatewayError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token = config.authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        request.httpBody = bodyData

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw GatewayError.transport("非 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let parsed = try? decoder.decode(ErrorBody.self, from: data)
            throw GatewayError.http(status: http.statusCode, detail: parsed?.detail ?? parsed?.error ?? "")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GatewayError.decoding(String(describing: error))
        }
    }

    /// dataTask + continuation：iOS 与 Linux corelibs 都稳定可用（async data(for:) 在 Linux 上历史坑多）
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: GatewayError.transport(error.localizedDescription))
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: GatewayError.transport("空响应"))
                }
            }
            task.resume()
        }
    }
}
