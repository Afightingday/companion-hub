import Foundation
import Network
import Observation

/// 系统级网络可达性。会话页的「网络已断开」窄条只认这里。
/// 只报"有没有路"，不报"网关活没活"——网关活不活由请求失败态自己说。
///
/// 不给整个类挂 @MainActor：`shared` 要能在 View 的 @State 初值里直接取。
/// 写入一律绕回主队列，读取只发生在渲染路径上，故 @unchecked Sendable 成立。
@Observable
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.yushi.network-monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
