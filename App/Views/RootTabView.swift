import SwiftUI
import UIKit
import YushiKit

/// 五 tab 定稿（2026-08-01 祐祐）：云笺（会话首页）、游艺（Agent 互动、
/// 小游戏）、食帖（记录美食）、留声（一起听音乐）、案头（个人设置与
/// Agent 管理）+ 系统搜索 tab（B2 第一步）。
/// 底栏三审定稿（同日）：回归苹果原生 tab bar 保系统动画——1.7 的自绘
/// 胶囊撤编；只把托盘调透压白。图标 = 设计稿手绘线条 PNG 双态：
/// 选中原色、未选中灰化版（tools/tint-tabbar.ps1 生成，保笔触）。
struct RootTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selection = 0

    init() {
        // 托盘「有点发白」→ 透明底 + 超薄磨砂 + 一层极淡暖纱（0xF2EBDA @14%）。
        // iOS 26 液态玻璃对 UITabBarAppearance 的吃法以真机为准，浓淡再调
        let ap = UITabBarAppearance()
        ap.configureWithTransparentBackground()
        ap.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        ap.backgroundColor = UIColor(red: 0.949, green: 0.922, blue: 0.855, alpha: 0.14)
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
            // 原生搜索 tab：底栏右侧独立圆钮，点开自带键盘与全套系统动画
            Tab(value: 5, role: .search) {
                SearchTabView()
            }
        }
        .tint(SceneTokens.sage700)
        .onChange(of: selection) {
            SoundPlayer.shared.play(.tabTick) // B12：底栏切页一记笔触点
            Haptic.softTap()
        }
        .onChange(of: appModel.pendingOpenPet) {
            // 搜索页点了某只 → 跳回云笺，由场景消费 pendingOpenPet 开卡
            if appModel.pendingOpenPet != nil { selection = 0 }
        }
    }

    /// 双态图标：选中=原色原件，未选中=灰化版；31pt（三审「放大一点」）
    private func tabIcon(_ name: String, tag: Int) -> Image {
        let art = selection == tag ? "art/tabbar/\(name).png" : "art/tabbar/\(name)-off.png"
        return Image(uiImage: SceneAsset.tabIcon(art, pt: 31))
    }
}

// MARK: - 原生搜索 tab（B2 第一步：先把系统壳接上）

/// 结果 = 三只 pet 的名字/定位/最近一句本地过滤；点行回云笺开那只的速览卡。
/// 展开搜索、键盘、取消、液态玻璃形态全部走系统。
struct SearchTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var query = ""
    @State private var contacts: [PetKey: ContactListItem] = [:]

    private var hits: [PetSpec] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return PET_SPECS }
        return PET_SPECS.filter { spec in
            let last = contacts[spec.key]?.lastMessage?.text ?? spec.previewFallback
            return spec.name.lowercased().contains(q)
                || spec.role.lowercased().contains(q)
                || last.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(hits) { spec in
                Button {
                    Haptic.softTap()
                    appModel.pendingOpenPet = spec.key
                } label: {
                    row(spec)
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(SceneTokens.cream500)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(SceneTokens.paperPage.ignoresSafeArea())
            .overlay {
                if hits.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("寻旧识")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "寻旧识，拾旧话")
        }
        .task { await load() }
    }

    private func row(_ spec: PetSpec) -> some View {
        HStack(spacing: 12) {
            SceneAsset.image(spec.art(.happy))
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(spec.name)
                    .font(SceneFont.note(17))
                    .foregroundStyle(SceneTokens.ink800)
                Text(contacts[spec.key]?.lastMessage?.text ?? spec.previewFallback)
                    .font(.system(size: 13))
                    .foregroundStyle(SceneTokens.ink400)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(time(spec))
                .font(SceneFont.note(11))
                .foregroundStyle(SceneTokens.ink300)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func time(_ spec: PetSpec) -> String {
        if let sentAt = contacts[spec.key]?.lastMessage?.sentAt {
            let shown = PaperFormat.shortTime(sentAt)
            if !shown.isEmpty { return shown }
        }
        return spec.timeFallback
    }

    @MainActor
    private func load() async {
        guard let client = appModel.client else { return }
        if let items = try? await client.listContacts() {
            contacts = PetContactMatch.map(items)
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
