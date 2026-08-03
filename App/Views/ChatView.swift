import SwiftUI
import YushiKit

/// 祐识 Conversation Screen：聊天不是一串系统气泡，而是一页持续生长的来往手账。
/// 数据与发送链仍由 ChatSession 负责；本文件只编排画布、卷轴和输入信笺。
struct ChatView: View {
    @Environment(AppModel.self) private var model
    let item: ContactListItem

    @State private var session: ChatSession?
    @State private var draft = ""

    var body: some View {
        ZStack {
            ChatPaperPalette.page.ignoresSafeArea()

            SceneAsset.image("assets/grain.png")
                .resizable(resizingMode: .tile)
                .opacity(0.045)
                .blendMode(.softLight)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let session {
                transcript(session)
            } else {
                ChatLoadingNote()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatComposerView(
                draft: $draft,
                isStreaming: session?.isStreaming ?? false,
                onSend: sendDraft,
                onAbort: abortTurn
            )
        }
        .navigationTitle(item.contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if session == nil {
                session = ChatSession(client: model.client, item: item)
                await session?.load()
            }
        }
    }

    // MARK: - 会话卷轴

    private func transcript(_ session: ChatSession) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                ChatConversationMarker(contactName: item.contact.name)

                if let loadError = session.loadError {
                    ChatLoadErrorNote(text: loadError)
                }

                if session.messages.isEmpty, session.loadError == nil {
                    ChatEmptyPage(contactName: item.contact.name)
                } else {
                    ForEach(session.messages) { message in
                        ChatMessageRow(
                            message: message,
                            contactName: item.contact.name
                        ) { approvalId, decision in
                            Task {
                                await session.decide(
                                    approvalId: approvalId,
                                    decision: decision
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 22)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
    }

    private func sendDraft() {
        guard !(session?.isStreaming ?? false) else { return }
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        Haptic.softTap()
        Task { await session?.send(text) }
    }

    private func abortTurn() {
        Haptic.lightTap()
        Task { await session?.abort() }
    }
}

private struct ChatConversationMarker: View {
    let contactName: String

    var body: some View {
        HStack(spacing: 10) {
            ChatPencilRule()
                .stroke(
                    ChatPaperPalette.paperEdge,
                    style: StrokeStyle(lineWidth: 0.8, dash: [4, 5])
                )
                .frame(height: 4)

            SceneAsset.image("assets/deco/crane.png")
                .resizable()
                .scaledToFit()
                .frame(width: 29, height: 25)
                .opacity(0.72)
                .accessibilityHidden(true)

            VStack(spacing: 1) {
                Text("与\(contactName)的这一页")
                    .font(SceneFont.note(12))
                    .tracking(1.05)
                    .foregroundStyle(ChatPaperPalette.inkFaint)
                Text(Date.now.formatted(.dateTime.month().day()))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(ChatPaperPalette.inkGhost)
            }
            .fixedSize()

            ChatPencilRule()
                .stroke(
                    ChatPaperPalette.paperEdge,
                    style: StrokeStyle(lineWidth: 0.8, dash: [4, 5])
                )
                .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}

private struct ChatEmptyPage: View {
    let contactName: String

    var body: some View {
        VStack(spacing: 11) {
            Text("今天想说点什么？")
                .font(SceneFont.note(21))
                .foregroundStyle(ChatPaperPalette.inkStrong)
            Text("写给\(contactName)的第一张纸，还空着。")
                .font(.subheadline)
                .foregroundStyle(ChatPaperPalette.inkFaint)
            SceneAsset.image("assets/chat/sparkles-gold.png")
                .resizable()
                .scaledToFit()
                .frame(width: 24)
                .opacity(0.55)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .background(ChatPaperPalette.paperRaised.opacity(0.56), in: ChatPaperCut(corner: 24))
        .overlay {
            ChatPaperCut(corner: 24)
                .strokeBorder(
                    ChatPaperPalette.sageSoft.opacity(0.62),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
        }
    }
}

private struct ChatLoadErrorNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14))
            Text(text)
                .font(.footnote)
                .lineSpacing(3)
        }
        .foregroundStyle(ChatPaperPalette.danger)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChatPaperPalette.roseWash.opacity(0.72), in: ChatPaperCut(corner: 14))
        .overlay {
            ChatPaperCut(corner: 14)
                .strokeBorder(ChatPaperPalette.rose.opacity(0.42), lineWidth: 0.8)
        }
    }
}

private struct ChatLoadingNote: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var faded = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 15))
            Text("正在摊开这一页")
                .font(SceneFont.note(13))
                .tracking(0.7)
        }
        .foregroundStyle(ChatPaperPalette.sageDeep)
        .opacity(faded ? 0.42 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                faded = true
            }
        }
    }
}
