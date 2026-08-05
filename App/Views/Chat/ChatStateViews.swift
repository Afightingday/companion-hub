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
