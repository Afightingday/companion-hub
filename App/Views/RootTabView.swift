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

    init() {
        // 四审实验：磨砂开到最厚一档、撤掉暖纱，看系统材质素颜——
        // 祐祐判断发白未必是磨砂档位的锅，先做单变量对比（浓淡真机定）
        let ap = UITabBarAppearance()
        ap.configureWithTransparentBackground()
        ap.backgroundEffect = UIBlurEffect(style: .systemThickMaterialLight)
        UITabBar.appearance().standardAppearance = ap
        UITabBar.appearance().scrollEdgeAppearance = ap
    }

    var body: some View {
        TabView(selection: $selection) {
            // 会话总览页（窗边手账工作室）取代微信式列表成为云笺首页；
            // 旧列表 YunjianView 保留在库里，B2 搜索重设计时再议去留
            Tab(value: 0) {
                HomeSceneView()
            } label: {
                Label { Text("云笺") } icon: { tabIcon("yunjian", tag: 0) }
            }
            Tab(value: 1) {
                ComingSoonView(title: "游艺", subtitle: "和小家伙们的互动与小游戏 · 规划中", systemImage: "balloon")
            } label: {
                Label { Text("游艺") } icon: { tabIcon("youyi", tag: 1) }
            }
            Tab(value: 2) {
                ComingSoonView(title: "食帖", subtitle: "美食档案 · 后续批次搬进来", systemImage: "fork.knife")
            } label: {
                Label { Text("食帖") } icon: { tabIcon("shitie", tag: 2) }
            }
            Tab(value: 3) {
                ComingSoonView(title: "留声", subtitle: "一起听音乐 · 后续批次搬进来", systemImage: "music.note")
            } label: {
                Label { Text("留声") } icon: { tabIcon("liusheng", tag: 3) }
            }
            Tab(value: 4) {
                AntouView()
            } label: {
                Label { Text("案头") } icon: { tabIcon("antou", tag: 4) }
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

    /// 双态图标：选中=原色原件，未选中=灰化版；46pt（四审「放大到 150%」）
    private func tabIcon(_ name: String, tag: Int) -> Image {
        let art = selection == tag ? "art/tabbar/\(name).png" : "art/tabbar/\(name)-off.png"
        return Image(uiImage: SceneAsset.tabIcon(art, pt: 46, contentScale: Self.iconNudge[name] ?? 1))
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
