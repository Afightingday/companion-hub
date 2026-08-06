import SwiftUI

/// 新对话空态：一枚「祐」印 + 三条可直接点的开场白胶囊。
/// 点缀**只留印章** —— 星芒与 swoosh 底纹图里本来就有（见 ChatBackdrop），
/// 这儿再摆一份就成了重影。
struct ChatEmptyState: View {
    let seeds: [String]
    var onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 34) {
            SceneAsset.image("assets/chat/seal-you.png")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .opacity(0.9)
                .frame(height: 110)
                .accessibilityHidden(true)

            VStack(spacing: 11) {
                ForEach(seeds, id: \.self) { seed in
                    Button { onPick(seed) } label: {
                        Text(seed)
                            .font(.system(size: 16.5, weight: .medium))
                            .foregroundStyle(YY.sage700)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        YY.sage400,
                                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .offset(y: 7)))
    }
}

/// 顶部飘一下就走的窄提示（已拷贝 / 已删除 / 附件通道还没接上）
struct ChatToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13.5))
            .foregroundStyle(YY.ink500)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .yyGlassFloat(Capsule())
            .transition(.opacity.combined(with: .offset(y: -6)))
            .allowsHitTesting(false)
    }
}

/// 多选时贴在底部的两枚磨砂圆钮：分享 / 删除。删除走系统原生动作单二次确认。
struct ChatSelectionBar: View {
    let count: Int
    var onShare: () -> Void
    var onDelete: () -> Void

    private var active: Bool { count > 0 }

    var body: some View {
        HStack {
            toolButton("square.and.arrow.up", tint: YY.sage600, label: "分享", action: onShare)
            Spacer()
            toolButton("trash", tint: YY.danger, label: "删除", action: onDelete)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .transition(.opacity.combined(with: .offset(y: 7)))
    }

    private func toolButton(
        _ symbol: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .yyGlassControl(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .opacity(active ? 1 : 0.32)
        .animation(.sceneStandard(0.24), value: active)
        .accessibilityLabel(label)
    }
}

/// 统一的报错行（2026-08-06 #14）：一枚手绕的重来圈 + 一句短话，纸白药丸垫底。
/// 会话页所有「坏了、可以再试」的地方都用这一张脸 ——
/// 正文没写完 / 被打断、自己的话没寄出去、历史拉不下来，只分两种口气：
/// `muted`（自己停的、不算事故）走墨灰，`danger`（真失败）走朱陶红。
/// 具体原因不上屏（原始报错常常又长又洋），留给 VoiceOver。
struct ChatErrorNote: View {
    enum Tone { case muted, danger }

    let text: String
    let tone: Tone
    var detail: String?
    var onTap: () -> Void

    private var ink: Color { tone == .danger ? YY.rose600 : YY.ink400 }

    var body: some View {
        Button {
            Haptic.lightTap()
            onTap()
        } label: {
            HStack(spacing: 8) {
                GlyphRetry()
                    .stroke(style: YYGlyph.stroke(1.6))
                    .frame(width: 16, height: 16)
                Text(text)
                    .font(.system(size: 14))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(YY.cream50.opacity(0.9), in: Capsule())
            .overlay {
                Capsule().strokeBorder(tone == .danger ? YY.rose300 : YY.borderHair, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detail ?? text)
    }
}

/// 「在想了」——寄出之后、第一个字之前的那一两秒里唯一的动静。
///
/// 刻意不写字：`状态不写字` 是定过的口径（只报失败）。这里只是一枚呼吸的墨点，
/// 大小跟正文行高同量级，不占版面、不成卡片。一有内容或过程链就让位。
struct ChatThinkingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(YY.ink300)
            .frame(width: 7, height: 7)
            .scaleEffect(breathing ? 1 : 0.55)
            .opacity(breathing ? 0.9 : 0.35)
            .frame(height: 22, alignment: .center)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
            .accessibilityLabel("正在回想")
    }
}
