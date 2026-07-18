import SwiftUI

/// 一枚动画 = 标题 + 循环时长 + 「相位 → 画面」纯函数。
/// phase ∈ [0,1) 覆盖整个循环(含停顿);播放器只负责推进相位。
struct MotionSpec: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    /// 一轮总时长(秒,含呼吸停顿)
    let cycle: Double
    let draw: (_ context: inout GraphicsContext, _ size: CGFloat, _ phase: Double, _ dark: Bool) -> Void
}

// MARK: - Thinking|寻径

/// 一根墨线沿闭合游走路线永续行进:两次接近自己却不闭合,
/// 相位扭曲带来「试探‐迟疑」,窗口呼吸带来「生长」。无缝循环。
enum PathfindingMotion {
    static let cycle = 2.3

    /// 强非凸流形:北侧浅湾 + 东南「峡湾」(进湾-U 折-贴旧迹扫出)
    /// 自距实测:峡湾走廊 ~0.104,西侧并行 ~0.147(单位空间)
    static let route = SampledPath.closedCatmullRom([
        CGPoint(x: 0.22, y: 0.50),
        CGPoint(x: 0.30, y: 0.30),
        CGPoint(x: 0.50, y: 0.21),
        CGPoint(x: 0.60, y: 0.33),    // 北湾浅探(第三次远眺)
        CGPoint(x: 0.74, y: 0.23),
        CGPoint(x: 0.84, y: 0.38),
        CGPoint(x: 0.78, y: 0.54),    // 东侧转入
        CGPoint(x: 0.60, y: 0.505),   // 峡湾上壁,向西
        CGPoint(x: 0.47, y: 0.57),    // 湾尖 U 折
        CGPoint(x: 0.58, y: 0.66),    // 峡湾下壁,折返向东
        CGPoint(x: 0.34, y: 0.735),   // 底部横扫,从湾尖下方掠过
        CGPoint(x: 0.19, y: 0.61),
    ])

    static let winBase = 0.48
    static let winBreath = 0.09
    static let winBreathPhase = 4.2
    static let warpA1 = 0.20, warpPhi1 = 0.30
    static let warpA2 = 0.16, warpPhi2 = 0.05
    static let tailTaper = 0.60
    static let widthScale: CGFloat = 0.95

    /// 相位扭曲:w(p+1) = w(p)+1,保证无缝;两阶正弦对应两处湾的迟疑
    static func warp(_ p: Double) -> Double {
        p + warpA1 * sin(2 * .pi * (p + warpPhi1)) / (2 * .pi)
          + warpA2 * sin(4 * .pi * (p + warpPhi2)) / (4 * .pi)
    }

    static let spec = MotionSpec(
        id: "thinking-pathfinding",
        title: "Thinking|寻径",
        subtitle: "2.3s · 无缝 · 纯墨",
        cycle: cycle
    ) { context, size, phase, dark in
        let m = PathfindingMotion.self
        let head = m.warp(phase)
        let win = m.winBase + m.winBreath * sin(2 * .pi * phase + m.winBreathPhase)
        m.route.drawWindow(
            in: &context, size: size, tail: head - win, head: head,
            style: .init(
                color: MotionPalette.stroke(dark: dark),
                width: MotionLineWidth.width(for: size) * m.widthScale,
                taper: m.tailTaper,
                wrap: true
            )
        )
    }
}

// MARK: - 搜索|听雨

/// 两条极细弧线错峰掠过;B 头抵达交点、A 尾尚覆盖交点的瞬间,
/// 一粒雨蓝辉光绽放又收敛。活动 1.5s + 呼吸停顿 0.35s。
enum RainListeningMotion {
    static let active = 1.5
    static let rest = 0.35
    static var cycle: Double { active + rest }

    static let cross = CGPoint(x: 0.56, y: 0.47)
    /// A:左上 → 右下(缓,弓向下);B:左下 → 右上(陡,弓向右,是「回应」)
    static let arcA = SampledPath.quadThrough(CGPoint(x: -0.06, y: 0.24), cross, CGPoint(x: 1.06, y: 0.55))
    static let arcB = SampledPath.quadThrough(CGPoint(x: 0.24, y: 1.06), cross, CGPoint(x: 0.66, y: -0.06))
    static let spanA = (t0: 0.06, t1: 0.86)
    static let spanB = (t0: 0.20, t1: 0.98)

    static let cometLen = 0.42
    static let easeMix = 0.35
    static let widthScale: CGFloat = 0.78
    static let dotAt = 0.494
    static let dotRise = 0.03, dotFall = 0.11
    static let dotRadius: CGFloat = 1.1
    static let tailTaper = 0.58

    static let spec = MotionSpec(
        id: "search-rain",
        title: "搜索|听雨",
        subtitle: "1.5s + 0.35s 停顿 · 雨蓝",
        cycle: cycle
    ) { context, size, phase, dark in
        let m = RainListeningMotion.self
        // 相位映射到活动段;越界即呼吸停顿(留白)
        let p = phase * m.cycle / m.active
        guard p < 1 else { return }

        let w = MotionLineWidth.width(for: size) * m.widthScale
        let ink = MotionPalette.stroke(dark: dark)

        for (span, path) in [(m.spanA, m.arcA), (m.spanB, m.arcB)] {
            guard p >= span.t0, p <= span.t1 else { continue }
            let u = (p - span.t0) / (span.t1 - span.t0)
            let eased = MotionEase.lerp(u, MotionEase.easeInOutSine(u), m.easeMix)
            let head = eased * (1 + m.cometLen)
            path.drawWindow(
                in: &context, size: size, tail: head - m.cometLen, head: head,
                style: .init(color: ink, width: w, taper: m.tailTaper, wrap: false)
            )
        }

        // 雨蓝微点:一次微小的辉光,不是气球
        let t = p - m.dotAt
        if t > 0, t < m.dotRise + m.dotFall {
            let rise = MotionEase.clamp01(t / m.dotRise)
            let fall = MotionEase.clamp01((t - m.dotRise) / m.dotFall)
            let alpha = MotionEase.easeOutCubic(rise) * (1 - MotionEase.easeInQuad(fall))
            let r = m.dotRadius * w * (0.55 + 0.45 * CGFloat(MotionEase.easeOutCubic(rise)))
            let blue = MotionPalette.rain(dark: dark)
            let center = m.cross.scaled(by: size)

            let halo = r * 1.6
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - halo, y: center.y - halo,
                    width: halo * 2, height: halo * 2
                )),
                with: .color(blue.opacity(alpha * 0.15))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - r, y: center.y - r,
                    width: r * 2, height: r * 2
                )),
                with: .color(blue.opacity(alpha * 0.9))
            )
        }
    }
}

/// 展板注册表(顺序即展示顺序)
enum MotionCatalog {
    static let all: [MotionSpec] = [
        PathfindingMotion.spec,
        RainListeningMotion.spec,
    ]
}
