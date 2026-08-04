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

/// 行与行之间那截 1px 虚线：落在 rail 的中轴上（x = 12）
private struct ChatTraceConnector: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 12, y: 0))
            p.addLine(to: CGPoint(x: 12, y: 12))
        }
        .stroke(YY.sage300, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 24, height: 12)
        .padding(.vertical, -3)
        .accessibilityHidden(true)
    }
}

struct ChatTraceLine: View {
    let part: UiPart
    @State private var open = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            rail
            VStack(alignment: .leading, spacing: 0) {
                row
                if open, let detail = spec.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13))
                        .lineSpacing(13 * 0.7)
                        .foregroundStyle(YY.ink500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 7)
                        .transition(.opacity.combined(with: .offset(y: -3)))
                }
            }
            .padding(.top, 5)
            .padding(.bottom, 9)
        }
    }

    // 24pt rail，glyph 22pt 居中——槽位尺寸照 DS，留给平台原生动画字形
    private var rail: some View {
        ZStack(alignment: .top) {
            Color.clear
            Group {
                if let icon = spec.icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(spec.thinking ? YY.sage500 : YY.ink400)
                } else {
                    Circle()
                        .strokeBorder(YY.sage300, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                        .frame(width: 15, height: 15)
                        .opacity(0.7)
                }
            }
            .frame(width: 22, height: 22)
            .background(YY.page, in: Circle())
            .padding(.top, 5)
        }
        .frame(width: 24)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ChatShimmerText(
                    spec.label,
                    running: spec.running,
                    color: spec.thinking ? YY.sage600 : YY.ink500
                )
                if let target = spec.target, !target.isEmpty {
                    Text(target)
                        .font(.yyMono(12))
                        .foregroundStyle(YY.ink400)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(spec.running ? 0.55 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let meta = spec.meta, !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 12))
                    .foregroundStyle(spec.failed ? YY.danger : YY.ink400)
                    .lineLimit(1)
            }
            if spec.detail != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(YY.ink300)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard spec.detail != nil else { return }
            withAnimation(.sceneStandard(0.2)) { open.toggle() }
        }
    }

    // MARK: - part → 一行的展示规格

    private struct Spec {
        var icon: String?
        var label: String
        var target: String?
        var meta: String?
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
                detail: trimmed.count > brief.count ? trimmed : nil,
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
            .font(.system(size: 13, weight: .medium))

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
        .lineSpacing(13 * 0.55)
        .fixedSize(horizontal: false, vertical: true)
    }
}
