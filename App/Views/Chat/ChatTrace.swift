import SwiftUI
import SwiftStreamingMarkdown
import YushiKit

/// Agent 过程链 —— 设计系统 TraceLine 的 1:1 移植。
/// 思考与只读工具都是一行轻量的字，永远不升级成卡片；
/// 唯一被允许抢眼的是写操作的 ApprovalCard。
struct ChatTraceChain: View {
    let parts: [UiPart]

    private var lines: [UiPart] {
        parts.filter { part in
            if case .approval = part.payload { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, part in
                if index > 0 { ChatTraceConnector() }
                ChatTraceLine(part: part)
            }
        }
    }
}

/// 行与行之间那截 1px 虚线：落在 rail 的中轴上（x = 14）
private struct ChatTraceConnector: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 14, y: 0))
            p.addLine(to: CGPoint(x: 14, y: 13))
        }
        .stroke(YY.sage300, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 28, height: 13)
        .padding(.vertical, -3)
        .accessibilityHidden(true)
    }
}

struct ChatTraceLine: View {
    let part: UiPart
    @State private var open = false

    /// 展开后这一行显示什么：思考链是把摘要**换成**全文（不是在下面再抄一遍），
    /// 计划 / 引文才是标题下面另起一段。
    private var expandable: Bool { spec.full != nil || spec.detail != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rail
            VStack(alignment: .leading, spacing: 0) {
                row
                if open, let detail = spec.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 14.5))
                        .lineSpacing(14.5 * 0.34)
                        .foregroundStyle(YY.ink500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .offset(y: -3)))
                }
            }
            .padding(.top, 5)
            .padding(.bottom, 10)
        }
    }

    // 28pt rail，glyph 26pt 居中——槽位尺寸照 DS，留给平台原生动画字形
    private var rail: some View {
        ZStack(alignment: .top) {
            Color.clear
            Group {
                if let icon = spec.icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(spec.thinking ? YY.sage500 : YY.ink400)
                } else {
                    Circle()
                        .strokeBorder(YY.sage300, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                        .frame(width: 17, height: 17)
                        .opacity(0.7)
                }
            }
            .frame(width: 26, height: 26)
            .background(YY.page, in: Circle())
            .padding(.top, 4)
        }
        .frame(width: 28)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                headline
                if let target = spec.target, !target.isEmpty {
                    Text(target)
                        .font(.yyMono(13))
                        .foregroundStyle(YY.ink400)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(spec.running ? 0.55 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let meta = spec.meta, !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 13))
                    .foregroundStyle(spec.failed ? YY.danger : YY.ink400)
                    .lineLimit(1)
                    // 这一行是整条过程链里唯一没有截断保护的刚性子项：`lineLimit(1)` 的 Text
                    // 会把自己的理想宽度当作硬需求，meta 一长就顶宽整行 → 整个正文列被撑宽 →
                    // 居中排布之下左边那截被推出屏幕，就是「首字被切」。
                    // 截断 + 负布局优先级：宽度不够时它先让，绝不外顶。
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
            if expandable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(YY.ink300)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .padding(.top, 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard expandable else { return }
            withAnimation(.sceneStandard(0.24)) { open.toggle() }
        }
    }

    /// 这一行的头一句。
    ///
    /// **收起时**是一句摘要，走 `ChatShimmerText` —— 在想的时候要扫光，
    /// 而扫光是靠遮罩一个 `Text` 做的，套不到 Markdown 那棵视图树上。
    ///
    /// **展开时**换成全文，这时才过 Markdown 渲染器（b30 祐祐点名「思考链里面的没渲染」）。
    /// 模型的思考摘要里满是 `**加粗`、`-` 列表、行内代码，裸 `Text` 就是把星号原样摊在脸上。
    /// 展开态一定不在 running（`running` 只在摘要为空时为真），所以不会丢扫光。
    @ViewBuilder
    private var headline: some View {
        if open, let full = spec.full, !full.isEmpty {
            // interactive: false —— 这一行要靠外层 onTapGesture 收起，
            // 文字自己吃掉点击就再也收不起来了
            ChatMarkdownBody(text: full, config: ChatMarkdown.trace, interactive: false)
        } else {
            ChatShimmerText(
                spec.label,
                running: spec.running,
                color: spec.thinking ? YY.sage600 : YY.ink500
            )
        }
    }

    // MARK: - part → 一行的展示规格

    private struct Spec {
        var icon: String?
        var label: String
        /// 展开后**替换** label 的全文；nil 表示这一行没有「更长的自己」
        var full: String?
        var target: String?
        var meta: String?
        /// 展开后**追加**在 label 下方的另一段内容
        var detail: String?
        var thinking = false
        var running = false
        var failed = false
    }

    private var spec: Spec {
        switch part.payload {
        case .reasoningSummary(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
            let brief = head.count > 22 ? String(head.prefix(22)) + "…" : head
            return Spec(
                icon: "sparkle",
                label: brief.isEmpty ? "在想怎么说" : brief,
                // 收起看摘要、展开看全文，同一行原地换字——不再在下面把全文再抄一遍
                full: trimmed.count > brief.count ? trimmed : nil,
                thinking: true,
                running: brief.isEmpty
            )

        case .toolCall(let card):
            let name = card.call?.name ?? "处理一步"
            let status = card.call?.status ?? ""
            let running = card.result == nil && (status == "starting" || status == "running")
            let failed = card.result.map { !$0.ok } ?? (status == "error")
            return Spec(
                icon: Self.toolIcon(name: name, failed: failed),
                label: name,
                target: card.call?.inputPreview,
                meta: failed ? "失败" : card.result?.preview,
                detail: nil,
                running: running,
                failed: failed
            )

        case .citation(let citation):
            return Spec(
                icon: "arrow.up.right",
                label: citation.title?.isEmpty == false ? citation.title! : citation.url,
                target: nil,
                meta: nil,
                detail: citation.snippet
            )

        case .plan(let plan):
            let done = plan.items.filter { $0.status == "done" }.count
            return Spec(
                icon: "list.bullet",
                label: "拟了个步骤",
                meta: "\(done)/\(plan.items.count)",
                detail: plan.items
                    .map { ($0.status == "done" ? "✓ " : "· ") + $0.text }
                    .joined(separator: "\n")
            )

        case .approval:
            return Spec(icon: nil, label: "")
        }
    }

    private static func toolIcon(name: String, failed: Bool) -> String {
        if failed { return "exclamationmark.triangle" }
        if name.contains("日历") || name.contains("日程") { return "calendar" }
        if name.contains("天气") { return "cloud.sun" }
        if name.contains("搜索") || name.contains("查找") { return "magnifyingglass" }
        if name.contains("网页") || name.contains("读取") { return "globe" }
        if name.contains("记忆") || name.contains("档案") { return "tray.full" }
        if name.contains("算") { return "function" }
        return "wrench.and.screwdriver"
    }
}

/// 进行中的文字扫光 —— 设计系统明确要求：骨架扫光，不做跳点。
struct ChatShimmerText: View {
    private let text: String
    private let running: Bool
    private let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -1

    init(_ text: String, running: Bool, color: Color) {
        self.text = text
        self.running = running
        self.color = color
    }

    var body: some View {
        let label = Text(text)
            .font(.system(size: 14.5, weight: .medium))

        Group {
            if running && !reduceMotion {
                label
                    .foregroundStyle(.clear)
                    .overlay {
                        GeometryReader { proxy in
                            LinearGradient(
                                stops: [
                                    .init(color: color, location: 0),
                                    .init(color: color, location: 0.36),
                                    .init(color: YY.cream600, location: 0.5),
                                    .init(color: color, location: 0.64),
                                    .init(color: color, location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: proxy.size.width * 2.2)
                            .offset(x: sweep * proxy.size.width * 2.2)
                        }
                        .mask { label }
                    }
                    .onAppear {
                        sweep = 0.55
                        withAnimation(.linear(duration: 1.65).repeatForever(autoreverses: false)) {
                            sweep = -1
                        }
                    }
            } else {
                label.foregroundStyle(color)
            }
        }
        .lineSpacing(14.5 * 0.32)
        .fixedSize(horizontal: false, vertical: true)
    }
}
