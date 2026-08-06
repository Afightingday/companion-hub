import SwiftUI
import YushiKit

/// 祐识那边完整的一个回合：过程链 → 正文 → 盖章信笺 → 动作行。
/// 正文不进任何容器；动作行只有一枚重答箭头，多版本了右端才长出页码。
struct ChatAgentTurn: View {
    let message: UiMessage
    let selecting: Bool
    let picked: Bool
    let dimmed: Bool
    let streaming: Bool
    let versionIndex: Int
    var onPick: () -> Void
    var onAction: (ChatMessageAction) -> Void
    var onRetry: () -> Void
    var onVersion: (Int) -> Void
    var onApproval: (_ approvalId: String, _ decision: String) -> Void

    private var approvals: [(id: String, request: ApprovalRequest, status: ApprovalUiStatus)] {
        message.parts.compactMap { part in
            if case .approval(let request, let status) = part.payload {
                return (part.id, request, status)
            }
            return nil
        }
    }

    private var hasTrace: Bool {
        message.parts.contains { part in
            if case .approval = part.payload { return false }
            return true
        }
    }

    private var shownText: String {
        let all = message.priorVersions + [message.text]
        let i = min(max(versionIndex, 0), all.count - 1)
        return all[i]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if hasTrace {
                ChatTraceChain(parts: message.parts)
                    .opacity(dimmed ? 0.42 : 1)
            }

            // 寄出之后、第一个字之前，整页是**空的** —— 你的话没有任何状态标记
            //（「寄出中什么都不显示」是定过的口径，不动），祐识这边还没开口，
            // 于是点完发送要空等一两秒，手感就是"卡住了"。这里补一枚无字的呼吸墨点：
            // 不写字，不占版面，一有内容或过程链就让位。
            if streaming, shownText.isEmpty, !hasTrace {
                ChatThinkingDot()
            }

            if !shownText.isEmpty || streaming {
                ChatMessageRow(
                    message: bodyMessage,
                    selecting: selecting,
                    picked: picked,
                    dimmed: dimmed,
                    onPick: onPick,
                    onAction: onAction
                )
            }

            ForEach(approvals, id: \.id) { item in
                ChatApprovalCard(
                    request: item.request,
                    status: item.status,
                    onDecide: onApproval
                )
                .opacity(dimmed ? 0.42 : 1)
            }

            if message.status == .error || message.status == .aborted {
                brokenNote
            }

            if !selecting, !streaming, message.status == .done, !shownText.isEmpty {
                actionsRow
                    .opacity(dimmed ? 0.42 : 1)
            }
        }
        // 盖章信笺有垫底纸和探出的印章，这里把整块的布局足迹钉死，免得它把外层 LazyVStack 撑宽
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.sceneStandard(0.3), value: dimmed)
    }

    /// 换版本时正文跟着换；其余字段照旧
    private var bodyMessage: UiMessage {
        var copy = message
        copy.text = shownText
        return copy
    }

    /// 没写完 / 被打断：统一报错行（#14）。自己按停的不算事故，走墨灰；
    /// 真断了才用朱陶红。原始报错不上屏，留给 VoiceOver。
    private var brokenNote: some View {
        let aborted = message.status == .aborted
        return ChatErrorNote(
            text: aborted ? "写到这儿停了，轻点续上" : "这条没写完，轻点重试",
            tone: aborted ? .muted : .danger,
            detail: aborted ? nil : message.errorText,
            onTap: onRetry
        )
    }

    private var actionsRow: some View {
        HStack(spacing: 0) {
            ChatRetryGlyph(action: onRetry)
            Spacer(minLength: 8)
            if message.versionCount > 1 {
                HStack(spacing: 1) {
                    versionStep("chevron.left", enabled: versionIndex > 0) {
                        onVersion(versionIndex - 1)
                    }
                    Text("\(versionIndex + 1)/\(message.versionCount)")
                        .font(.yyMono(12.5))
                        .tracking(0.44)
                        .foregroundStyle(YY.ink400)
                        .frame(minWidth: 30)
                    versionStep("chevron.right", enabled: versionIndex < message.versionCount - 1) {
                        onVersion(versionIndex + 1)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(height: 42)
        .padding(.leading, -4)
        .padding(.top, -4)
        .animation(.sceneStandard(0.3), value: message.versionCount)
    }

    private func versionStep(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(YY.ink400)
                .frame(width: 26, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

/// 重答：点一下，那个手绕的圈重新描一遍（对位设计稿的 stroke-dashoffset 动画）。
/// 图形换成 GlyphRetry（#15 统一线稿语言），描边随全套规格走。
struct ChatRetryGlyph: View {
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 1
    @State private var hot = false

    var body: some View {
        Button {
            Haptic.lightTap()
            action()
            guard !reduceMotion else { return }
            drawn = 0
            hot = true
            withAnimation(.sceneStandard(0.55)) { drawn = 1 }
            withAnimation(.sceneStandard(0.22).delay(0.4)) { hot = false }
        } label: {
            GlyphRetry()
                .trim(from: 0, to: drawn)
                .stroke(style: YYGlyph.stroke())
                .foregroundStyle(hot ? YY.sage600 : YY.ink300)
                .frame(width: 20, height: 20)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重答一次")
    }
}
