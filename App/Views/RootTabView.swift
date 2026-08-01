import SwiftUI

/// 五 tab 定稿（2026-08-01 祐祐）：云笺（会话首页）、游艺（Agent 互动、
/// 小游戏）、食帖（记录美食）、留声（一起听音乐）、案头（个人设置与
/// Agent 管理）。
/// 底栏为自绘 YushiTabBar（同日二审拍板）：系统 Liquid Glass 托盘「发白」
/// 被否，改玻璃胶囊形态 + 暖调微磨砂 + 设计稿手绘线条图标。
struct RootTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            // 会话总览页（窗边手账工作室）取代微信式列表成为云笺首页；
            // 旧列表 YunjianView 保留在库里，B2 搜索重设计时再议去留
            HomeSceneView()
                .toolbar(.hidden, for: .tabBar)
                .tag(0)
            ComingSoonView(title: "游艺", subtitle: "和小家伙们的互动与小游戏 · 规划中", systemImage: "balloon")
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 74) }
                .tag(1)
            ComingSoonView(title: "食帖", subtitle: "美食档案 · 后续批次搬进来", systemImage: "fork.knife")
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 74) }
                .tag(2)
            ComingSoonView(title: "留声", subtitle: "一起听音乐 · 后续批次搬进来", systemImage: "music.note")
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 74) }
                .tag(3)
            AntouView()
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 74) }
                .tag(4)
        }
        .overlay(alignment: .bottom) {
            YushiTabBar(selection: $selection)
                .opacity(appModel.homeCardOpen ? 0 : 1)
                .offset(y: appModel.homeCardOpen ? 26 : 0)
                .animation(.sceneStandard(0.24), value: appModel.homeCardOpen)
                .allowsHitTesting(!appModel.homeCardOpen)
        }
        .onChange(of: selection) {
            SoundPlayer.shared.play(.tabTick) // B12：底栏切页一记笔触点
            Haptic.softTap()
        }
    }
}

// MARK: - 自绘底栏（2026-08-01 二审定稿方向）
// 形态 = iOS 时钟那种悬浮玻璃胶囊；材质 = 微微磨砂但不发白——
// ultraThinMaterial 上罩一层暖奶油纱压掉系统材质的白气；
// 图标 = 设计稿定稿手绘线条 PNG（原色渲染，保笔触浓淡）；
// 选中 = 鼠尾草软泡随选择弹性滑移；点按 = 压扁回弹小反馈。

private struct YushiTabItem {
    let tag: Int
    let title: String
    let art: String
}

struct YushiTabBar: View {
    @Binding var selection: Int
    @Namespace private var ns
    @State private var squashedTag: Int?

    private static let items: [YushiTabItem] = [
        YushiTabItem(tag: 0, title: "云笺", art: "art/tabbar/yunjian.png"),
        YushiTabItem(tag: 1, title: "游艺", art: "art/tabbar/youyi.png"),
        YushiTabItem(tag: 2, title: "食帖", art: "art/tabbar/shitie.png"),
        YushiTabItem(tag: 3, title: "留声", art: "art/tabbar/liusheng.png"),
        YushiTabItem(tag: 4, title: "案头", art: "art/tabbar/antou.png"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items, id: \.tag) { item in
                itemView(item)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                // 暖奶油纱：只压白气，不盖掉磨砂的透景
                Capsule(style: .continuous)
                    .fill(Color(hex: 0xF2EBDA).opacity(0.42))
                Capsule(style: .continuous)
                    .strokeBorder(SceneTokens.cream500.opacity(0.85), lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: SceneTokens.shadowInk.opacity(0.16), radius: 11, y: 6)
            .shadow(color: SceneTokens.shadowInk.opacity(0.08), radius: 2.5, y: 1.5)
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 4)
    }

    private func itemView(_ item: YushiTabItem) -> some View {
        let on = selection == item.tag
        return Button {
            guard selection != item.tag else { return }
            withAnimation(.interpolatingSpring(stiffness: 330, damping: 27)) {
                selection = item.tag
            }
            squashedTag = item.tag
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.32))
                if squashedTag == item.tag { squashedTag = nil }
            }
        } label: {
            VStack(spacing: 2.5) {
                SceneAsset.image(item.art)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 31, height: 27)
                    .scaleEffect(squashedTag == item.tag ? 0.84 : 1)
                    .animation(.interpolatingSpring(stiffness: 400, damping: 13), value: squashedTag)
                    .opacity(on ? 1 : 0.78)
                Text(item.title)
                    .font(SceneFont.note(11))
                    .tracking(0.55)
                    .foregroundStyle(on ? SceneTokens.ink800 : SceneTokens.ink500)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 7)
            .padding(.bottom, 5.5)
            .background {
                if on {
                    Capsule(style: .continuous)
                        .fill(SceneTokens.sage300.opacity(0.5))
                        .matchedGeometryEffect(id: "yushi.tab.bubble", in: ns)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
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
