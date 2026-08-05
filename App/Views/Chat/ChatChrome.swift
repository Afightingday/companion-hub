import SwiftUI
import UIKit

/// 会话页的**窗口级** chrome：真实安全区 + 键盘高度。
///
/// 为什么要自己取，而不是用 SwiftUI 现成的：
///
/// 这一页挂在一棵**安全区被抹平**的 hosting 树里 ——
/// `RootTabView` 的 representable 是 `.ignoresSafeArea()`（安全区交给
/// UITabBarController 自己算），`HomeSceneView` 又是 440×956 设计画布直落 +
/// `.ignoresSafeArea()`。到了 ChatScreen 这层，静态 `safeAreaInsets` 曾经是 0。
/// 键盘这条不能从静态安全区继续外推：b28 真机证明宿主仍会提供一部分键盘避让，
/// 所以这里只记录窗口级真值，最终 padding 由「目标遮挡 - 系统已给 inset」算差值。
///
/// - 顶栏顶到状态栏里，名字被灵动岛压住；
/// - 输入胶囊贴在屏幕物理最底，压着 home 指示条；
/// - 键盘弹起时胶囊纹丝不动，整条被键盘盖住。
///
/// 三件事同一个根因。`UIWindow.safeAreaInsets` 是设备给的，不受视图树里那些
/// `ignoresSafeArea` 影响，所以从窗口取一定对；键盘只能听通知。
///
/// ⚠️ 别把这套推广到别的页面。正常待在安全区里的页面用 SwiftUI 自带的就行，
/// 自己算等于给自己找两份真值（见 skill 的原则二：一个位置只能有一个庄家）。
/// 注：**刻意不标 `@MainActor`**。它要作为 `@State` 的初值在 View 的初始化里就地
/// 创建（同页的 `ChatSession` 是 `@MainActor`，所以只能声明成可选、拖到 `.task` 里
/// 再建）。这个类没有那个必要：所有通知都注册在 `.main` 队列上，`start()` 也只从
/// `onAppear` 调，写入天然都在主线程。
@Observable
final class ChatChrome {
    /// 刘海 / 灵动岛那一侧
    private(set) var safeTop: CGFloat = 0
    /// home 指示条那一侧
    private(set) var safeBottom: CGFloat = 0
    /// 键盘从屏幕底部往上盖了多少点；收起时 0
    private(set) var keyboard: CGFloat = 0

    private var tokens: [NSObjectProtocol] = []

    /// 底部悬浮物还需要**额外**补多少：宿主已经给过的那一段必须扣掉。
    /// b28 的错误正是把完整 keyboard 再加一次，和系统的部分避让叠成双份。
    func supplementalBottomInset(systemBottomInset: CGFloat) -> CGFloat {
        let target = keyboard > 0 ? keyboard : safeBottom
        return max(0, target - max(0, systemBottomInset))
    }

    func start() {
        readInsets()
        let center = NotificationCenter.default
        let onFrame = center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.apply(note)
        }
        let onHide = center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.set(keyboard: 0)
        }
        // 转屏 / 分屏之后安全区会变
        let onGeometry = center.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.readInsets()
        }
        tokens = [onFrame, onHide, onGeometry]
    }

    func stop() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
    }

    // MARK: - 内部

    private var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }

    private func readInsets() {
        guard let window else { return }
        // 窗口自己的 safeAreaInsets 来自设备，视图树里怎么 ignoresSafeArea 都不影响它
        safeTop = window.safeAreaInsets.top
        safeBottom = window.safeAreaInsets.bottom
    }

    private func apply(_ note: Notification) {
        guard
            let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        // 键盘帧是屏幕坐标系的：盖住的高度 = 屏幕底 - 键盘顶
        let screen = window?.screen.bounds ?? UIScreen.main.bounds
        set(keyboard: max(0, screen.maxY - end.minY))
    }

    /// 通知里给的是键盘最终帧。这里必须立即占住最终安全位置：宿主自己的键盘避让
    /// 已经在动画，若再给差值套一层 SwiftUI easeOut，真机上会落后并被键盘追上遮住。
    private func set(keyboard value: CGFloat) {
        guard value != keyboard else { return }
        keyboard = value
    }
}
