import SwiftUI

/// 一枚动画 = 标题 + 循环时长 + 「相位 → 画面」纯函数。
/// phase ∈ [0,1) 覆盖整个循环(含停顿);播放器只负责推进相位。
/// 设计原则(2026-07-18 用户确认):动画要能让人自然联想到对应功能,
/// 用独特有设计感的隐喻,不用放大镜/齿轮等通用图标;文字仍兜底说明。
struct MotionSpec: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    /// 一轮总时长(秒,含呼吸停顿)
    let cycle: Double
    let draw: (_ context: inout GraphicsContext, _ size: CGFloat, _ phase: Double, _ dark: Bool) -> Void
}

// MARK: - Thinking|起草

/// 看不见的笔在写草稿:连笔字形的起伏(不可读的行书),词间提笔,
/// 写完悬置一拍,墨入水般下沉消散,新句已经开笔——永远未完成的草稿。
/// 双句各占半周期交叠,无缝连续。常量与草样 1:1。
enum DraftingMotion {
    static let cycle = 3.6

    struct Phrase {
        let paths: [SampledPath]
        let spans: [(Double, Double)]
    }

    static let wordGap = 0.05

    /// 每句 = 若干笔画(词);隆起间距须 ≳ 2× 线宽,否则墨挤成团
    static let phrases: [Phrase] = {
        let strokeSets: [[[CGPoint]]] = [
            [
                [CGPoint(x: 0.10, y: 0.420), CGPoint(x: 0.155, y: 0.315), CGPoint(x: 0.21, y: 0.435),
                 CGPoint(x: 0.265, y: 0.320), CGPoint(x: 0.32, y: 0.440)],
                [CGPoint(x: 0.40, y: 0.435), CGPoint(x: 0.435, y: 0.240), CGPoint(x: 0.475, y: 0.440),
                 CGPoint(x: 0.545, y: 0.325), CGPoint(x: 0.615, y: 0.450), CGPoint(x: 0.70, y: 0.360)],
            ],
            [
                [CGPoint(x: 0.14, y: 0.655), CGPoint(x: 0.19, y: 0.540), CGPoint(x: 0.245, y: 0.660),
                 CGPoint(x: 0.30, y: 0.550), CGPoint(x: 0.355, y: 0.665)],
                [CGPoint(x: 0.43, y: 0.660), CGPoint(x: 0.50, y: 0.535), CGPoint(x: 0.565, y: 0.670),
                 CGPoint(x: 0.65, y: 0.560)],
            ],
        ]
        return strokeSets.map { strokes in
            let gap = DraftingMotion.wordGap
            let paths = strokes.map { SampledPath.openCatmullRom($0) }
            let totalLen = paths.reduce(CGFloat(0)) { $0 + $1.total }
            let gaps = Double(paths.count - 1) * gap
            var spans: [(Double, Double)] = []
            var t = 0.0
            for path in paths {
                let share = (1 - gaps) * Double(path.total / totalLen)
                spans.append((t, t + share))
                t += share + gap
            }
            return Phrase(paths: paths, spans: spans)
        }
    }()

    static let writeEnd = 0.34     // 句内相位:书写结束(写得轻快)
    static let holdEnd = 0.50      // 写完悬置一拍再化(读得完)
    static let fadeEnd = 0.66      // 消散完毕(避免两句同显吵)
    static let sinkDrift: CGFloat = 0.022   // 消散时墨微微下沉
    static let agingTaper = 0.04   // 句首湿墨线索,若有似无
    static let widthScale: CGFloat = 0.62   // 笔要细,字形才透气

    /// 句内相位 pLocal ∈ [0,1):书写 [0,writeEnd] → 悬置 → 消散 [holdEnd,fadeEnd]
    static func drawPhrase(_ context: inout GraphicsContext, size: CGFloat, pLocal: Double, phrase: Phrase, dark: Bool) {
        let color = MotionPalette.stroke(dark: dark)
        let w = MotionLineWidth.width(for: size) * widthScale
        var masterAlpha = 1.0
        var drift = CGPoint.zero
        var writeP = 1.0
        if pLocal < writeEnd {
            writeP = pLocal / writeEnd
        } else if pLocal >= holdEnd {
            let q = MotionEase.clamp01((pLocal - holdEnd) / (fadeEnd - holdEnd))
            if q >= 1 { return }
            masterAlpha = 1 - MotionEase.smoothstep(q)
            drift = CGPoint(x: 0, y: sinkDrift * CGFloat(q))
        }
        for (i, path) in phrase.paths.enumerated() {
            let (t0, t1) = phrase.spans[i]
            let prog: Double
            if writeP >= t1 {
                prog = 1
            } else if writeP <= t0 {
                continue     // 该词尚未起笔(或正处词间提笔)
            } else {
                prog = (writeP - t0) / (t1 - t0)
            }
            let writing = prog < 1
            path.drawWindow(
                in: &context, size: size, tail: 0, head: prog,
                style: .init(
                    color: color, width: w, taper: agingTaper, wrap: false,
                    masterAlpha: masterAlpha, drift: drift,
                    headDot: writing || pLocal < holdEnd
                )
            )
        }
    }

    static let spec = MotionSpec(
        id: "thinking-drafting",
        title: "Thinking|起草",
        subtitle: "3.6s · 双句交叠 · 无缝 · 纯墨",
        cycle: cycle
    ) { context, size, phase, dark in
        let m = DraftingMotion.self
        // 两句各偏移半周期,任一时刻总有一句在动
        for k in 0..<2 {
            let shifted = phase - Double(k) * 0.5
            let pLocal = (shifted.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
            m.drawPhrase(&context, size: size, pLocal: pLocal, phrase: m.phrases[k], dark: dark)
        }
    }
}

// MARK: - 搜索|拾音

/// 几粒淡墨微点如雨错峰散落(候选的「声音」),极细墨线巡访而过,
/// 经过一粒它便微微一亮;在目标前减速停驻——雨蓝辉光 + 一圈发丝涟漪,
/// 线被吸入,其余微点淡去。活动 1.7s + 呼吸停顿 0.4s。常量与草样 1:1。
enum PickupMotion {
    static let active = 1.7
    static let rest = 0.4
    static var cycle: Double { active + rest }

    /// 巡访路线:入场 → 经过 3 粒 → 钩入目标
    static let routePts: [CGPoint] = [
        CGPoint(x: -0.06, y: 0.36), CGPoint(x: 0.25, y: 0.30), CGPoint(x: 0.55, y: 0.26),
        CGPoint(x: 0.78, y: 0.46), CGPoint(x: 0.52, y: 0.62),
    ]
    static let route = SampledPath.openCatmullRom(routePts, perSegment: 64)
    static let specks: [CGPoint] = [
        CGPoint(x: 0.25, y: 0.30), CGPoint(x: 0.55, y: 0.26), CGPoint(x: 0.78, y: 0.46),
    ]
    static let extraSpeck = CGPoint(x: 0.80, y: 0.72)   // 未被巡访的一粒(「大量」感)
    static let target = CGPoint(x: 0.52, y: 0.62)
    /// 微点在路线上的最近弧长分数(草样 nearestFraction 实测;routePts 变则需重测)
    static let speckFractions: [Double] = [0.253, 0.497, 0.751]

    static let cometLen = 0.22
    static let widthScale: CGFloat = 0.78
    static let speckR: CGFloat = 0.62      // × 线宽(微点是耳语,不是波点)
    static let targetR: CGFloat = 0.72
    static let speckAlpha = 0.22
    static let flickAlpha = 0.50           // 被经过瞬间
    static let flickHalf = 0.045           // 亮度脉冲半宽(按头部弧长分数)
    static let spawnSpan = (t0: 0.02, t1: 0.18)   // 微点错峰浮现
    static let targetBorn = 0.14
    static let travelSpan = (t0: 0.10, t1: 0.68)  // 头部行进(带减速落点)
    static let travelEase = 0.60
    static let absorbSpan = (t0: 0.70, t1: 0.86)  // 线被目标吸入
    static let bloomAt = 0.68
    static let bloomRise = 0.04, bloomFall = 0.20
    static let bloomR: CGFloat = 0.95      // × 线宽(核心);光晕 ×1.7
    static let rippleSpan = (t0: 0.68, t1: 0.94)
    static let rippleR = (r0: CGFloat(1.6), r1: CGFloat(4.2))   // 一圈细纹,不是声呐
    static let othersFade = (t0: 0.78, t1: 0.96)
    static let targetFade = (t0: 0.88, t1: 0.98)
    static let tailTaper = 0.55

    static func fillDot(_ context: inout GraphicsContext, center: CGPoint, size: CGFloat, radius: CGFloat, color: Color, alpha: Double) {
        guard alpha > 0.003 else { return }
        let c = CGPoint(x: center.x * size, y: center.y * size)
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(color.opacity(alpha))
        )
    }

    static let spec = MotionSpec(
        id: "search-pickup",
        title: "搜索|拾音",
        subtitle: "1.7s + 0.4s 停顿 · 雨蓝命中",
        cycle: cycle
    ) { context, size, phase, dark in
        let m = PickupMotion.self
        let p = phase * m.cycle / m.active
        guard p < 1 else { return }
        let w = MotionLineWidth.width(for: size) * m.widthScale
        let ink = MotionPalette.stroke(dark: dark)
        let blue = MotionPalette.rain(dark: dark)

        // 头部行进(减速落点)与吸入
        let u = MotionEase.clamp01((p - m.travelSpan.t0) / (m.travelSpan.t1 - m.travelSpan.t0))
        let head = MotionEase.lerp(u, MotionEase.easeOutCubic(u), m.travelEase)
        var tail = head - m.cometLen
        if p > m.absorbSpan.t0 {
            let q = MotionEase.clamp01((p - m.absorbSpan.t0) / (m.absorbSpan.t1 - m.absorbSpan.t0))
            tail = MotionEase.lerp(head - m.cometLen, 1, MotionEase.smoothstep(q))
        }

        // 微点(候选)
        let specksAll = m.specks + [m.extraSpeck]
        for (i, s) in specksAll.enumerated() {
            let born = MotionEase.lerp(m.spawnSpan.t0, m.spawnSpan.t1, Double(i) / Double(max(1, specksAll.count - 1)))
            if p < born { continue }
            let grow = MotionEase.smoothstep(MotionEase.clamp01((p - born) / 0.06))
            var a = m.speckAlpha * grow
            var r = m.speckR * w * (1.35 - 0.35 * CGFloat(grow))
            // 巡访微亮
            if i < m.speckFractions.count, p >= m.travelSpan.t0, p <= m.travelSpan.t1 + 0.02 {
                let d = abs(head - m.speckFractions[i])
                if d < m.flickHalf {
                    let boost = 1 - d / m.flickHalf
                    a = MotionEase.lerp(a, m.flickAlpha, MotionEase.smoothstep(boost))
                    r *= 1 + 0.12 * CGFloat(boost)
                }
            }
            // 其余淡去
            if p > m.othersFade.t0 {
                let q = MotionEase.clamp01((p - m.othersFade.t0) / (m.othersFade.t1 - m.othersFade.t0))
                a *= 1 - MotionEase.smoothstep(q)
            }
            m.fillDot(&context, center: s, size: size, radius: r, color: ink, alpha: a)
        }

        // 目标微点(也随雨错峰落下;最后随蓝一起淡去)
        if p >= m.targetBorn {
            let grow = MotionEase.smoothstep(MotionEase.clamp01((p - m.targetBorn) / 0.06))
            var a = (m.speckAlpha + 0.10) * grow
            let r = m.targetR * w * (1.35 - 0.35 * CGFloat(grow))
            if p > m.targetFade.t0 {
                let q = MotionEase.clamp01((p - m.targetFade.t0) / (m.targetFade.t1 - m.targetFade.t0))
                a *= 1 - MotionEase.smoothstep(q)
            }
            m.fillDot(&context, center: m.target, size: size, radius: r, color: ink, alpha: a)
        }

        // 巡访线
        if p >= m.travelSpan.t0, tail < 1 {
            m.route.drawWindow(
                in: &context, size: size, tail: tail, head: head,
                style: .init(
                    color: ink, width: w, taper: m.tailTaper, wrap: false,
                    headDot: head < 0.999
                )
            )
        }

        // 命中:雨蓝辉光
        let tb = p - m.bloomAt
        if tb > 0, tb < m.bloomRise + m.bloomFall {
            let rise = MotionEase.clamp01(tb / m.bloomRise)
            let fall = MotionEase.clamp01((tb - m.bloomRise) / m.bloomFall)
            let alpha = MotionEase.easeOutCubic(rise) * (1 - MotionEase.easeInQuad(fall))
            let r = m.bloomR * w * (0.55 + 0.45 * CGFloat(MotionEase.easeOutCubic(rise)))
            m.fillDot(&context, center: m.target, size: size, radius: r * 1.7, color: blue, alpha: alpha * 0.15)
            m.fillDot(&context, center: m.target, size: size, radius: r, color: blue, alpha: alpha * 0.9)
        }

        // 命中:一圈发丝涟漪
        if p >= m.rippleSpan.t0, p <= m.rippleSpan.t1 {
            let q = (p - m.rippleSpan.t0) / (m.rippleSpan.t1 - m.rippleSpan.t0)
            let rr = MotionEase.lerp(Double(m.rippleR.r0), Double(m.rippleR.r1), MotionEase.easeOutCubic(q)) * Double(w)
            let center = CGPoint(x: m.target.x * size, y: m.target.y * size)
            let radius = CGFloat(rr)
            let lineWidth = max(0.4, w * 0.35 * CGFloat(1 - q))
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(blue.opacity(0.30 * (1 - q))),
                style: StrokeStyle(lineWidth: lineWidth)
            )
        }
    }
}

/// 展板注册表(顺序即展示顺序)
enum MotionCatalog {
    static let all: [MotionSpec] = [
        DraftingMotion.spec,
        PickupMotion.spec,
    ]
}
