import SwiftUI
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

/// 行与行之间那截 1px 虚线：落在 rail 的中轴上（x = 11，槽宽 22 的中点）
private struct ChatTraceConnector: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 11, y: 0))
            p.addLine(to: CGPoint(x: 11, y: 13))
        }
        .stroke(YY.sage300, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 22, height: 13)
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
        HStack(alignment: .top, spacing: 10) {
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
            .padding(.bottom, 10)
        }
    }

    /// 裸 glyph 槽（#17 去掉圆容器和垫底纸）：22×19，高度对齐 label 首行行高、
    /// 垂直居中即与文字同轴 —— 原来的一高一低（#16）就是 rail 自带的 4pt 下沉
    /// 叠上正文 5pt 顶距造成的，这两截 padding 都不要了。
    private var rail: some View {
        Group {
            if spec.thinking {
                // 思考链的品牌图形：一缕卷起来的墨丝（#17，不是星星）
                GlyphThoughtCurl()
                    .stroke(style: YYGlyph.stroke(1.6))
                    .foregroundStyle(YY.sage500)
                    .padding(1)
            } else if let icon = spec.icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(YY.ink400)
            }
        }
        .frame(width: 22, height: 19)
        .accessibilityHidden(true)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                ChatShimmerText(
                    open ? (spec.full ?? spec.label) : spec.label,
                    running: spec.running,
                    color: spec.thinking ? YY.sage600 : YY.ink500
                )
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
                    // 失败色并进统一报错语言（#14）：全会话页的「坏了」都是朱陶红
                    .foregroundStyle(spec.failed ? YY.rose600 : YY.ink400)
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
            // 思考摘要是模型的草稿，常夹着裸 markdown 记号（**加粗**、`码`、# 标题）。
            // 这一行是纯文本 Text，不解析就会把星号原样露出来（2026-08-06 #16 截图里那样），
            // 记号全剥掉只留字。
            let plain = text
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: "#", with: "")
            let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
            let brief = head.count > 22 ? String(head.prefix(22)) + "…" : head
            return Spec(
                icon: nil, // thinking 走 GlyphThoughtCurl，不占 SF 位
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
