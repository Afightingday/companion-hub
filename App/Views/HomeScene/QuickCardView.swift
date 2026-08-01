import SwiftUI

/// 速览卡 = 一张撕拉拍立得（图层化底卡 + 整卡覆膜）。
/// 1:1 移植 src/components/QuickCard.tsx：出现动画锚在 pet 一侧
///（去牵线口径，空间关系全靠 transformOrigin），三层压过外壳=标准模态。
/// 掀膜走原生 .pageCurl（CoverCurlView，B6）。撕开后整卡可点进入聊天。
struct QuickCardOverlay: View {
    let spec: PetSpec
    let petPos: CGPoint
    let preview: String
    let time: String
    var onClose: () -> Void
    var onEnter: () -> Void

    static let cardW: CGFloat = 246
    /// 整卡 3:4 图层底卡：round(246 × 1448 / 1086)
    static let artH: CGFloat = 328

    @State private var gone = false

    var body: some View {
        let w = Self.cardW
        let h = Self.artH
        let x = clamp(petPos.x - w / 2, 18, SceneTokens.designW - 18 - w)
        let below = petPos.y < 500
        let y = below
            ? clamp(petPos.y + 24, 130, 820 - h)
            : clamp(petPos.y - 186 - h, 110, 820 - h)
        let anchor = UnitPoint(x: (petPos.x - x) / w, y: below ? 0 : 1)

        ZStack(alignment: .topLeading) {
            // 遮罩：点哪都是收卡（含底栏区域）
            Rectangle()
                .fill(SceneTokens.scrim)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .transition(.opacity.animation(.easeInOut(duration: 0.24)))

            cardBody
                .frame(width: w, height: h)
                .offset(x: x, y: y)
                .transition(.asymmetric(
                    insertion: AnyTransition.modifier(
                        active: CardPopFx(opacity: 0, scale: 0.82, rotationDeg: spec.tilt * 2.2,
                                          dy: below ? -14 : 14, anchor: anchor),
                        identity: CardPopFx(opacity: 1, scale: 1, rotationDeg: spec.tilt,
                                            dy: 0, anchor: anchor))
                        .animation(.interpolatingSpring(mass: 0.9, stiffness: 320, damping: 24)),
                    removal: AnyTransition.modifier(
                        active: CardPopFx(opacity: 0, scale: 0.9, rotationDeg: spec.tilt * 1.6,
                                          dy: below ? -8 : 8, anchor: anchor),
                        identity: CardPopFx(opacity: 1, scale: 1, rotationDeg: spec.tilt,
                                            dy: 0, anchor: anchor))
                        .animation(.interpolatingSpring(mass: 0.9, stiffness: 320, damping: 24))))
        }
    }

    private var cardBody: some View {
        let ins = spec.coverInsets
        return ZStack(alignment: .topLeading) {
            SceneAsset.image(spec.cardArt)
                .resizable()
                .frame(width: Self.cardW, height: Self.artH)
                // 图层卡容器裸装：投影跟底卡 alpha 走（drop-shadow 0 14 30 / 0 4 9 对位）。
                // 投影不能包住 UIKit 翻页子树——SwiftUI 会按整块矩形描影，
                // 真机上就是卡后那团错位灰影（2026-08-01 实证）
                .shadow(color: SceneTokens.shadowInk.opacity(0.22), radius: 15, y: 14)
                .shadow(color: SceneTokens.shadowInk.opacity(0.12), radius: 4.5, y: 4)

            if !gone {
                // 翻页容器 = 膜的实测可见框（整卡内衬 insets），
                // 卷走的就是「真实大小的膜」，不带隐形透明边
                CoverCurlView(
                    coverPath: spec.coverArt,
                    cardPath: spec.cardArt,
                    preview: preview,
                    time: time,
                    cardSize: CGSize(width: Self.cardW, height: Self.artH),
                    insets: ins,
                    onCurlStart: { SoundPlayer.shared.play(.filmCurl) },
                    onCancelled: { SoundPlayer.shared.play(.filmCurl, volume: 0.5) },
                    onDone: {
                        gone = true
                        SoundPlayer.shared.play(.filmFly)
                        Haptic.lightTap()
                    })
                .frame(width: Self.cardW - ins.leading - ins.trailing,
                       height: Self.artH - ins.top - ins.bottom)
                .offset(x: ins.leading, y: ins.top)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if gone { onEnter() } // 撕开后整卡可点，不放内部按钮
        }
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(hi, max(lo, v))
    }
}

/// 出场/收场变换：绕 pet 侧锚点缩放+回转+纵向小位移
private struct CardPopFx: ViewModifier, Animatable {
    var opacity: CGFloat
    var scale: CGFloat
    var rotationDeg: CGFloat
    var dy: CGFloat
    let anchor: UnitPoint

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(opacity, scale), AnimatablePair(rotationDeg, dy)) }
        set {
            opacity = newValue.first.first
            scale = newValue.first.second
            rotationDeg = newValue.second.first
            dy = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotationDeg), anchor: anchor)
            .scaleEffect(scale, anchor: anchor)
            .offset(y: dy)
            .opacity(opacity)
    }
}
