import SwiftUI
import UIKit
import YushiKit

/// 手账组件（chrome.css 对位）：搜索、墨水瓶羽毛笔。
/// 底栏/状态栏/Home 条不再自绘——正式版全走系统（SwiftUI TabView + 真机自带）。

// MARK: - 搜索玻璃面板（B2 第四步，1.11 六审定位）
// 场景几乎不糊（只轻压一点暗），搜索装进一块液态玻璃面板浮在键盘上
//（对位祐祐给的系统「自定义」面板参考）：面板内=结果行 + 原生 UISearchBar。
// 空白处点一下收起。点结果由场景收帘 + 开速览卡。

struct SearchVeilView: View {
    /// 选中某只：由场景收帘 + 开卡
    var onPick: (PetKey) -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
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
        ZStack(alignment: .bottom) {
            // 空白处点一下 = 收帘（场景只轻压暗，不糊）
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            panel
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .presentationBackground(Color.black.opacity(0.08))
        .task { await load() }
    }

    /// 液态玻璃面板：结果在上、原生搜索条在下（贴键盘）
    private var panel: some View {
        VStack(spacing: 2) {
            if hits.isEmpty {
                Text("没找着，换个词试试")
                    .font(SceneFont.note(13.5))
                    .foregroundStyle(SceneTokens.ink500)
                    .padding(.vertical, 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { i, spec in
                        if i > 0 {
                            Divider().overlay(SceneTokens.cream500.opacity(0.55))
                        }
                        Button {
                            Haptic.softTap()
                            onPick(spec.key)
                        } label: {
                            row(spec)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            NativeSearchBar(text: $query, placeholder: "寻旧识，拾旧话") {
                dismiss()
            }
            .frame(height: 52)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func row(_ spec: PetSpec) -> some View {
        HStack(spacing: 12) {
            SceneAsset.image(spec.art(.happy))
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 42)
            VStack(alignment: .leading, spacing: 2.5) {
                Text(spec.name)
                    .font(SceneFont.note(16))
                    .foregroundStyle(SceneTokens.ink800)
                Text(contacts[spec.key]?.lastMessage?.text ?? spec.previewFallback)
                    .font(.system(size: 12.5))
                    .foregroundStyle(SceneTokens.ink500)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(time(spec))
                .font(SceneFont.note(11))
                .foregroundStyle(SceneTokens.ink400)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
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

/// 苹果原生搜索条（UISearchBar 原件，六审「搜索条可以用原生的吗」）：
/// 自带放大镜/清空钮/取消钮与全套系统样式，唤起自动聚焦弹键盘
struct NativeSearchBar: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.placeholder = placeholder
        bar.searchBarStyle = .minimal
        bar.showsCancelButton = true
        bar.delegate = context.coordinator
        bar.backgroundImage = UIImage() // 面板已是玻璃，不要自带底
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak bar] in
            bar?.becomeFirstResponder()
        }
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        if bar.text != text { bar.text = text }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativeSearchBar
        init(_ parent: NativeSearchBar) { self.parent = parent }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.onCancel()
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }
    }
}

// MARK: - 搜索：纸签 ⇢ 便笺条（1.8 退役留库；1.9 起入口改玻璃圆钮+sheet）

struct SearchNoteView: View {
    let quiet: Bool
    @State private var open = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                open.toggle()
            } label: {
                // 手撕纸签：四边圆钝不均，像用手指掐出来的一块
                ZStack {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 22, bottomLeadingRadius: 22,
                        bottomTrailingRadius: 24, topTrailingRadius: 24,
                        style: .continuous)
                        .fill(SceneTokens.cream100)
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 22, bottomLeadingRadius: 22,
                                bottomTrailingRadius: 24, topTrailingRadius: 24,
                                style: .continuous)
                                .strokeBorder(SceneTokens.cream500, lineWidth: 1))
                        .shadow(color: SceneTokens.shadowInk.opacity(0.12), radius: 2.5, y: 2)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(SceneTokens.ink500)
                }
                .frame(width: 46, height: 46)
                .rotationEffect(.degrees(-6))
            }
            .buttonStyle(.plain)
            .zIndex(1)

            // 便笺条：默认卷着（宽 0），点开舒展
            ZStack(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 3, bottomLeadingRadius: 4,
                    bottomTrailingRadius: 8, topTrailingRadius: 10)
                    .fill(SceneTokens.cream100)
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 3, bottomLeadingRadius: 4,
                            bottomTrailingRadius: 8, topTrailingRadius: 10)
                            .strokeBorder(SceneTokens.cream500, lineWidth: 1))
                    .shadow(color: SceneTokens.shadowInk.opacity(0.1), radius: 3, y: 2)

                Text("寻旧识，拾旧话")
                    .font(.system(size: 13.5))
                    .tracking(0.27)
                    .foregroundStyle(SceneTokens.ink400)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 18)

                DashedLineShape()
                    .stroke(SceneTokens.sage300, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(height: 1.5)
                    .padding(.leading, 16)
                    .padding(.trailing, 14)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
            }
            .frame(width: open ? 252 : 0, height: 42, alignment: .leading)
            .clipped()
            .animation(.sceneGentle(0.34), value: open) // 宽度 340ms 舒展
            .opacity(open ? 1 : 0)
            .animation(.sceneStandard(0.2), value: open) // 透明度 200ms
            .rotationEffect(.degrees(-1.5))
            .offset(x: -8)
        }
        .opacity(quiet ? 0.28 : 1)
        .scaleEffect(quiet ? 0.86 : 1, anchor: .bottomLeading)
        .animation(.sceneStandard(0.32), value: quiet)
        .allowsHitTesting(!quiet)
        .accessibilityLabel(open ? "收起搜索" : "搜索")
    }
}

struct DashedLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - 新建：墨水瓶里的羽毛笔（正式资产 inkbottle + quill，滴墨 idle 6s）

struct QuillWellView: View {
    let quiet: Bool

    /// 滴墨与音效共用的 6s 周期（时间轴按参考纪元对齐，声画同步）
    static let dropPeriod: Double = 6
    static let dropHitPhase: Double = 0.9 // 90% 处触墨面

    var body: some View {
        TimelineView(.animation) { timeline in
            let sway = SceneWave.pingPong(timeline.date, period: 4.6)
            let u = SceneWave.cycle(timeline.date, period: Self.dropPeriod)

            VStack(spacing: -4) {
                ZStack(alignment: .topLeading) {
                    // 羽毛（后）：绕笔尖（瓶颈处）轻摇
                    SceneAsset.image("assets/quill.png")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 47)
                        .rotationEffect(.degrees(-2.4 + 4.4 * sway), anchor: UnitPoint(x: 10.0 / 47.0, y: 1))
                        .offset(x: 26, y: -8)

                    // 玻璃瓶（前）：羽轴在瓶颈被瓶沿截断，读作"插在瓶里"
                    SceneAsset.image("assets/inkbottle.png")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                    // 滴墨：笔尖凝出 → 落进墨面（隔玻璃可见）
                    Capsule()
                        .fill(SceneTokens.ink600)
                        .frame(width: 3, height: 4)
                        .scaleEffect(y: SceneWave.keyframes(u, [(0, 1), (0.8, 1), (0.9, 1.25), (0.93, 0.7), (1, 0.7)]), anchor: .top)
                        .offset(
                            x: 34.5,
                            y: 91 + SceneWave.keyframes(u, [(0, 0), (0.8, 0), (0.9, 17), (0.93, 21), (1, 21)]))
                        .opacity(SceneWave.keyframes(u, [(0, 0), (0.74, 0), (0.8, 0.85), (0.9, 0.85), (0.93, 0), (1, 0)]))
                }
                .frame(width: 88, height: 138, alignment: .topLeading)

                Text("添新识")
                    .font(SceneFont.note(11))
                    .tracking(0.88)
                    .foregroundStyle(SceneTokens.ink400)
                    .shadow(color: Color(hex: 0xFDFCF8).opacity(0.9), radius: 0, y: 1)
            }
            .frame(width: 92)
        }
        .shadow(color: SceneTokens.shadowInk.opacity(0.16), radius: 3, y: 3)
        .opacity(quiet ? 0.28 : 1)
        .scaleEffect(quiet ? 0.9 : 1, anchor: .bottomTrailing)
        .animation(.sceneStandard(0.32), value: quiet)
        .allowsHitTesting(!quiet)
        .accessibilityLabel("新建 Agent，添一位新伙伴")
        // 点击流程是 B11 待议：先只给按压手感，不接页面
        .onTapGesture { Haptic.softTap() }
    }
}
