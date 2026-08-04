import SwiftUI
import YushiKit

/// 长按菜单里的一项（用原生 .contextMenu 渲染，这里只描述语义）
enum ChatMessageAction {
    case edit, copy, quote, select, delete
}

/// 一条消息的一行。
/// 你的话＝一圈 2px 虚线，不填色；祐识那边的话不进任何容器，正文直接落在纸上。
/// 时间不占版面：64pt 的槽挂在行的右边缘之外，整条卷轴左拖才露出来。
struct ChatMessageRow: View {
    let message: UiMessage
    let selecting: Bool
    let picked: Bool
    let dimmed: Bool
    var onPick: () -> Void
    var onAction: (ChatMessageAction) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if selecting {
                ChatSelectBox(picked: picked, action: onPick)
                    .padding(.bottom, 5)
            }

            Group {
                if message.isUser {
                    userBubble
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    agentBody
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ChatTimeSlot(sentAt: message.sentAt)
        }
        .padding(.trailing, -64)      // 时间槽整块探出行外，对位设计稿的 margin-right:-64
        .opacity(dimmed ? 0.42 : 1)
        .animation(.sceneStandard(0.3), value: dimmed)
    }

    // MARK: - 你的话

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(alignment: .center, spacing: 7) {
                Text(message.text)
                    .font(.system(size: 15.5))
                    .lineSpacing(15.5 * 0.55)
                    .foregroundStyle(YY.ink700)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                YY.sage400,
                                style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                            )
                    }
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: 260, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .chatMenu(isUser: true, enabled: !selecting, onAction: onAction)

                if message.status == .error {
                    ChatFailMark(action: { onAction(.edit) })
                }
            }

            if message.status == .error {
                Text("未送达 · 轻点重发")
                    .font(.yyMono(10.5, weight: .medium))
                    .tracking(0.42)
                    .foregroundStyle(Color(hex: 0xD0453C))
                    .padding(.trailing, 25)
                    .onTapGesture { onAction(.edit) }
            } else if message.status == .sending {
                Text("寄出中")
                    .font(.yyMono(10))
                    .foregroundStyle(YY.ink300)
                    .padding(.trailing, 2)
            }
        }
    }

    // MARK: - 祐识那边的话

    private var agentBody: some View {
        Text(displayText)
            .font(.system(size: 16))
            .lineSpacing(16 * 0.78)
            .foregroundStyle(YY.ink700)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
            .chatMenu(isUser: false, enabled: !selecting, onAction: onAction)
    }

    /// 定稿才解析行内 Markdown；流式期间保持原文，否则每来一个字都重排一次版
    private var displayText: AttributedString {
        guard message.status == .done,
              let styled = try? AttributedString(
                  markdown: message.text,
                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              )
        else { return AttributedString(message.text) }
        return styled
    }
}

// MARK: - 长按：交给系统原生菜单（抬起、压暗、触感全是系统的）

private struct ChatMenuModifier: ViewModifier {
    let isUser: Bool
    let enabled: Bool
    var onAction: (ChatMessageAction) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu {
                if isUser {
                    Button { onAction(.edit) } label: { Label("编辑", systemImage: "pencil") }
                } else {
                    Button { onAction(.quote) } label: { Label("引用", systemImage: "arrowshape.turn.up.left") }
                }
                Button { onAction(.copy) } label: { Label("拷贝", systemImage: "doc.on.doc") }
                Button { onAction(.select) } label: { Label("多选", systemImage: "checkmark.circle") }
                Divider()
                Button(role: .destructive) { onAction(.delete) } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } else {
            content
        }
    }
}

private extension View {
    func chatMenu(
        isUser: Bool,
        enabled: Bool,
        onAction: @escaping (ChatMessageAction) -> Void
    ) -> some View {
        modifier(ChatMenuModifier(isUser: isUser, enabled: enabled, onAction: onAction))
    }
}

// MARK: - 零件

/// 多选圆圈：原生 Mail 的语汇，从左侧滑进来
struct ChatSelectBox: View {
    let picked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(picked ? YY.sage600 : .clear)
                .overlay {
                    Circle().strokeBorder(picked ? YY.sage600 : YY.ink300, lineWidth: 1.5)
                }
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .opacity(picked ? 1 : 0)
                }
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}

/// 挂在行外的时间槽。border-box 64pt，左内缩 24pt——数值对位设计稿。
struct ChatTimeSlot: View {
    let sentAt: String

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        Text(ChatTime.parse(sentAt).map { Self.clock.string(from: $0) } ?? "")
            .font(.yyMono(10))
            .tracking(0.3)
            .foregroundStyle(YY.ink300)
            .lineLimit(1)
            .padding(.leading, 24)
            .frame(width: 64, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// 未送达：气泡右侧一枚朱红小圈，不写整行红字
struct ChatFailMark: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .strokeBorder(YY.danger, lineWidth: 1.5)
                .overlay {
                    Text("!")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(YY.danger)
                }
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }
}

/// 日界戳：磨砂胶囊，滚动时跟手浮现，停手 1.2 秒淡掉。
/// 挂在滚动容器的 overlay 上，不进内容流——进内容流会被顶栏压住（设计稿里那处位置 bug）。
struct ChatDayPill: View {
    let label: String
    let visible: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 11.5))
            .tracking(0.34)
            .foregroundStyle(YY.ink500)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(YY.cream50.opacity(0.66), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(YY.shadowInk.opacity(0.1), lineWidth: 0.5) }
            .shadow(color: YY.shadowInk.opacity(0.1), radius: 1.5, y: 1)
            .opacity(visible ? 1 : 0)
            .animation(.sceneStandard(0.34), value: visible)
            .allowsHitTesting(false)
    }
}

extension ChatDayPill {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f
    }()

    static func label(for iso: String) -> String {
        guard let date = ChatTime.parse(iso) else { return "" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return dayFormatter.string(from: date)
    }
}
