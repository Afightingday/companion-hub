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

    /// 没写完 / 被打断：一截断掉的虚线接一枚回环箭头 —— 不写「点击重试」那种话，
    /// 该说的话留给 VoiceOver
    private var brokenNote: some View {
        let aborted = message.status == .aborted
        return Button {
            Haptic.lightTap()
            onRetry()
        } label: {
            HStack(spacing: 10) {
                ChatBrokenStub()
                ZStack {
                    ChatRetryArc()
                        .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    ChatRetryTick()
                        .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 18, height: 18)
            }
            .foregroundStyle(aborted ? YY.ink300 : YY.danger)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(aborted ? "写到这儿停了，轻点续上" : (message.errorText ?? "没写完，轻点重试"))
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

/// 那截断掉的虚线：左浓右淡，尾巴悬空 —— 一眼是「这里断了」
private struct ChatBrokenStub: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 1))
            p.addLine(to: CGPoint(x: 30, y: 1))
        }
        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
        .frame(width: 30, height: 2)
        .mask {
            LinearGradient(colors: [.black, .black.opacity(0.15)], startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityHidden(true)
    }
}

/// 重答：点一下，箭头的两笔重新描一遍（对位设计稿的 stroke-dashoffset 动画）
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
            ZStack {
                ChatRetryArc()
                    .trim(from: 0, to: drawn)
                    .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                ChatRetryTick()
                    .trim(from: 0, to: drawn)
                    .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            .foregroundStyle(hot ? YY.sage600 : YY.ink300)
            .frame(width: 19, height: 19)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重答一次")
    }
}

/// 24×24 视框里那道大圆弧：M20.6 12.4 a8.6 8.6 0 1 1 -3 -6.6
private struct ChatRetryArc: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.minX + 12 * s, y: rect.minY + 12 * s),
            radius: 8.6 * s,
            startAngle: .degrees(2.7),
            endAngle: .degrees(312.1),
            clockwise: false
        )
        return path
    }
}

/// 箭头那一折：M20.9 4.2 v5.2 h-5.2
private struct ChatRetryTick: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 20.9 * s, y: rect.minY + 4.2 * s))
        path.addLine(to: CGPoint(x: rect.minX + 20.9 * s, y: rect.minY + 9.4 * s))
        path.addLine(to: CGPoint(x: rect.minX + 15.7 * s, y: rect.minY + 9.4 * s))
        return path
    }
}
