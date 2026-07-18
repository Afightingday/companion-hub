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

// MARK: - Thinking|起草(可见笔)

/// 一支线艺勾勒的笔正在写不可读的行书:笔随书写微颤,词间小提笔,
/// 写完悬笔一拍(在想),再大提笔换行;写过的句子墨入水般下沉消散。
/// 笔尖位置全程连续,双句各占半周期,无缝。常量与草样 1:1。
enum DraftingMotion {
    static let cycle = 3.6

    struct Phrase {
        let paths: [SampledPath]
        let spans: [(Double, Double)]
    }

    static let wordGap = 0.14      // 词间提笔占书写段比例(提笔要看得见)

    /// 每句 = 若干笔画(词);隆起间距须 ≳ 2× 线宽,否则墨挤成团
    static let phrases: [Phrase] = {
        let strokeSets: [[[CGPoint]]] = [
            [
                [CGPoint(x: 0.10, y: 0.475), CGPoint(x: 0.155, y: 0.370), CGPoint(x: 0.21, y: 0.490),
                 CGPoint(x: 0.265, y: 0.375), CGPoint(x: 0.32, y: 0.495)],
                [CGPoint(x: 0.40, y: 0.490), CGPoint(x: 0.435, y: 0.295), CGPoint(x: 0.475, y: 0.495),
                 CGPoint(x: 0.545, y: 0.380), CGPoint(x: 0.615, y: 0.505), CGPoint(x: 0.70, y: 0.415)],
            ],
            [
                [CGPoint(x: 0.14, y: 0.700), CGPoint(x: 0.19, y: 0.585), CGPoint(x: 0.245, y: 0.705),
                 CGPoint(x: 0.30, y: 0.595), CGPoint(x: 0.355, y: 0.710)],
                [CGPoint(x: 0.43, y: 0.705), CGPoint(x: 0.50, y: 0.580), CGPoint(x: 0.565, y: 0.715),
                 CGPoint(x: 0.65, y: 0.605)],
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

    static let writeEnd = 0.38     // 句内相位:书写结束(半窗 0.5 内含悬笔+换行)
    static let holdEnd = 0.50      // 悬置结束、开始消散
    static let fadeEnd = 0.66      // 消散完毕
    static let sinkDrift: CGFloat = 0.022
    static let agingTaper = 0.04
    static let widthScale: CGFloat = 0.62   // 字迹比笔细,层次

    // 笔(线艺,局部坐标笔尖在原点、笔杆朝上,再整体旋转)
    static let penAngle = 0.55     // rad,右倾书写姿态
    static let penWobble = 0.05    // rad,书写微颤幅度
    static let penWobbleFreq = 9.0 // 每周期颤动次数
    static let penWidthScale: CGFloat = 0.50   // 笔是线艺勾勒,不是实心棒
    static let penLen: CGFloat = 0.24
    static let penNibLen: CGFloat = 0.055
    static let penNibHalf: CGFloat = 0.017
    static let hoverEnd = 0.44     // [writeEnd,hoverEnd] 悬笔思考;[hoverEnd,0.5] 换行
    static let gapLift = 0.05      // 词间提笔高度
    static let hopLift = 0.10      // 换行提笔高度
    static let hoverBob = 0.007    // 悬笔呼吸幅度

    struct TipState {
        let pos: CGPoint
        let tilt: Double
        let writing: Bool
    }

    /// 书写进度 wp∈[0,1] → 笔尖位置(词内沿笔画;词隙走提笔小弧)
    static func tipAt(_ phrase: Phrase, _ wp: Double) -> (pos: CGPoint, lift: Double) {
        for i in 0..<phrase.paths.count {
            let (t0, t1) = phrase.spans[i]
            if wp <= t1 {
                if wp >= t0 {
                    return (phrase.paths[i].point(at: (wp - t0) / (t1 - t0)), 0)
                }
                let prevEnd = phrase.paths[i - 1].point(at: 1)
                let curStart = phrase.paths[i].point(at: 0)
                let g0 = phrase.spans[i - 1].1
                let q = (wp - g0) / (t0 - g0)
                let s = MotionEase.smoothstep(q)
                let pos = CGPoint(
                    x: prevEnd.x + (curStart.x - prevEnd.x) * CGFloat(s),
                    y: prevEnd.y + (curStart.y - prevEnd.y) * CGFloat(s)
                )
                return (pos, gapLift * sin(.pi * q))
            }
        }
        return (phrase.paths[phrase.paths.count - 1].point(at: 1), 0)
    }

    /// 全局相位 → 笔尖状态。笔全程连续:写 → 悬笔 → 换行 → 写……
    static func penState(_ phase: Double) -> TipState {
        let k = phase < 0.5 ? 0 : 1
        let pl = phase - 0.5 * Double(k)
        let cur = phrases[k], nxt = phrases[(k + 1) % 2]
        if pl < writeEnd {
            let t = tipAt(cur, pl / writeEnd)
            return TipState(
                pos: CGPoint(x: t.pos.x, y: t.pos.y - CGFloat(t.lift)),
                tilt: 0,
                writing: t.lift == 0
            )
        }
        let endPos = cur.paths[cur.paths.count - 1].point(at: 1)
        if pl < hoverEnd {
            let q = (pl - writeEnd) / (hoverEnd - writeEnd)
            return TipState(
                pos: CGPoint(x: endPos.x, y: endPos.y - CGFloat(hoverBob * sin(2 * .pi * q))),
                tilt: 0,
                writing: false
            )
        }
        let startPos = nxt.paths[0].point(at: 0)
        let q = (pl - hoverEnd) / (0.5 - hoverEnd)
        let s = MotionEase.smoothstep(q)
        return TipState(
            pos: CGPoint(
                x: endPos.x + (startPos.x - endPos.x) * CGFloat(s),
                y: endPos.y + (startPos.y - endPos.y) * CGFloat(s) - CGFloat(hopLift * sin(.pi * q))
            ),
            tilt: 0.16 * sin(.pi * q),
            writing: false
        )
    }

    static func drawPen(_ context: inout GraphicsContext, size: CGFloat, phase: Double, dark: Bool) {
        let st = penState(phase)
        let w = MotionLineWidth.width(for: size) * penWidthScale
        let color = MotionPalette.stroke(dark: dark)
        let wobble = st.writing ? penWobble * sin(2 * .pi * penWobbleFreq * phase) : 0
        let angle = penAngle + wobble + st.tilt

        var pctx = context
        pctx.translateBy(x: st.pos.x * size, y: st.pos.y * size)
        pctx.rotate(by: .radians(angle))

        let len = penLen * size
        let nib = penNibLen * size
        let nh = penNibHalf * size
        var pen = Path()
        pen.move(to: .zero)
        pen.addLine(to: CGPoint(x: -nh, y: -nib))
        pen.move(to: .zero)
        pen.addLine(to: CGPoint(x: nh, y: -nib))
        pen.move(to: CGPoint(x: 0, y: -nib))
        pen.addLine(to: CGPoint(x: 0, y: -len))
        pctx.stroke(
            pen,
            with: .color(color),
            style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        )
    }

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
            path.drawWindow(
                in: &context, size: size, tail: 0, head: prog,
                style: .init(
                    color: color, width: w, taper: agingTaper, wrap: false,
                    masterAlpha: masterAlpha, drift: drift,
                    headDot: prog < 1 || pLocal < holdEnd
                )
            )
        }
    }

    static let spec = MotionSpec(
        id: "thinking-drafting-pen",
        title: "Thinking|起草",
        subtitle: "3.6s · 可见笔 · 写-悬-换行 · 纯墨",
        cycle: cycle
    ) { context, size, phase, dark in
        let m = DraftingMotion.self
        for k in 0..<2 {
            let shifted = phase - Double(k) * 0.5
            let pLocal = (shifted.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
            m.drawPhrase(&context, size: size, pLocal: pLocal, phrase: m.phrases[k], dark: dark)
        }
        m.drawPen(&context, size: size, phase: phase, dark: dark)
    }
}

// MARK: - 搜索|拾音(斜雨涟漪)

/// 并行的雨丝被风吹斜,落在一条看不见的水面上;
/// 众丝落下各起一圈墨色微澜,唯命中那根减速落定,
/// 荡开雨蓝双圈椭圆涟漪(椭圆即水面透视)。活动 1.7s + 停顿 0.4s。
enum RainfallMotion {
    static let active = 1.7
    static let rest = 0.4
    static var cycle: Double { active + rest }

    struct Lane {
        let x0: CGFloat
        let yLand: CGFloat
        let born: Double
        let dur: Double
        let len: Double
        let alpha: Double
        let hit: Bool
    }

    static let yTop: CGFloat = -0.08
    static let widthScale: CGFloat = 0.45   // 雨丝极细

    static let lanes: [Lane] = [
        Lane(x0: 0.06, yLand: 0.60, born: 0.04, dur: 0.42, len: 0.22, alpha: 0.50, hit: false),
        Lane(x0: 0.22, yLand: 0.55, born: 0.10, dur: 0.40, len: 0.25, alpha: 0.72, hit: false),
        Lane(x0: 0.37, yLand: 0.58, born: 0.16, dur: 0.42, len: 0.26, alpha: 0.95, hit: true),
        Lane(x0: 0.55, yLand: 0.57, born: 0.22, dur: 0.38, len: 0.21, alpha: 0.62, hit: false),
        Lane(x0: 0.72, yLand: 0.62, born: 0.28, dur: 0.42, len: 0.24, alpha: 0.78, hit: false),
        Lane(x0: 0.88, yLand: 0.59, born: 0.34, dur: 0.40, len: 0.20, alpha: 0.46, hit: false),
    ]

    /// 风吹斜方向(归一化)
    static let dirN: CGPoint = {
        let d = CGPoint(x: 0.36, y: 1)
        let m = hypot(d.x, d.y)
        return CGPoint(x: d.x / m, y: d.y / m)
    }()

    static let builtLanes: [(lane: Lane, path: SampledPath, land: CGPoint)] = {
        let dir = RainfallMotion.dirN
        let top = RainfallMotion.yTop
        return RainfallMotion.lanes.map { lane in
            let travel = (lane.yLand - top) / dir.y
            let start = CGPoint(x: lane.x0, y: top)
            let land = CGPoint(x: start.x + dir.x * travel, y: start.y + dir.y * travel)
            return (lane, SampledPath.straight(start, land), land)
        }
    }()

    static let hitEase = 0.65        // 命中丝减速混合
    static let absorbDur = 0.12      // 落定后余丝没入水面
    static let microRipple = (dur: 0.14, r1: 2.3, alpha: 0.18)   // 半径 microR0→r1(×线宽)
    static let microR0 = 0.8
    static let ringSquash: CGFloat = 0.42   // 椭圆涟漪纵横比(水面透视)
    static let bloom = (rise: 0.04, fall: 0.22, r: CGFloat(0.95), haloR: CGFloat(1.4), haloA: 0.10, coreA: 0.9)
    static let rings: [(delay: Double, dur: Double, r0: Double, r1: Double, alpha: Double)] = [
        (delay: 0.00, dur: 0.34, r0: 1.4, r1: 5.6, alpha: 0.32),
        (delay: 0.09, dur: 0.34, r0: 1.0, r1: 4.2, alpha: 0.22),
    ]
    static let ringWidth: CGFloat = 0.32    // × 线宽,随扩散衰减
    static let tailTaper = 0.60

    /// 椭圆涟漪(水面透视)
    static func strokeRipple(_ context: inout GraphicsContext, center: CGPoint, size: CGFloat,
                             radius: CGFloat, color: Color, alpha: Double, lineWidth: CGFloat) {
        guard alpha > 0.003 else { return }
        let c = CGPoint(x: center.x * size, y: center.y * size)
        let ry = radius * ringSquash
        context.stroke(
            Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - ry, width: radius * 2, height: ry * 2)),
            with: .color(color.opacity(alpha)),
            style: StrokeStyle(lineWidth: lineWidth)
        )
    }

    static let spec = MotionSpec(
        id: "search-rainfall",
        title: "搜索|拾音",
        subtitle: "斜雨落水 · 1.7s + 0.4s · 雨蓝涟漪",
        cycle: cycle
    ) { context, size, phase, dark in
        let m = RainfallMotion.self
        let p = phase * m.cycle / m.active
        guard p < 1 else { return }
        let w = MotionLineWidth.width(for: size) * m.widthScale
        let ink = MotionPalette.stroke(dark: dark)
        let blue = MotionPalette.rain(dark: dark)

        for entry in m.builtLanes {
            let lane = entry.lane
            let u = (p - lane.born) / lane.dur
            // 雨丝
            if u > 0 {
                let head: Double
                var tail: Double
                if lane.hit {
                    let cu = MotionEase.clamp01(u)
                    head = MotionEase.lerp(cu, MotionEase.easeOutCubic(cu), m.hitEase)
                    tail = head - lane.len
                    if u > 1 {
                        let q = MotionEase.clamp01((p - (lane.born + lane.dur)) / m.absorbDur)
                        tail = MotionEase.lerp(head - lane.len, 1, MotionEase.smoothstep(q))
                    }
                } else {
                    head = u * (1 + lane.len)   // 线性坠落,尾部随之没入水面
                    tail = head - lane.len
                }
                if tail < 1 {
                    entry.path.drawWindow(
                        in: &context, size: size, tail: tail, head: min(1, head),
                        style: .init(
                            color: ink, width: w, taper: m.tailTaper, wrap: false,
                            masterAlpha: lane.alpha,
                            headDot: false   // 雨丝要利落,不要蝌蚪头
                        )
                    )
                }
            }
            // 落水微澜(墨色,极淡)
            if !lane.hit {
                let tLand = lane.born + lane.dur / (1 + lane.len)
                let q = (p - tLand) / m.microRipple.dur
                if q > 0, q < 1 {
                    let rr = CGFloat(MotionEase.lerp(m.microR0, m.microRipple.r1, MotionEase.easeOutCubic(q))) * w
                    m.strokeRipple(
                        &context, center: entry.land, size: size, radius: rr,
                        color: ink, alpha: m.microRipple.alpha * (1 - q) * lane.alpha,
                        lineWidth: max(0.4, w * 0.3)
                    )
                }
            }
        }

        // 命中:雨蓝辉光 + 双圈椭圆涟漪
        guard let hitEntry = m.builtLanes.first(where: { $0.lane.hit }) else { return }
        let hitAt = hitEntry.lane.born + hitEntry.lane.dur
        let tb = p - hitAt
        if tb > 0, tb < m.bloom.rise + m.bloom.fall {
            let rise = MotionEase.clamp01(tb / m.bloom.rise)
            let fall = MotionEase.clamp01((tb - m.bloom.rise) / m.bloom.fall)
            let alpha = MotionEase.easeOutCubic(rise) * (1 - MotionEase.easeInQuad(fall))
            let r = m.bloom.r * w * (0.55 + 0.45 * CGFloat(MotionEase.easeOutCubic(rise)))
            let c = CGPoint(x: hitEntry.land.x * size, y: hitEntry.land.y * size)
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - r * m.bloom.haloR, y: c.y - r * m.bloom.haloR,
                                       width: r * m.bloom.haloR * 2, height: r * m.bloom.haloR * 2)),
                with: .color(blue.opacity(alpha * m.bloom.haloA))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(blue.opacity(alpha * m.bloom.coreA))
            )
        }
        for ring in m.rings {
            let q = (tb - ring.delay) / ring.dur
            if q > 0, q < 1 {
                let rr = CGFloat(MotionEase.lerp(ring.r0, ring.r1, MotionEase.easeOutCubic(q))) * w
                m.strokeRipple(
                    &context, center: hitEntry.land, size: size, radius: rr,
                    color: blue, alpha: ring.alpha * (1 - q),
                    lineWidth: max(0.4, w * m.ringWidth * CGFloat(1 - 0.7 * q))
                )
            }
        }
    }
}

/// 展板注册表(顺序即展示顺序)
enum MotionCatalog {
    static let all: [MotionSpec] = [
        DraftingMotion.spec,
        RainfallMotion.spec,
    ]
}
