import SwiftUI
import YushiKit

/// 一次 Agent 回合里的过程链。读操作轻、写操作重；Approval Card 是唯一抢眼元素。
struct ChatAgentTrace: View {
    let parts: [UiPart]
    var onApproval: (_ approvalId: String, _ decision: String) -> Void

    private var traceIndices: [Int] {
        parts.indices.filter { index in
            if case .approval = parts[index].payload { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                ChatAgentPartRow(
                    part: part,
                    isFirstTrace: traceIndices.first == index,
                    isLastTrace: traceIndices.last == index,
                    onApproval: onApproval
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatAgentPartRow: View {
    let part: UiPart
    let isFirstTrace: Bool
    let isLastTrace: Bool
    var onApproval: (_ approvalId: String, _ decision: String) -> Void

    @ViewBuilder
    var body: some View {
        switch part.payload {
        case .reasoningSummary(let text):
            ChatReasoningTrace(
                text: text,
                isFirst: isFirstTrace,
                isLast: isLastTrace
            )
        case .toolCall(let card):
            ChatToolTrace(
                card: card,
                isFirst: isFirstTrace,
                isLast: isLastTrace
            )
        case .approval(let request, let status):
            ChatApprovalCard(request: request, status: status, onDecide: onApproval)
                .padding(.top, 7)
                .padding(.bottom, 3)
        case .citation(let citation):
            ChatCitationTrace(
                citation: citation,
                isFirst: isFirstTrace,
                isLast: isLastTrace
            )
        case .plan(let plan):
            ChatPlanTrace(
                plan: plan,
                isFirst: isFirstTrace,
                isLast: isLastTrace
            )
        }
    }
}

private struct ChatTraceScaffold<Content: View>: View {
    let icon: String
    let running: Bool
    let failed: Bool
    let isFirst: Bool
    let isLast: Bool
    let content: Content

    init(
        icon: String,
        running: Bool = false,
        failed: Bool = false,
        isFirst: Bool,
        isLast: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.running = running
        self.failed = failed
        self.isFirst = isFirst
        self.isLast = isLast
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear
                .frame(width: 28)

            content
                .padding(.top, 1)
                .padding(.bottom, isLast ? 2 : 9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Rail 放在完成布局后的 overlay 里，能拿到正文决定的整行高度；
        // GeometryReader 若直接做 HStack 子项，在纵向 ScrollView 中只会取 10pt ideal height。
        .overlay(alignment: .topLeading) {
            ChatTraceRail(
                icon: icon,
                running: running,
                failed: failed,
                isFirst: isFirst,
                isLast: isLast
            )
            .frame(width: 28)
        }
    }
}

private struct ChatTraceRail: View {
    let icon: String
    let running: Bool
    let failed: Bool
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var color: Color {
        if failed { return ChatPaperPalette.rose }
        return ChatPaperPalette.sage
    }

    var body: some View {
        GeometryReader { proxy in
            let glyphY: CGFloat = 12
            Path { path in
                if !isFirst {
                    path.move(to: CGPoint(x: 14, y: 0))
                    path.addLine(to: CGPoint(x: 14, y: glyphY - 8))
                }
                if !isLast {
                    path.move(to: CGPoint(x: 14, y: glyphY + 8))
                    path.addLine(to: CGPoint(x: 14, y: proxy.size.height))
                }
            }
            .stroke(
                ChatPaperPalette.paperEdge,
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )

            Circle()
                .fill(ChatPaperPalette.page)
                .overlay {
                    Circle()
                        .strokeBorder(color.opacity(0.62), lineWidth: 1)
                }
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(color)
                }
                .scaleEffect(running && breathing ? 0.88 : 1)
                .opacity(running && breathing ? 0.58 : 1)
                .position(x: 14, y: glyphY)
        }
        .onAppear {
            guard running, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .onChange(of: running) { _, active in
            guard active, !reduceMotion else {
                breathing = false
                return
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

private struct ChatReasoningTrace: View {
    let text: String
    let isFirst: Bool
    let isLast: Bool
    @State private var expanded = false

    var body: some View {
        ChatTraceScaffold(
            icon: "clock",
            isFirst: isFirst,
            isLast: isLast
        ) {
            VStack(alignment: .leading, spacing: 7) {
                Button {
                    withAnimation(.sceneGentle(0.24)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(expanded ? "收起想法" : "先想了想")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .foregroundStyle(ChatPaperPalette.sageDeep)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    Text(text)
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(ChatPaperPalette.inkMuted)
                        .textSelection(.enabled)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ChatPaperPalette.paperRaised.opacity(0.78), in: ChatPaperCut(corner: 11))
                        .overlay {
                            ChatPaperCut(corner: 11)
                                .strokeBorder(
                                    ChatPaperPalette.paperEdge,
                                    style: StrokeStyle(lineWidth: 0.8, dash: [4, 4])
                                )
                        }
                        .transition(.opacity.combined(with: .offset(y: -3)))
                }
            }
        }
    }
}

private struct ChatToolTrace: View {
    let card: UiToolCard
    let isFirst: Bool
    let isLast: Bool

    private var status: String {
        if let result = card.result { return result.ok ? "完成" : "失败" }
        switch card.call?.status {
        case "starting", "running": return "进行中"
        case "done": return "完成"
        case "error": return "失败"
        default: return ""
        }
    }

    private var isRunning: Bool { status == "进行中" }
    private var failed: Bool { status == "失败" }

    private var icon: String {
        let name = card.call?.name ?? ""
        if name.contains("日历") { return "calendar" }
        if name.contains("搜索") || name.contains("查") { return "magnifyingglass" }
        if failed { return "exclamationmark" }
        return "wrench.and.screwdriver"
    }

    var body: some View {
        ChatTraceScaffold(
            icon: icon,
            running: isRunning,
            failed: failed,
            isFirst: isFirst,
            isLast: isLast
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(card.call?.name ?? "处理一步")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(failed ? ChatPaperPalette.danger : ChatPaperPalette.inkMuted)
                    if !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(failed ? ChatPaperPalette.rose : ChatPaperPalette.inkGhost)
                    }
                }

                if let preview = card.call?.inputPreview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(ChatPaperPalette.inkFaint)
                        .lineLimit(1)
                }
                if let preview = card.result?.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .lineSpacing(3)
                        .foregroundStyle(ChatPaperPalette.inkFaint)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct ChatCitationTrace: View {
    let citation: Citation
    let isFirst: Bool
    let isLast: Bool

    private var label: String {
        if let title = citation.title, !title.isEmpty { return title }
        return citation.url
    }

    var body: some View {
        ChatTraceScaffold(
            icon: "arrow.up.right",
            isFirst: isFirst,
            isLast: isLast
        ) {
            if let url = URL(string: citation.url) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(.subheadline)
                            .lineLimit(2)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(ChatPaperPalette.sageDeep)
                }
            }
        }
    }
}

private struct ChatPlanTrace: View {
    let plan: AgentPlan
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        ChatTraceScaffold(
            icon: "list.bullet.clipboard",
            isFirst: isFirst,
            isLast: isLast
        ) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(plan.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: item.status == "done" ? "checkmark" : "circle")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                item.status == "done"
                                    ? ChatPaperPalette.sage
                                    : ChatPaperPalette.inkGhost
                            )
                        Text(item.text)
                            .font(.caption)
                            .foregroundStyle(
                                item.status == "done"
                                    ? ChatPaperPalette.inkFaint
                                    : ChatPaperPalette.inkMuted
                            )
                    }
                }
            }
        }
    }
}

// MARK: - 盖章审批信笺

struct ChatApprovalCard: View {
    let request: ApprovalRequest
    let status: ApprovalUiStatus
    var onDecide: (_ approvalId: String, _ decision: String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamping = false
    @State private var deciding = false

    private var isDanger: Bool {
        let copy = request.title + " " + (request.detail ?? "")
        return copy.contains("删除") || copy.contains("移除") || copy.contains("不可恢复")
    }

    private var accent: Color {
        isDanger ? ChatPaperPalette.rose : ChatPaperPalette.sage
    }

    private var backing: Color {
        isDanger ? ChatPaperPalette.roseWash : ChatPaperPalette.sageSoft.opacity(0.58)
    }

    var body: some View {
        switch status {
        case .pending:
            pendingCard
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
        case .approved:
            receipt(approved: true)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        case .denied:
            receipt(approved: false)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private var pendingCard: some View {
        ZStack(alignment: .topLeading) {
            ChatPaperCut(corner: 23, foldedCorner: true)
                .fill(backing)
                .rotationEffect(.degrees(isDanger ? -1.15 : 1.25), anchor: .bottomTrailing)
                .offset(x: 5, y: 7)

            ChatPaperCut(corner: 23)
                .fill(ChatPaperPalette.paperHigh)
                .overlay {
                    ChatPaperCut(corner: 23)
                        .strokeBorder(ChatPaperPalette.paperEdge.opacity(0.9), lineWidth: 0.8)
                }
                .chatPaperShadow(raised: true)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 9) {
                    SceneAsset.image("assets/chat/leaf-sprig.png")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 35, height: 48)
                        .saturation(isDanger ? 0.45 : 0.78)
                        .colorMultiply(isDanger ? ChatPaperPalette.rose : .white)
                        .opacity(0.86)

                    Text(request.title)
                        .font(.title3.weight(.bold))
                        .lineSpacing(2)
                        .foregroundStyle(isDanger ? ChatPaperPalette.danger : ChatPaperPalette.inkStrong)
                        .padding(.top, 4)
                }

                if let detail = request.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .lineSpacing(3)
                        .foregroundStyle(ChatPaperPalette.inkMuted)
                }

                ChatPencilRule()
                    .stroke(
                        accent.opacity(0.62),
                        style: StrokeStyle(lineWidth: 0.9, dash: [5, 4])
                    )
                    .frame(width: 176, height: 5)

                HStack(spacing: 7) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(ChatPaperPalette.rose)
                    Text(isDanger ? "确认后不可恢复" : "需要你确认")
                        .foregroundStyle(ChatPaperPalette.inkMuted)
                }
                .font(.subheadline)

                Button {
                    guard !deciding else { return }
                    deciding = true
                    Haptic.lightTap()
                    onDecide(request.id, "deny")
                } label: {
                    Text("先不了")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatPaperPalette.inkFaint)
                        .overlay(alignment: .bottom) {
                            ChatPencilRule()
                                .stroke(
                                    ChatPaperPalette.inkGhost,
                                    style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
                                )
                                .frame(height: 2)
                                .offset(y: 4)
                        }
                }
                .buttonStyle(.plain)
                .disabled(deciding)
            }
            .padding(.leading, 17)
            .padding(.trailing, 100)
            .padding(.vertical, 17)

            Button(action: approveWithStamp) {
                VStack(spacing: -2) {
                    SceneAsset.image("assets/chat/seal-you.png")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 82, height: 82)
                    Text(isDanger ? "确认删除" : "盖章确认")
                        .font(SceneFont.note(12))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                }
                .scaleEffect(stamping ? 0.87 : 1)
                .offset(y: stamping ? 4 : 0)
                .opacity(stamping ? 0.76 : 1)
            }
            .buttonStyle(.plain)
            .disabled(deciding)
            .accessibilityLabel(isDanger ? "确认删除" : "盖章批准")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 13)
            .padding(.bottom, 12)

            SceneAsset.image("assets/chat/sparkles-gold.png")
                .resizable()
                .scaledToFit()
                .frame(width: 21)
                .opacity(0.72)
                .offset(x: 47, y: 12)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: 356, minHeight: 218, alignment: .leading)
    }

    private func receipt(approved: Bool) -> some View {
        HStack(spacing: 11) {
            SceneAsset.image("assets/chat/leaf-sprig.png")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 40)
                .opacity(0.68)

            VStack(alignment: .leading, spacing: 3) {
                Text(request.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatPaperPalette.inkStrong)
                    .lineLimit(2)
                Label(approved ? "已盖章批准" : "没有寄出", systemImage: approved ? "checkmark" : "xmark")
                    .font(.caption)
                    .foregroundStyle(approved ? ChatPaperPalette.sageDeep : ChatPaperPalette.inkFaint)
            }

            Spacer(minLength: 6)

            VStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { _ in
                    Capsule()
                        .fill(ChatPaperPalette.paperEdge)
                        .frame(width: 1, height: 4)
                }
            }
            .frame(height: 44)

            SceneAsset.image("assets/chat/seal-you.png")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .opacity(approved ? 0.50 : 0.24)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(ChatPaperPalette.paperHigh, in: ChatPaperCut(corner: 17, foldedCorner: true))
        .overlay {
            ChatPaperCut(corner: 17, foldedCorner: true)
                .strokeBorder(ChatPaperPalette.paperEdge, lineWidth: 0.8)
        }
        .overlay(alignment: .leading) {
            Circle()
                .fill(ChatPaperPalette.page)
                .frame(width: 14, height: 14)
                .offset(x: -7)
        }
        .overlay(alignment: .trailing) {
            Circle()
                .fill(ChatPaperPalette.page)
                .frame(width: 14, height: 14)
                .offset(x: 7)
        }
        .chatPaperShadow()
        .frame(maxWidth: 356)
    }

    private func approveWithStamp() {
        guard !deciding else { return }
        deciding = true
        Haptic.softTap()
        if reduceMotion {
            onDecide(request.id, "approve")
            return
        }
        withAnimation(.sceneGentle(0.18)) { stamping = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            onDecide(request.id, "approve")
            stamping = false
        }
    }
}
