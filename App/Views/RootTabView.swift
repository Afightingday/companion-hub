import SwiftUI
import UIKit
import YushiKit

/// 五 tab 定稿（2026-08-01 祐祐）：云笺（会话首页）、游艺（Agent 互动、
/// 小游戏）、食帖（记录美食）、留声（一起听音乐）、案头（个人设置与
/// Agent 管理）。
/// 底栏终审口径：苹果原生 tab bar + 系统动画（1.7 自绘胶囊勿回退）；
/// 图标 = 设计稿手绘线条 PNG 双态：选中原色、未选中灰化版
///（tools/tint-tabbar.ps1 生成，保笔触）。搜索不占底栏（1.9 四审：
/// 系统搜索 tab 会把案头挤进 More），玻璃圆钮回场景老位置。
struct RootTabView: View {
    @State private var selection = 0

    // 五审教训存档：iOS 26 液态玻璃底栏由系统自绘，UITabBarAppearance 的
    // backgroundEffect/backgroundColor 全被忽略（b18→b19 毫无变化的原因），
    // 相关代码已拆除；托盘底色目前没有官方接口可调

    var body: some View {
        TabView(selection: $selection) {
            // 会话总览页（窗边手账工作室）取代微信式列表成为云笺首页；
            // 旧列表 YunjianView 保留在库里，B2 搜索重设计时再议去留
            Tab(value: 0) {
                HomeSceneView()
            } label: {
                tabLabel("yunjian", "云笺", 0)
            }
            Tab(value: 1) {
                ComingSoonView(title: "游艺", subtitle: "和小家伙们的互动与小游戏 · 规划中", systemImage: "balloon")
            } label: {
                tabLabel("youyi", "游艺", 1)
            }
            Tab(value: 2) {
                ComingSoonView(title: "食帖", subtitle: "美食档案 · 后续批次搬进来", systemImage: "fork.knife")
            } label: {
                tabLabel("shitie", "食帖", 2)
            }
            Tab(value: 3) {
                ComingSoonView(title: "留声", subtitle: "一起听音乐 · 后续批次搬进来", systemImage: "music.note")
            } label: {
                tabLabel("liusheng", "留声", 3)
            }
            Tab(value: 4) {
                AntouView()
            } label: {
                tabLabel("antou", "案头", 4)
            }
        }
        .tint(SceneTokens.sage700)
        .onChange(of: selection) {
            SoundPlayer.shared.play(.tabTick) // B12：底栏切页一记笔触点
            Haptic.softTap()
        }
    }

    /// 满方图形的单枚缩系数（可见框 alpha 实测：齿轮 359×359 满方，
    /// 其余为长条形，同缩放下齿轮显壮——五审「案头怎么比别的大」）
    private static let iconNudge: [String: CGFloat] = ["antou": 0.86]

    /// 六审定稿：选中=浅鼠尾草绿版(-on)、去文字、图标放大居中；
    /// 未选中=暖灰版(-off) + 标签
    @ViewBuilder
    private func tabLabel(_ name: String, _ title: String, _ tag: Int) -> some View {
        let nudge = Self.iconNudge[name] ?? 1
        if selection == tag {
            Image(uiImage: SceneAsset.tabIcon("art/tabbar/\(name)-on.png", pt: 56, contentScale: nudge))
        } else {
            Label {
                Text(title)
            } icon: {
                Image(uiImage: SceneAsset.tabIcon("art/tabbar/\(name)-off.png", pt: 44, contentScale: nudge))
            }
        }
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
