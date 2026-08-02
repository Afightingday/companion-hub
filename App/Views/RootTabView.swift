import SwiftUI
import UIKit
import YushiKit

/// 五 tab 定稿（2026-08-01 祐祐）：云笺（会话首页）、游艺（Agent 互动、
/// 小游戏）、食帖（记录美食）、留声（一起听音乐）、案头（个人设置与
/// Agent 管理）。
///
/// 底栏实现变迁：1.7 自绘胶囊（三审否，勿回退）→ 1.8 系统 TabView →
/// 1.13(b24) 起 UITabBarController 手管 item（终点站）。原因：iOS 26 的
/// SwiftUI Tab 桥只在建 item 时读一次 label——selection 变了 label 重算
/// 但 item 不刷新，b21 裸条件、b23 加 .id 换身份，真机两轮均不动。
/// UIKit 侧 image/title 是可变属性，delegate 里手改是确定性行为，不再赌桥。
/// 图标口径不变（六审）：选中=浅鼠尾草绿 -on 56pt 无字居中；
/// 未选中=-off 44pt+标签；齿轮满方缩 0.86（五审）。液态玻璃 bar 由系统
/// 自绘，UIKit 结构照拿（背景仍无接口可调，教训同 b19）。
struct RootTabView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NativeTabs(appModel: appModel)
            .ignoresSafeArea() // representable 吃满窗口，安全区交给 UITabBarController 自己算
    }
}

/// tab 清单（顺序=底栏顺序；make 出的根视图会统一补挂 WindowGroup 级修饰）
private struct TabSpec {
    let icon: String // Media/art/tabbar/<icon>-{on,off}.png
    let title: String
    let nudge: CGFloat
    let make: () -> AnyView
}

private let TAB_SPECS: [TabSpec] = [
    TabSpec(icon: "yunjian", title: "云笺", nudge: 1) { AnyView(HomeSceneView()) },
    TabSpec(icon: "youyi", title: "游艺", nudge: 1) {
        AnyView(ComingSoonView(title: "游艺", subtitle: "和小家伙们的互动与小游戏 · 规划中", systemImage: "balloon"))
    },
    TabSpec(icon: "shitie", title: "食帖", nudge: 1) {
        AnyView(ComingSoonView(title: "食帖", subtitle: "美食档案 · 后续批次搬进来", systemImage: "fork.knife"))
    },
    TabSpec(icon: "liusheng", title: "留声", nudge: 1) {
        AnyView(ComingSoonView(title: "留声", subtitle: "一起听音乐 · 后续批次搬进来", systemImage: "music.note"))
    },
    TabSpec(icon: "antou", title: "案头", nudge: 0.86) { AnyView(AntouView()) },
]

/// UIKit 底栏宿主：五个 UIHostingController + delegate 手管双态
private struct NativeTabs: UIViewControllerRepresentable {
    let appModel: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UITabBarController {
        let tc = UITabBarController()
        tc.delegate = context.coordinator
        // WindowGroup 根上的浅色锁定不进独立 hosting 树，这里在 UIKit 层再锁一次
        tc.overrideUserInterfaceStyle = .light
        tc.tabBar.tintColor = UIColor(SceneTokens.sage700)
        tc.viewControllers = TAB_SPECS.enumerated().map { i, spec in
            // WindowGroup 级修饰（environment/tint/浅色）对手建 hosting 树要逐棵重挂
            let root = spec.make()
                .environment(appModel)
                .tint(PaperTheme.matchaDeep)
                .preferredColorScheme(.light)
            let vc = UIHostingController(rootView: AnyView(root))
            // 首建 item 图文必须一次到位：先 nil 图后补图，UIKit 会按
            // 纯文字 item 排首版布局（标题偏下超框），切一次选中才重排
            //（b25 真机实证）
            vc.tabBarItem = UITabBarItem(
                title: spec.title,
                image: SceneAsset.tabIcon(
                    "art/tabbar/\(spec.icon)-off.png", pt: 44, contentScale: spec.nudge),
                tag: i)
            return vc
        }
        context.coordinator.applySelection(tc)
        tc.tabBar.setNeedsLayout() // 选中位换 56pt 大图标后立刻重排，不等切页
        TabBarChrome.shared.controller = tc
        return tc
    }

    func updateUIViewController(_ tc: UITabBarController, context: Context) {}

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        private var lastIndex = 0

        func tabBarController(_ tc: UITabBarController, didSelect viewController: UIViewController) {
            if tc.selectedIndex != lastIndex {
                lastIndex = tc.selectedIndex
                SoundPlayer.shared.play(.tabTick) // B12：底栏切页一记笔触点
                Haptic.softTap()
            }
            applySelection(tc)
        }

        /// 双态落位：选中=on56 去题（无题 item 图标才会竖直居中），其余=off44+题
        func applySelection(_ tc: UITabBarController) {
            guard let vcs = tc.viewControllers else { return }
            for (i, vc) in vcs.enumerated() {
                let spec = TAB_SPECS[i]
                let selected = i == tc.selectedIndex
                vc.tabBarItem.image = SceneAsset.tabIcon(
                    "art/tabbar/\(spec.icon)-\(selected ? "on" : "off").png",
                    pt: selected ? 56 : 44,
                    contentScale: spec.nudge)
                vc.tabBarItem.title = selected ? nil : spec.title
            }
        }
    }
}

/// 收/放底栏的庄家线：UIKit 结构里 SwiftUI 的 .toolbar(_, for: .tabBar)
/// 失效（要 TabView 祖先），开卡/搜索时 HomeSceneView 走这里
@MainActor
final class TabBarChrome {
    static let shared = TabBarChrome()
    weak var controller: UITabBarController?

    func setHidden(_ hidden: Bool, animated: Bool = true) {
        guard let tc = controller, tc.isTabBarHidden != hidden else { return }
        tc.setTabBarHidden(hidden, animated: animated)
    }
}

/// 占位页：网页版仍可用，此处只标注迁移批次
struct ComingSoonView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ZStack {
                PaperTheme.paperBg.ignoresSafeArea()
                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                } description: {
                    Text(subtitle)
                        .foregroundStyle(PaperTheme.inkMuted)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 导航内的轻量占位（不带 NavigationStack）
struct ComingSoonPlain: View {
    let text: String

    var body: some View {
        ZStack {
            PaperTheme.paperBg.ignoresSafeArea()
            Text(text)
                .font(.footnote)
                .foregroundStyle(PaperTheme.inkMuted)
                .padding()
        }
    }
}
