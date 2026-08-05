import SwiftUI

/// 会话页的四副面孔。`.contact` ＝ 正在就地改备注（名字在导航栏标题位上直接变成输入框）。
///
/// 2026-08-05 上午一度把改备注做成独立面板（`ChatRenameSheet`），祐祐当天就否了
/// （「弹一张编辑面板就是不好不喜欢」）。**别再往面板方向走** ——
/// 要的是原位展开：点名字弹一张贴着它的小卡片（原生 Menu），选「改名字」就地变输入框。
enum ChatMode: Equatable {
    case idle, search, select, contact
}

/// 断网提示：不占导航栏的位置，作为一枚浮丸挂在栏下。
/// 底下垫玻璃 —— 光有虚线圈的话，正文从后面滚过去时字会糊在一起。
struct ChatOfflinePill: View {
    var body: some View {
        HStack(spacing: 7) {
            ChatPulseDot()
            Text("网络已断开")
                .font(.yyMono(11))
                .tracking(0.6)
                .foregroundStyle(YY.ink400)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 5)
        .yyGlassFloat(Capsule())
        .overlay {
            Capsule().strokeBorder(YY.ink300, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .transition(.opacity.combined(with: .offset(y: -6)))
        .allowsHitTesting(false)
    }
}

/// 会话内搜索：对位会话总览页的范式 —— 直接用那边同一枚 `NativeSearchBar`（UISearchBar 原件，
/// 自带放大镜/清空/取消与拼音组合期保护），贴在键盘上方。
/// 卷轴留在原地继续显示命中高亮；命中计数与上下跳做成一枚窄玻璃丸浮在搜索条正上方。
struct ChatSearchDock: View {
    @Binding var query: String
    let hitLabel: String
    var onPrev: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 9) {
            if hasQuery {
                HStack(spacing: 2) {
                    Text(hitLabel)
                        .font(.yyMono(12))
                        .tracking(0.5)
                        .foregroundStyle(YY.ink500)
                        .padding(.trailing, 6)
                    stepper("chevron.up", action: onPrev)
                    stepper("chevron.down", action: onNext)
                }
                .padding(.leading, 15)
                .padding(.trailing, 5)
                .padding(.vertical, 4)
                .yyGlassFloat(Capsule())
                .transition(.opacity.combined(with: .offset(y: 6)))
            }

            NativeSearchBar(text: $query, placeholder: "搜索这个对话", onCancel: onClose)
                .frame(height: 52)
        }
        .animation(.sceneStandard(0.24), value: hasQuery)
    }

    private func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(YY.ink500)
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 呼吸的小圆点（离线丸用）
struct ChatPulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(YY.ink400)
            .frame(width: 5, height: 5)
            .opacity(dim ? 0.35 : 1)
            .scaleEffect(dim ? 0.8 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.sceneStandard(0.8).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}
