import SwiftUI

/// 聊天输入不是系统胶囊，而是一张压在桌面底部、随时可以落笔的小信笺。
struct ChatComposerView: View {
    @Binding var draft: String
    let isStreaming: Bool
    var onSend: () -> Void
    var onAbort: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ChatPaperCut(corner: 24, foldedCorner: true)
                .fill(ChatPaperPalette.sageSoft.opacity(0.48))
                .rotationEffect(.degrees(0.9), anchor: .bottomTrailing)
                .offset(x: 3, y: 4)

            ChatPaperCut(corner: 24, foldedCorner: false)
                .fill(ChatPaperPalette.paperHigh)
                .chatPaperTexture()
                .overlay {
                    ChatPaperCut(corner: 24)
                        .strokeBorder(
                            focused
                                ? ChatPaperPalette.sage.opacity(0.52)
                                : ChatPaperPalette.paperEdge.opacity(0.92),
                            lineWidth: focused ? 1.25 : 0.8
                        )
                }
                .chatPaperShadow(raised: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 11, weight: .medium))
                    Text("写一封话")
                        .font(SceneFont.note(12))
                        .tracking(1.2)
                    ChatPencilRule()
                        .stroke(
                            ChatPaperPalette.sageSoft.opacity(0.65),
                            style: StrokeStyle(lineWidth: 0.8, dash: [4, 4])
                        )
                        .frame(height: 5)
                }
                .foregroundStyle(ChatPaperPalette.inkFaint)

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("今天想说点什么？", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(ChatPaperPalette.inkStrong)
                        .tint(ChatPaperPalette.sageDeep)
                        .focused($focused)

                    Button {
                        isStreaming ? onAbort() : onSend()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    isStreaming
                                        ? ChatPaperPalette.roseWash
                                        : ChatPaperPalette.sage
                                )
                            Circle()
                                .strokeBorder(
                                    isStreaming
                                        ? ChatPaperPalette.rose
                                        : ChatPaperPalette.paperHigh.opacity(0.78),
                                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                                )
                                .padding(3)
                            Text(isStreaming ? "停" : "寄")
                                .font(SceneFont.note(17))
                                .foregroundStyle(
                                    isStreaming
                                        ? ChatPaperPalette.danger
                                        : ChatPaperPalette.paperHigh
                                )
                        }
                        .frame(width: 43, height: 43)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isStreaming && !canSend)
                    .opacity(!isStreaming && !canSend ? 0.42 : 1)
                    .accessibilityLabel(isStreaming ? "停笔" : "寄出")
                }
            }
            .padding(.leading, 17)
            .padding(.trailing, 13)
            .padding(.top, 14)
            .padding(.bottom, 13)

            ChatWashiTape(color: ChatPaperPalette.goldWash, width: 48)
                .offset(x: 30, y: -6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 13)
        .padding(.top, 13)
        .padding(.bottom, 7)
        .background {
            ChatPaperPalette.page.opacity(0.965)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [
                            SceneTokens.shadowInk.opacity(0.055),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 15)
                }
                .ignoresSafeArea()
        }
        .animation(.sceneGentle(0.2), value: focused)
    }
}
