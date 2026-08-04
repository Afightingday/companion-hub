import SwiftUI
import YushiKit

/// 写操作的盖章信笺 —— 全页唯一被允许升级成卡片的东西。
/// 批准＝盖下那枚「祐」印：抬起 → 压下 → 留一枚淡墨印，然后收成一张齿边回执。
struct ChatApprovalCard: View {
    let request: ApprovalRequest
    let status: ApprovalUiStatus
    var onDecide: (_ approvalId: String, _ decision: String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamping = false
    @State private var deciding = false

    private var danger: Bool {
        let copy = request.title + " " + (request.detail ?? "") + " " + request.kind
        return copy.contains("删除") || copy.contains("移除") || copy.contains("不可恢复")
            || copy.localizedCaseInsensitiveContains("delete")
    }

    private var accent: Color { danger ? YY.rose600 : YY.sage700 }
    private var sealAsset: String { danger ? "assets/chat/seal-rose.png" : "assets/chat/seal-you.png" }
    private var sprigAsset: String { danger ? "assets/chat/sprig-rose.png" : "assets/chat/sprig-sage.png" }

    var body: some View {
        Group {
            switch status {
            case .pending: pendingCard
            case .approved: receipt(approved: true)
            case .denied: receipt(approved: false)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    // MARK: - 待批

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 13) {
                SceneAsset.image(sprigAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 54)
                    .rotationEffect(.degrees(-8))
                    .shadow(color: YY.shadowInk.opacity(0.12), radius: 1, y: 1)
                    .overlay(alignment: .topTrailing) {
                        SceneAsset.image("assets/chat/gold-sparkles.png")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26)
                            .offset(x: 9, y: -2)
                    }
                    .accessibilityHidden(true)

                Text(request.title)
                    .font(.system(size: 26, weight: .heavy))
                    .lineSpacing(26 * 0.3)
                    .kerning(0.26)
                    .foregroundStyle(danger ? YY.rose600 : YY.ink800)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !metaLines.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(metaLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: line.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(danger ? YY.rose500 : YY.sage600)
                                .frame(width: 19)
                            Text(line.text)
                                .font(.system(size: 16.5))
                                .foregroundStyle(YY.ink700)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 14)
            }

            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: 190, y: 0))
            }
            .stroke(
                danger ? YY.rose400 : YY.sage300,
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
            .frame(width: 190, height: 1.5)
            .padding(.top, 16)

            HStack(spacing: 9) {
                Image(systemName: danger ? "exclamationmark.circle" : "heart.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(danger ? YY.danger : YY.rose500)
                Text(danger ? "确认后不可恢复" : "需要你点个头")
                    .font(.system(size: 16.5))
                    .foregroundStyle(YY.ink700)
            }
            .padding(.top, 14)

            Button {
                guard !deciding else { return }
                deciding = true
                Haptic.lightTap()
                onDecide(request.id, "deny")
            } label: {
                Text("先不了")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(YY.ink400)
                    .overlay(alignment: .bottom) {
                        Path { p in
                            p.move(to: .zero)
                            p.addLine(to: CGPoint(x: 47, y: 0))
                        }
                        .stroke(YY.cream600, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 47, height: 1.5)
                        .offset(y: 5)
                    }
            }
            .buttonStyle(.plain)
            .disabled(deciding)
            .padding(.top, 12)
        }
        .padding(.leading, 22)
        .padding(.trailing, 112)      // 给右下那枚印章留出地方
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YY.cream50, in: RoundedRectangle(cornerRadius: YY.rXL, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: YY.rXL, style: .continuous)
                .strokeBorder(danger ? YY.rose200 : YY.borderHair, lineWidth: 1)
        }
        .yyShadowMD()
        // 垫在底下、歪出边界的那张纸：走 background 不进布局足迹，不会把父容器撑歪
        .background {
            RoundedRectangle(cornerRadius: YY.rXL, style: .continuous)
                .fill(danger ? YY.rose300 : YY.sage200)
                .rotationEffect(.degrees(2.2))
                .padding(EdgeInsets(top: 10, leading: 12, bottom: -12, trailing: -10))
                .shadow(color: YY.shadowInk.opacity(0.06), radius: 1, y: 1)
        }
        .overlay(alignment: .bottomTrailing) { sealButton }
    }

    private var sealButton: some View {
        VStack(spacing: 5) {
            ZStack {
                // 压下去留下的淡墨印
                SceneAsset.image(sealAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .opacity(stamping ? 0.2 : 0)
                    .animation(.sceneOut(0.34).delay(0.22), value: stamping)

                SceneAsset.image(sealAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .shadow(color: YY.shadowInk.opacity(0.1), radius: 1, y: 1)
                    .keyframeAnimator(
                        initialValue: StampPose(),
                        trigger: stamping
                    ) { content, pose in
                        content
                            .scaleEffect(pose.scale)
                            .offset(y: pose.lift)
                            .rotationEffect(.degrees(-3))
                    } keyframes: { _ in
                        KeyframeTrack(\.lift) {
                            CubicKeyframe(0, duration: 0.001)
                            CubicKeyframe(-13, duration: 0.162)
                            CubicKeyframe(3, duration: 0.186)
                            CubicKeyframe(0, duration: 0.104)
                            CubicKeyframe(0, duration: 0.127)
                        }
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(1, duration: 0.001)
                            CubicKeyframe(1.12, duration: 0.162)
                            CubicKeyframe(0.95, duration: 0.186)
                            CubicKeyframe(1.02, duration: 0.104)
                            CubicKeyframe(1, duration: 0.127)
                        }
                    }
            }
            Text(danger ? "确认删除" : "盖章批准")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(accent)
        }
        .padding(.trailing, 18)
        .padding(.bottom, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: approve)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(danger ? "确认删除" : "盖章批准")
    }

    private func approve() {
        guard !deciding else { return }
        deciding = true
        Haptic.softTap()
        if reduceMotion {
            onDecide(request.id, "approve")
            return
        }
        stamping = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(560))
            onDecide(request.id, "approve")
        }
    }

    // MARK: - 回执（齿边小票）

    private func receipt(approved: Bool) -> some View {
        HStack(spacing: 14) {
            SceneAsset.image(sprigAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .rotationEffect(.degrees(-8))
                .opacity(0.92)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.title)
                    .font(.system(size: 17.5, weight: .bold))
                    .foregroundStyle(YY.ink800)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: approved ? "checkmark" : "xmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text(approved ? "已记入" : "没有寄出")
                }
                .font(.system(size: 13))
                .foregroundStyle(YY.ink400)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 22)
        .padding(.trailing, 84)
        .padding(.vertical, 16)
        .frame(maxWidth: 334, alignment: .leading)
        .background(YY.cream50, in: RoundedRectangle(cornerRadius: YY.rLG, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: YY.rLG, style: .continuous)
                .strokeBorder(YY.borderHair, lineWidth: 1)
        }
        // 齿口：两枚页色半圆咬进上下边（对位 CSS 的 ::before / ::after）
        .overlay(alignment: .topTrailing) { notch(up: false) }
        .overlay(alignment: .bottomTrailing) { notch(up: true) }
        .overlay(alignment: .trailing) {
            GeometryReader { proxy in
                Path { p in
                    p.move(to: CGPoint(x: 0.75, y: 0))
                    p.addLine(to: CGPoint(x: 0.75, y: proxy.size.height))
                }
                .stroke(YY.cream600, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            .frame(width: 1.5)
            .padding(.vertical, 12)
            .padding(.trailing, 72)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .trailing) {
            SceneAsset.image(sealAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .rotationEffect(.degrees(-4))
                .opacity(approved ? 0.5 : 0.22)
                .padding(.trailing, 14)
                .accessibilityHidden(true)
        }
        .shadow(color: YY.shadowInk.opacity(0.1), radius: 3, y: 3)
    }

    /// 咬进上下边的半圆齿口。用页色填充盖住卡片边，不做形状相减——相减要 even-odd 填充，
    /// 走 background(_, in:) 拿不到。
    private func notch(up: Bool) -> some View {
        Circle()
            .fill(YY.page)
            .overlay {
                Circle().strokeBorder(danger ? YY.rose200 : YY.borderHair, lineWidth: 1)
            }
            .frame(width: 22, height: 22)
            // up=true 取圆的上半（咬进下边），否则取下半（咬进上边）
            .frame(width: 22, height: 11, alignment: up ? .top : .bottom)
            .clipped()
            .padding(.trailing, 50)
            .accessibilityHidden(true)
    }

    // MARK: - detail → 带图标的信息行

    private struct MetaLine {
        var icon: String
        var text: String
    }

    private var metaLines: [MetaLine] {
        guard let detail = request.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty else { return [] }
        return detail.split(separator: "\n").map { raw in
            let text = String(raw).trimmingCharacters(in: .whitespaces)
            return MetaLine(icon: Self.metaIcon(for: text), text: text)
        }
    }

    private static func metaIcon(for text: String) -> String {
        if text.contains("提醒") || text.contains("闹") { return "bell" }
        if text.contains("月") || text.contains("日") || text.contains(":") { return "calendar" }
        if text.contains("删除") || text.contains("移除") { return "trash" }
        if text.contains("发送") || text.contains("寄") { return "paperplane" }
        return "circle.dashed"
    }
}

private struct StampPose {
    var lift: CGFloat = 0
    var scale: CGFloat = 1
}
