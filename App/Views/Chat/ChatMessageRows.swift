import SwiftUI
import YushiKit

/// 长按菜单里的一项（用原生 .contextMenu 渲染，这里只描述语义）
enum ChatMessageAction {
    case edit, copy, quote, select, delete
}

/// 一条消息的一行。
/// 你的话＝一圈 2px 虚线，不填色；祐识那边的话不进任何容器，正文直接落在纸上。
/// 时间**完全不进流**：整点浮动胶囊是唯一的时间线索（不做左拖露时间）。
/// 送达状态只报**失败**，而且不写字只给图标 —— 寄出中什么都不显示。
struct ChatMessageRow: View {
    let message: UiMessage
    let selecting: Bool
    let picked: Bool
    let dimmed: Bool
    var onPick: () -> Void
    var onAction: (ChatMessageAction) -> Void

    private let bubbleShape = RoundedRectangle(cornerRadius: 19, style: .continuous)

    var body: some View {
        HStack(alignment: .bottom, spacing: 11) {
            if selecting {
                ChatSelectBox(picked: picked, action: onPick)
                    .padding(.bottom, 7)
            }

            if message.isUser {
                userBubble
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                agentBody
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(dimmed ? 0.42 : 1)
        .animation(.sceneStandard(0.3), value: dimmed)
    }

    // MARK: - 你的话

    private var userBubble: some View {
        HStack(alignment: .center, spacing: 9) {
            // 寄出中**什么都不显示**：从点发送到出字都是「在等模型」，
            // 拆成几个阶段报给用户没有意义（祐祐 2026-08-04）。只有失败才需要出面。
            Text(message.text)
                .font(.system(size: 17))
                .lineSpacing(17 * 0.3)
                .foregroundStyle(YY.ink700)
                .padding(.horizontal, 17)
                .padding(.vertical, 12)
                .overlay {
                    bubbleShape.strokeBorder(
                        YY.sage400,
                        style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                    )
                }
                .contentShape(.contextMenuPreview, bubbleShape)
                .frame(maxWidth: 288, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .chatMenu(isUser: true, enabled: !selecting, onAction: onAction)

            if message.status == .error {
                ChatFailMark(action: { onAction(.edit) })
            }
        }
        .animation(.sceneStandard(0.26), value: message.status)
    }

    // MARK: - 祐识那边的话

    private var agentBody: some View {
        Text(displayText)
            .font(.system(size: 17.5))
            .lineSpacing(17.5 * 0.4)
            .foregroundStyle(YY.ink700)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
            .chatMenu(isUser: false, enabled: !selecting, onAction: onAction)
    }

    /// 定稿才解析行内 Markdown；流式期间保持原文，否则每来一个字都重排一次版。
    ///
    /// 解析结果**必须走缓存**：这是个计算属性，body 每求值一次就重新解析一次整段正文。
    /// LazyVStack 在滚动中反复创建/求值行视图，于是每帧都在解 Markdown ——
    /// 「上下滑像掉帧」有它一份（祐祐 2026-08-05 真机反馈）。
    private var displayText: AttributedString {
        guard message.status == .done else { return AttributedString(message.text) }
        return ChatMarkdownCache.styled(id: message.id, text: message.text)
    }
}

/// 行内 Markdown 解析结果的缓存。按消息 id 存一份，正文变了才重解。
/// 刻意不做成 @Observable：它只是记忆，写它不该触发任何重绘。
@MainActor
enum ChatMarkdownCache {
    private static var store: [String: (source: String, styled: AttributedString)] = [:]
    private static var order: [String] = []
    private static let limit = 160

    static func styled(id: String, text: String) -> AttributedString {
        if let hit = store[id], hit.source == text { return hit.styled }
        let made = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        if store[id] == nil { order.append(id) }
        store[id] = (text, made)
        if order.count > limit {
            let drop = order.removeFirst()
            store.removeValue(forKey: drop)
        }
        return made
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
                .frame(width: 25, height: 25)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}

/// 未送达：气泡右侧一枚朱红小圈，轻点重发 —— 同样不写字，话留给 VoiceOver
struct ChatFailMark: View {
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        Button(action: action) {
            Circle()
                .strokeBorder(YY.danger, lineWidth: 1.6)
                .overlay {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(YY.danger)
                }
                .frame(width: 22, height: 22)
                .opacity(breathe ? 0.55 : 1)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.sceneStandard(0.9).repeatForever(autoreverses: true)) { breathe = true }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
        .accessibilityLabel("没送出去，轻点重发")
    }
}

/// 时间胶囊：**按整点**，不是日戳。滚动时跟手浮现，停手 1.2 秒淡掉。
/// 玻璃走系统原生液态玻璃。挂在滚动容器的 overlay 上，不进内容流——
/// 进内容流会被顶栏压住（设计稿里那处位置 bug）。
struct ChatTimePill: View {
    let label: String
    let visible: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(YY.ink500)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .yyGlassFloat(Capsule())
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.94)
            .animation(.sceneStandard(0.34), value: visible)
            .allowsHitTesting(false)
    }
}

extension ChatTimePill {
    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:00"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    /// 今天只报点，跨天才补上是哪天 —— 胶囊得短，长了就成横幅了
    static func label(for iso: String) -> String {
        guard let date = ChatTime.parse(iso) else { return "" }
        let clock = hourFormatter.string(from: date)
        if Calendar.current.isDateInToday(date) { return clock }
        if Calendar.current.isDateInYesterday(date) { return "昨天 " + clock }
        return dayFormatter.string(from: date) + " " + clock
    }
}
