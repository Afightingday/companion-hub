import SwiftUI
import YushiKit

/// 第 1 批：只读历史 —— 验证「真机 ↔ Tailscale ↔ 网关」全链路和纸面气泡手感。
/// 发送 / SSE 流式 / Markdown / 过程卡片 / 审批信封在第 2 批接入。
struct ChatView: View {
    @Environment(AppModel.self) private var model
    let item: ContactListItem

    @State private var messages: [ApiMessage] = []
    @State private var loadError: String?

    var body: some View {
        ZStack {
            PaperTheme.paperBg.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let loadError {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(PaperTheme.danger)
                            .padding(.top, 12)
                    }
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Text("发送与流式回复在第 2 批接入 ✍️")
                .font(.footnote)
                .foregroundStyle(PaperTheme.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.thinMaterial)
        }
        .navigationTitle(item.contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let client = model.client else { return }
        do {
            let snapshot = try await client.conversation(contactId: item.contact.id, limit: 50)
            messages = snapshot.messages
            loadError = nil
            // 进门即已读（与网页版一致）
            try? await client.markRead(conversationId: snapshot.conversationId)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct MessageBubble: View {
    let message: ApiMessage

    /// 过程摘要（第 2 批换成可展开的过程卡片；先证明 parts 通了）
    private var processSummary: [String] {
        guard let parts = message.parts else { return [] }
        var labels: [String] = []
        if parts.contains(where: { $0.kind == .reasoningSummary }) { labels.append("💭 思考") }
        let toolCount = parts.filter { $0.kind == .toolCall }.count
        if toolCount > 0 { labels.append("🛠 工具 ×\(toolCount)") }
        if parts.contains(where: { $0.kind == .citation }) { labels.append("🔖 引用") }
        if parts.contains(where: { $0.kind == .approval }) { labels.append("✉️ 审批") }
        return labels
    }

    private var statusNote: String? {
        switch message.status {
        case .error: return "发送出错"
        case .aborted: return "已中断"
        default: return nil
        }
    }

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 6) {
                if !processSummary.isEmpty {
                    Text(processSummary.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(PaperTheme.inkMuted)
                }
                Text(message.textContent.isEmpty ? "（空）" : message.textContent)
                    .font(.callout)
                    .foregroundStyle(PaperTheme.ink)
                    .textSelection(.enabled)
                if let statusNote {
                    Text(statusNote)
                        .font(.caption2)
                        .foregroundStyle(PaperTheme.danger)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.isUser ? PaperTheme.matchaSoft : PaperTheme.paperCard,
                in: RoundedRectangle(cornerRadius: PaperTheme.cardRadius, style: .continuous)
            )
            .shadow(color: PaperTheme.shadowColor, radius: 10, x: 0, y: 8)
            if !message.isUser { Spacer(minLength: 48) }
        }
    }
}
