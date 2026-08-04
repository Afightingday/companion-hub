import SwiftUI

/// 新对话空态：一枚「祐」印 + 两笔手绘点缀，下面三条虚线胶囊是可以直接点的开场白。
struct ChatEmptyState: View {
    let seeds: [String]
    var onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                SceneAsset.image("assets/chat/seal-you.png")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .opacity(0.9)

                SceneAsset.image("assets/chat/gold-sparkles.png")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34)
                    .opacity(0.45)
                    .offset(x: 42, y: -38)

                SceneAsset.image("assets/chat/swoosh.png")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58)
                    .opacity(0.22)
                    .offset(x: -33, y: 42)
            }
            .frame(width: 150, height: 120)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                ForEach(seeds, id: \.self) { seed in
                    Button { onPick(seed) } label: {
                        Text(seed)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(YY.sage700)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
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
            .padding(.horizontal, 14)
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
            .font(.yyMono(10.5))
            .tracking(0.63)
            .foregroundStyle(YY.ink500)
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(YY.cream50.opacity(0.82), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(YY.shadowInk.opacity(0.12), lineWidth: 0.5) }
            .shadow(color: YY.shadowInk.opacity(0.1), radius: 4, y: 2)
            .transition(.opacity)
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
        .padding(.horizontal, 20)
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
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .yyGlassPill(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .opacity(active ? 1 : 0.32)
        .animation(.sceneStandard(0.24), value: active)
        .accessibilityLabel(label)
    }
}
