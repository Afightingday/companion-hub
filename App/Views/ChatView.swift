import SwiftUI
import YushiKit

/// 第 2 批：真聊天 —— 发送 / SSE 流式 / 思考与工具过程行 / 审批纸卡。
/// 设计语言 = 奶油宣纸（D:\会话列表页-design_mock 设计系统）：
/// 你的话 = 右侧鼠尾草纸片；AI 的话 = 直接写在纸上（不装泡）；
/// 思考与只读工具 = 细淡 TraceLine 行；写动作审批 = 纸面信封卡。
/// 画布用 SceneTokens.paperPage 与 ChatSheetView 顶栏同纸；文字沿用 PaperTheme 墨色。
struct ChatView: View {
    @Environment(AppModel.self) private var model
    let item: ContactListItem

    @State private var session: ChatSession?
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            SceneTokens.paperPage.ignoresSafeArea()
            SceneAsset.image("assets/grain.png")
                .resizable(resizingMode: .tile)
                .opacity(0.05)
                .blendMode(.softLight)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let session {
                transcript(session)
            } else {
                ProgressView().tint(SceneTokens.sage600)
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .navigationTitle(item.contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if session == nil {
                session = ChatSession(client: model.client, item: item)
                await session?.load()
            }
        }
    }

    // MARK: - 消息卷轴

    private func transcript(_ session: ChatSession) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let loadError = session.loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                ForEach(session.messages) { message in
                    MessageRow(message: message) { approvalId, decision in
                        Task { await session.decide(approvalId: approvalId, decision: decision) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges) // 流式增长时粘底
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - 输入条（纸面胶囊 + 玻璃圆钮；流式中圆钮变「停笔」）

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("写点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16))
                .foregroundStyle(PaperTheme.ink)
                .tint(SceneTokens.sage600)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    SceneTokens.cream100,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(SceneTokens.cream500, lineWidth: 1)
                )
                .shadow(color: SceneTokens.shadowInk.opacity(0.06), radius: 8, x: 0, y: 4)

            actionButton
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.thinMaterial)
    }

    private var actionButton: some View {
        let streaming = session?.isStreaming ?? false
        return Button {
            if streaming {
                Haptic.lightTap()
                Task { await session?.abort() }
            } else {
                sendDraft()
            }
        } label: {
            Image(systemName: streaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(streaming ? PaperTheme.danger : SceneTokens.sage700)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(!streaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        Haptic.softTap()
        Task { await session?.send(text) }
    }
}

// MARK: - 一条消息

private struct MessageRow: View {
    let message: UiMessage
    var onApproval: (_ approvalId: String, _ decision: String) -> Void

    var body: some View {
        if message.isUser {
            userBubble
        } else {
            contactColumn
        }
    }

    /// 你的话：右侧鼠尾草纸片（18/18/6/18 带笔锋角）
    private var userBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .foregroundStyle(SceneTokens.ink800)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(PaperTheme.matchaSoft, in: bubbleShape)
                    .overlay(bubbleShape.strokeBorder(SceneTokens.sage300.opacity(0.55), lineWidth: 1))

                if message.status == .sending {
                    Text("寄出中…")
                        .font(.caption2)
                        .foregroundStyle(SceneTokens.ink400)
                } else if message.status == .error {
                    Text(message.errorText ?? "没寄出去")
                        .font(.caption2)
                        .foregroundStyle(PaperTheme.danger)
                }
            }
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 6,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    /// AI 的话：过程行在上，正文直接写在纸上；流式尾随墨点
    private var contactColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(message.parts) { part in
                PartRow(part: part, onApproval: onApproval)
            }

            if !message.text.isEmpty {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(displayText)
                        .font(.system(size: 16))
                        .lineSpacing(5)
                        .foregroundStyle(SceneTokens.ink800)
                        .textSelection(.enabled)
                    if message.status == .streaming {
                        PulsingDot()
                    }
                }
            } else if message.status == .streaming, message.parts.isEmpty {
                HStack(spacing: 6) {
                    PulsingDot()
                    Text("落笔中")
                        .font(.system(size: 13))
                        .foregroundStyle(SceneTokens.ink400)
                }
            }

            if message.status == .aborted {
                Text("已停笔")
                    .font(.caption2)
                    .foregroundStyle(SceneTokens.ink400)
            } else if message.status == .error, let errorText = message.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(PaperTheme.danger)
            }
        }
        .padding(.trailing, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 定稿消息轻量渲染行内 Markdown（粗斜体/行内码/链接）；流式期间原样直出避免闪烁
    private var displayText: AttributedString {
        if message.status == .done,
           let styled = try? AttributedString(
               markdown: message.text,
               options: AttributedString.MarkdownParsingOptions(
                   interpretedSyntax: .inlineOnlyPreservingWhitespace
               )
           ) {
            return styled
        }
        return AttributedString(message.text)
    }
}

// MARK: - 过程条目（TraceLine 精神：读写分层，只读细淡、写动作才上卡）

private struct PartRow: View {
    let part: UiPart
    var onApproval: (_ approvalId: String, _ decision: String) -> Void

    var body: some View {
        switch part.payload {
        case .reasoningSummary(let text):
            ThinkingRow(text: text)
        case .toolCall(let card):
            ToolRow(card: card)
        case .approval(let request, let status):
            ApprovalCardView(request: request, status: status, onDecide: onApproval)
        case .citation(let citation):
            CitationRow(citation: citation)
        case .plan(let plan):
            PlanRows(plan: plan)
        }
    }
}

/// 思考纸条：收起时一行淡字，展开是虚线框里的小字
private struct ThinkingRow: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.sceneGentle(0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 12))
                    Text(expanded ? "想的过程" : "先想了想")
                        .font(.system(size: 13))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(SceneTokens.ink400)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(SceneTokens.ink500)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        SceneTokens.cream100.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                SceneTokens.cream500,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                    )
            }
        }
    }
}

/// 只读工具行：一行淡字 + 摘要，永不变大卡
private struct ToolRow: View {
    let card: UiToolCard

    private var statusText: String {
        if let result = card.result { return result.ok ? "完成" : "失败" }
        switch card.call?.status {
        case "starting", "running": return "进行中"
        case "done": return "完成"
        case "error": return "失败"
        default: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "hammer")
                    .font(.system(size: 11))
                Text(card.call?.name ?? "工具")
                    .font(.system(size: 13, weight: .medium))
                if !statusText.isEmpty {
                    Text("· \(statusText)")
                        .font(.system(size: 12))
                }
            }
            .foregroundStyle(SceneTokens.ink400)

            if let preview = card.call?.inputPreview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SceneTokens.ink300)
                    .lineLimit(1)
            }
            if let preview = card.result?.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(SceneTokens.ink400)
                    .lineLimit(2)
            }
        }
        .padding(.leading, 2)
    }
}

/// 审批信封（简版纸卡；四拍拆封与祐印盖章动效等 Motion Lab 立项后再上）
private struct ApprovalCardView: View {
    let request: ApprovalRequest
    let status: ApprovalUiStatus
    var onDecide: (_ approvalId: String, _ decision: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "envelope")
                    .font(.system(size: 12))
                Text(request.title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(SceneTokens.ink800)

            if let detail = request.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(SceneTokens.ink500)
            }

            switch status {
            case .pending:
                HStack(spacing: 14) {
                    Button {
                        Haptic.softTap()
                        onDecide(request.id, "approve")
                    } label: {
                        Text("批准")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SceneTokens.cream100)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 7)
                            .background(SceneTokens.sage600, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptic.lightTap()
                        onDecide(request.id, "deny")
                    } label: {
                        Text("先不了")
                            .font(.system(size: 14))
                            .foregroundStyle(SceneTokens.ink400)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            case .approved:
                Label("已批准", systemImage: "checkmark.seal")
                    .font(.system(size: 13))
                    .foregroundStyle(SceneTokens.sage600)
            case .denied:
                Label("先不了", systemImage: "seal")
                    .font(.system(size: 13))
                    .foregroundStyle(SceneTokens.ink400)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }
}

private struct CitationRow: View {
    let citation: Citation

    private var label: String {
        if let title = citation.title, !title.isEmpty { return title }
        return citation.url
    }

    var body: some View {
        if let url = URL(string: citation.url) {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                    Text(label)
                        .font(.system(size: 12))
                        .underline()
                        .lineLimit(1)
                }
                .foregroundStyle(SceneTokens.sage600)
            }
        }
    }
}

private struct PlanRows: View {
    let plan: AgentPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(plan.items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.status == "done" ? SceneTokens.sage400 : SceneTokens.cream500)
                        .frame(width: 6, height: 6)
                    Text(item.text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(item.status == "done" ? SceneTokens.ink300 : SceneTokens.ink500)
                }
            }
        }
    }
}

/// 流式墨点：句尾的一滴呼吸墨
private struct PulsingDot: View {
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(SceneTokens.sage600)
            .frame(width: 7, height: 7)
            .opacity(dimmed ? 0.25 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}
