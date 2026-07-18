import Foundation
import Observation
import YushiKit

/// 全局应用状态：网关连接配置 + 客户端工厂。
/// 地址存 UserDefaults（非敏感）；令牌只存 Keychain。
@Observable
final class AppModel {
    static let urlDefaultsKey = "yushi.gatewayURL"
    static let tokenKeychainKey = "gateway.authToken"

    var gatewayURLString: String {
        didSet { UserDefaults.standard.set(gatewayURLString, forKey: Self.urlDefaultsKey) }
    }

    var authToken: String {
        didSet { Keychain.set(authToken, forKey: Self.tokenKeychainKey) }
    }

    enum ConnectionState: Equatable {
        case unknown
        case ok(HealthResponse)
        case failed(String)
    }

    var connection: ConnectionState = .unknown

    init() {
        gatewayURLString = UserDefaults.standard.string(forKey: Self.urlDefaultsKey) ?? ""
        authToken = Keychain.string(forKey: Self.tokenKeychainKey) ?? ""
    }

    /// 规范化网关地址：自动补 https://、去尾部斜杠
    var normalizedBaseURL: URL? {
        var s = gatewayURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    var client: GatewayClient? {
        guard let base = normalizedBaseURL else { return nil }
        return GatewayClient(config: GatewayConfig(
            baseURL: base,
            authToken: authToken.isEmpty ? nil : authToken
        ))
    }

    @MainActor
    func testConnection() async {
        guard let client else {
            connection = .failed("先填网关地址（形如 https://xxx.ts.net）")
            return
        }
        do {
            connection = .ok(try await client.health())
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }
}
