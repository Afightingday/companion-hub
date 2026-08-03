import SwiftUI
import YushiKit

/// 一条消息不再是聊天软件气泡，而是手账页里的一张来往纸片。
struct ChatMessageRow: View {
    let message: UiMessage
    let contactName: String
    var onApproval: (_ approvalId: String, _ decision: String) -> Void

    var body: some View {
        Group {
            if message.isUser {
                userNote
            } else {
                agentEntry
            }
        }
        .id(message.id)
    }

    private var userNote: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 58)
            VStack(alignment: .trailing, spacing: 7) {
                ZStack(alignment: .topLeading) {
                    ChatPaperCut(corner: 17, foldedCorner: message.id.chatScrapbookVariant == 2)
                        .fill(ChatPaperPalette.sageSoft.opacity(0.58))
                        .rotationEffect(.degrees(-0.9), anchor: .bottomLeading)
                        .offset(x: -4, y: 5)

                    ChatPaperCut(corner: 17, foldedCorner: message.id.chatScrapbookVariant == 1)
                        .fill(ChatPaperPalette.sageWash)
                        .chatPaperTexture()
                        .overlay {
                            ChatPaperCut(corner: 17, foldedCorner: message.id.chatScrapbookVariant == 1)
                                .strokeBorder(ChatPaperPalette.sageSoft.opacity(0.72), lineWidth: 0.8)
                        }
                        .chatPaperShadow()

                    Text(message.text)
                        .font(.body)
                        .lineSpacing(5)
                        .foregroundStyle(ChatPaperPalette.inkStrong)
                        .textSelection(.enabled)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 14)

                    if message.id.chatScrapbookVariant == 0 {
                        ChatWashiTape(color: ChatPaperPalette.goldWash, width: 43)
                            .offset(x: 21, y: -7)
                    } else {
                        ChatPencilRule()
                            .stroke(
                                ChatPaperPalette.sage.opacity(0.34),
                                style: StrokeStyle(lineWidth: 0.8, dash: [4, 4])
                            )
                            .frame(width: 54, height: 3)
                            .offset(x: 18, y: 8)
                    }
                }
                .rotationEffect(.degrees(message.id.chatStableTilt), anchor: .bottomTrailing)
                .frame(maxWidth: 318, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)

                messageState(trailing: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var agentEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !message.parts.isEmpty {
                ChatAgentTrace(parts: message.parts, onApproval: onApproval)
                    .padding(.leading, 1)
                    .padding(.trailing, 3)
            }

            if !message.text.isEmpty {
                agentLetter
            } else if message.status == .streaming, message.parts.isEmpty {
                HStack(spacing: 8) {
                    ChatInkNib()
                    Text("正在纸上落笔")
                        .font(SceneFont.note(13))
                        .tracking(0.5)
                        .foregroundStyle(ChatPaperPalette.inkFaint)
                }
                .padding(.leading, 9)
            }

            messageState(trailing: false)
        }
        .frame(maxWidth: 358, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var agentLetter: some View {
        ZStack(alignment: .topLeading) {
            ChatPaperCut(corner: 20, foldedCorner: message.id.chatScrapbookVariant == 2)
                .fill(ChatPaperPalette.paperInset.opacity(0.62))
                .rotationEffect(.degrees(0.7), anchor: .bottomTrailing)
                .offset(x: 4, y: 5)

            ChatPaperCut(corner: 20, foldedCorner: message.id.chatScrapbookVariant == 1)
                .fill(ChatPaperPalette.paperHigh)
                .chatPaperTexture()
                .overlay {
                    ChatPaperCut(corner: 20, foldedCorner: message.id.chatScrapbookVariant == 1)
                        .strokeBorder(ChatPaperPalette.paperEdge.opacity(0.9), lineWidth: 0.8)
                }
                .chatPaperShadow(raised: true)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(ChatPaperPalette.sageSoft)
                        .frame(width: 6, height: 6)
                    Text(contactName)
                        .font(SceneFont.note(11.5))
                        .tracking(1.1)
                        .foregroundStyle(ChatPaperPalette.sageDeep)
                    ChatPencilRule()
                        .stroke(
                            ChatPaperPalette.paperEdge,
                            style: StrokeStyle(lineWidth: 0.8, dash: [4, 4])
                        )
                        .frame(height: 4)
                }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(displayText)
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundStyle(ChatPaperPalette.ink)
                        .textSelection(.enabled)
                    if message.status == .streaming {
                        ChatInkNib()
                    }
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            scrapbookAccent
        }
        .rotationEffect(.degrees(message.id.chatStableTilt * -0.68), anchor: .bottomLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var scrapbookAccent: some View {
        switch message.id.chatScrapbookVariant {
        case 0:
            SceneAsset.image("assets/chat/sparkles-gold.png")
                .resizable()
                .scaledToFit()
                .frame(width: 19)
                .opacity(0.52)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.top, 8)
                .padding(.trailing, 9)
                .allowsHitTesting(false)
        case 1:
            ChatWashiTape(color: ChatPaperPalette.roseWash, width: 39)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .offset(x: -24, y: -7)
        default:
            Image(systemName: "paperclip")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ChatPaperPalette.inkGhost.opacity(0.54))
                .rotationEffect(.degrees(10))
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.top, 9)
                .padding(.trailing, 12)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func messageState(trailing: Bool) -> some View {
        let frameAlignment: Alignment = trailing ? .trailing : .leading
        if message.status == .sending {
            Text("正晾一晾墨，再寄出")
                .font(SceneFont.note(11.5))
                .foregroundStyle(ChatPaperPalette.inkGhost)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
        } else if message.status == .aborted {
            Text("写到这里，先停笔")
                .font(SceneFont.note(11.5))
                .foregroundStyle(ChatPaperPalette.inkGhost)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
        } else if message.status == .error {
            Text(message.errorText ?? "这张纸没寄出去")
                .font(.caption)
                .foregroundStyle(ChatPaperPalette.danger)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
    }

    /// 定稿消息解析轻量行内 Markdown；流式期间保持原文，避免字体反复重排。
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

/// 流式尾标是一滴墨和一小截笔锋，不是现代聊天 UI 的三点 loading。
private struct ChatInkNib: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var faded = false

    var body: some View {
        HStack(spacing: 2) {
            Capsule()
                .fill(ChatPaperPalette.sage)
                .frame(width: 8, height: 2)
                .rotationEffect(.degrees(-16))
            Circle()
                .fill(ChatPaperPalette.sageDeep)
                .frame(width: 5.5, height: 5.5)
        }
        .opacity(faded ? 0.35 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                faded = true
            }
        }
        .accessibilityHidden(true)
    }
}
