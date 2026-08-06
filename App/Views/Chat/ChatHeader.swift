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

/// 会话内搜索的结果卡（#12，照抄会话首页 SearchVeilView.resultsPanel 的形态）：
/// 清透玻璃、顶部向下按命中数自适应；命中多了卡内自己滚，不往键盘底下钻。
/// 底部输入条直接复用首页那枚 `NativeSearchBar`（UISearchBar 原件，
/// 自带放大镜/清空/取消与拼音组合期保护），在 ChatScreen.bottomBar 的 .search 档。
struct ChatSearchResultsCard: View {
    let hits: [ChatSearchHit]
    /// 这一轮检索是否已经回来（区分「找着呢」和「真没有」）
    let searched: Bool
    var onPick: (String) -> Void

    var body: some View {
        Group {
            if hits.isEmpty {
                Text(searched ? "没找着，换个词试试" : "找着呢…")
                    .font(.system(size: 13.5))
                    .foregroundStyle(YY.ink500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else {
                // 命中少就按内容长，多了封顶改卡内滚动（Spotlight 式）
                ViewThatFits(in: .vertical) {
                    hitList
                    ScrollView { hitList }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .frame(maxHeight: 420, alignment: .top)
    }

    private var hitList: some View {
        VStack(spacing: 0) {
            ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                if i > 0 {
                    Divider().overlay(YY.cream500.opacity(0.55))
                }
                Button {
                    onPick(hit.id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(hit.text)
                            .font(.system(size: 14.5))
                            .foregroundStyle(YY.ink700)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(PaperFormat.shortTime(hit.sentAt))
                            .font(.yyMono(11))
                            .foregroundStyle(YY.ink400)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
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
