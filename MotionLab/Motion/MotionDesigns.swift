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

// MARK: - Thinking|起草 v4:用户钢笔书写「祐」(甲骨文)

/// 笔 = 用户 SVG(writing-pen-monochrome-v2,见 design-refs/)原样描线,
///      笔尖锚点 (128,226),笔长 199(256 空间),小尺寸省略细节线。
/// 祐 = 以用户填充轮廓 SVG 为底稿手工配准的 10 笔中心线;
///      单字循环:写 → 悬笔端详 → 墨沉消散 → 回笔蓄势。笔尖全程连续。
/// 常量与草样(motion-sketch.html v4)1:1。
enum DraftingMotion {
    static let cycle = 4.4

    // ---- 字形 ----
    static let glyphBox = CGRect(x: 0.17, y: 0.19, width: 0.45, height: 0.62)   // 812:1118

    /// 字形归一化坐标(x/812, y/1118)。笔顺:示旁 二+三竖(中竖最长)→ 横折长竖钩 → 中横 → 匣顶 → 匣左底 → 匣内横
    static let strokePoints: [[CGPoint]] = [
        [CGPoint(x: 0.12, y: 0.081), CGPoint(x: 0.24, y: 0.070), CGPoint(x: 0.356, y: 0.073)],
        [CGPoint(x: 0.078, y: 0.177), CGPoint(x: 0.26, y: 0.166), CGPoint(x: 0.456, y: 0.169)],
        [CGPoint(x: 0.144, y: 0.234), CGPoint(x: 0.132, y: 0.44), CGPoint(x: 0.140, y: 0.60), CGPoint(x: 0.150, y: 0.70)],
        [CGPoint(x: 0.256, y: 0.20), CGPoint(x: 0.262, y: 0.52), CGPoint(x: 0.258, y: 0.84)],
        [CGPoint(x: 0.389, y: 0.242), CGPoint(x: 0.398, y: 0.46), CGPoint(x: 0.396, y: 0.69)],
        [CGPoint(x: 0.556, y: 0.152), CGPoint(x: 0.75, y: 0.132), CGPoint(x: 0.905, y: 0.138),
         CGPoint(x: 0.940, y: 0.22), CGPoint(x: 0.915, y: 0.50), CGPoint(x: 0.878, y: 0.85)],
        [CGPoint(x: 0.556, y: 0.319), CGPoint(x: 0.68, y: 0.306), CGPoint(x: 0.80, y: 0.310)],
        [CGPoint(x: 0.578, y: 0.412), CGPoint(x: 0.836, y: 0.405)],
        [CGPoint(x: 0.593, y: 0.422), CGPoint(x: 0.567, y: 0.56), CGPoint(x: 0.63, y: 0.682), CGPoint(x: 0.833, y: 0.672)],
        [CGPoint(x: 0.627, y: 0.512), CGPoint(x: 0.782, y: 0.505)],
    ]

    static let strokes: [SampledPath] = {
        let box = DraftingMotion.glyphBox
        return DraftingMotion.strokePoints.map { pts in
            SampledPath.openCatmullRom(pts.map { p in
                CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
            })
        }
    }()

    static let strokeGap = 0.020    // 笔画间提笔(占书写段比例)

    static let spans: [(Double, Double)] = {
        let paths = DraftingMotion.strokes
        let gap = DraftingMotion.strokeGap
        let totalLen = paths.reduce(CGFloat(0)) { $0 + $1.total }
        let gaps = Double(paths.count - 1) * gap
        var spans: [(Double, Double)] = []
        var t = 0.0
        for path in paths {
            let share = (1 - gaps) * Double(path.total / totalLen)
            spans.append((t, t + share))
            t += share + gap
        }
        return spans
    }()

    // ---- 时间线 ----
    static let writeSpan = (t0: 0.02, t1: 0.60)
    static let hoverEnd = 0.68               // [writeEnd, hoverEnd] 悬笔端详
    static let fadeSpan = (t0: 0.70, t1: 0.90)   // 墨沉消散
    static let returnSpan = (t0: 0.68, t1: 0.96) // 回笔(与消散重叠)
    static let sinkDrift: CGFloat = 0.022
    static let agingTaper = 0.04
    static let widthScale: CGFloat = 0.62    // 字迹线宽比

    // ---- 笔 ----
    static let penLenUnit: CGFloat = 0.34    // 笔长(单位空间)
    static let penSvgLen: CGFloat = 199      // SVG 空间笔长(y 27→226)
    static let penTip = CGPoint(x: 128, y: 226)
    static let penAngle = 38.0 * Double.pi / 180   // 用户 SVG 的书写倾角
    static let penWobble = 0.035
    static let penWobbleFreq = 11.0
    static let penWidthScale: CGFloat = 0.50 // 笔主线宽比;细节线 ×0.75
    static let penDetailMin: CGFloat = 64    // 画布小于此值省略细节线
    static let gapLift = 0.045
    static let hopLift = 0.12
    static let hoverBob = 0.007

    /// 用户钢笔 SVG 主体线(256 空间):笔身胶囊 + 握位四线 + 笔尖 V
    static let penMainPaths: [Path] = {
        var body = Path()
        body.move(to: CGPoint(x: 128, y: 27))
        body.addCurve(to: CGPoint(x: 112.5, y: 42.5), control1: CGPoint(x: 119.4, y: 27), control2: CGPoint(x: 112.5, y: 33.9))
        body.addLine(to: CGPoint(x: 112.5, y: 128.5))
        body.addCurve(to: CGPoint(x: 123, y: 139), control1: CGPoint(x: 112.5, y: 134.3), control2: CGPoint(x: 117.2, y: 139))
        body.addLine(to: CGPoint(x: 133, y: 139))
        body.addCurve(to: CGPoint(x: 143.5, y: 128.5), control1: CGPoint(x: 138.8, y: 139), control2: CGPoint(x: 143.5, y: 134.3))
        body.addLine(to: CGPoint(x: 143.5, y: 42.5))
        body.addCurve(to: CGPoint(x: 128, y: 27), control1: CGPoint(x: 143.5, y: 33.9), control2: CGPoint(x: 136.6, y: 27))
        body.closeSubpath()

        func line(_ a: CGPoint, _ b: CGPoint) -> Path {
            var p = Path(); p.move(to: a); p.addLine(to: b); return p
        }

        var nib = Path()
        nib.move(to: CGPoint(x: 121, y: 171))
        nib.addCurve(to: CGPoint(x: 128, y: 226), control1: CGPoint(x: 120.5, y: 187.5), control2: CGPoint(x: 122.8, y: 203.5))
        nib.addCurve(to: CGPoint(x: 135, y: 171), control1: CGPoint(x: 133.2, y: 203.5), control2: CGPoint(x: 135.5, y: 187.5))
        nib.closeSubpath()

        return [
            body,
            line(CGPoint(x: 117, y: 139), CGPoint(x: 121, y: 171)),
            line(CGPoint(x: 139, y: 139), CGPoint(x: 135, y: 171)),
            line(CGPoint(x: 117, y: 139), CGPoint(x: 139, y: 139)),
            line(CGPoint(x: 121, y: 171), CGPoint(x: 135, y: 171)),
            nib,
        ]
    }()

    /// 细节线:帽缝、笔夹、尖肩、呼吸孔、笔缝
    static let penDetailPaths: [Path] = {
        func line(_ a: CGPoint, _ b: CGPoint) -> Path {
            var p = Path(); p.move(to: a); p.addLine(to: b); return p
        }
        var clip = Path()
        clip.move(to: CGPoint(x: 136.5, y: 44.5))
        clip.addCurve(to: CGPoint(x: 136.2, y: 96.5), control1: CGPoint(x: 141.2, y: 58.2), control2: CGPoint(x: 141.1, y: 78.5))
        clip.addCurve(to: CGPoint(x: 132, y: 104.5), control1: CGPoint(x: 135.1, y: 100.6), control2: CGPoint(x: 133.7, y: 103.2))
        var shoulder = Path()
        shoulder.move(to: CGPoint(x: 121.7, y: 178))
        shoulder.addLine(to: CGPoint(x: 128, y: 187))
        shoulder.addLine(to: CGPoint(x: 134.3, y: 178))
        return [
            line(CGPoint(x: 113, y: 55), CGPoint(x: 143, y: 55)),
            clip,
            shoulder,
            Path(ellipseIn: CGRect(x: 125, y: 184, width: 6, height: 6)),
            line(CGPoint(x: 128, y: 190), CGPoint(x: 128, y: 223)),
        ]
    }()

    struct TipState {
        let pos: CGPoint
        let tilt: Double
        let writing: Bool
    }

    /// 书写进度 wp∈[0,1] → 笔尖(笔画内沿线;笔画间提笔小弧)
    static func tipAt(_ wp: Double) -> (pos: CGPoint, lift: Double) {
        for i in 0..<strokes.count {
            let (t0, t1) = spans[i]
            if wp <= t1 {
                if wp >= t0 {
                    return (strokes[i].point(at: (wp - t0) / (t1 - t0)), 0)
                }
                let prevEnd = strokes[i - 1].point(at: 1)
                let curStart = strokes[i].point(at: 0)
                let g0 = spans[i - 1].1
                let q = (wp - g0) / (t0 - g0)
                let s = MotionEase.smoothstep(q)
                let pos = CGPoint(
                    x: prevEnd.x + (curStart.x - prevEnd.x) * CGFloat(s),
                    y: prevEnd.y + (curStart.y - prevEnd.y) * CGFloat(s)
                )
                return (pos, gapLift * sin(.pi * q))
            }
        }
        return (strokes[strokes.count - 1].point(at: 1), 0)
    }

    /// 全局相位 → 笔尖状态。写 → 悬 → 回笔 → 蓄势 → 写……全程连续。
    static func penState(_ p: Double) -> TipState {
        let startPos = strokes[0].point(at: 0)
        let endPos = strokes[strokes.count - 1].point(at: 1)
        if p >= writeSpan.t0, p < writeSpan.t1 {
            let t = tipAt((p - writeSpan.t0) / (writeSpan.t1 - writeSpan.t0))
            return TipState(
                pos: CGPoint(x: t.pos.x, y: t.pos.y - CGFloat(t.lift)),
                tilt: 0,
                writing: t.lift == 0
            )
        }
        if p >= writeSpan.t1, p < hoverEnd {
            let q = (p - writeSpan.t1) / (hoverEnd - writeSpan.t1)
            return TipState(
                pos: CGPoint(x: endPos.x, y: endPos.y - CGFloat(hoverBob * sin(2 * .pi * q))),
                tilt: 0,
                writing: false
            )
        }
        // 回笔与蓄势(蓄势含跨 0 到 writeSpan.t0)
        var q = 1.0
        if p >= returnSpan.t0, p < returnSpan.t1 {
            q = (p - returnSpan.t0) / (returnSpan.t1 - returnSpan.t0)
        }
        if q >= 1 {
            let poiseLen = 1 - returnSpan.t1 + writeSpan.t0
            let q2 = p >= returnSpan.t1 ? (p - returnSpan.t1) / poiseLen : (p + 1 - returnSpan.t1) / poiseLen
            let bob = 0.004 + hoverBob * 0.6 * sin(.pi * MotionEase.clamp01(q2))
            return TipState(
                pos: CGPoint(x: startPos.x, y: startPos.y - CGFloat(bob)),
                tilt: 0,
                writing: false
            )
        }
        let s = MotionEase.smoothstep(q)
        return TipState(
            pos: CGPoint(
                x: endPos.x + (startPos.x - endPos.x) * CGFloat(s),
                y: endPos.y + (startPos.y - endPos.y) * CGFloat(s) - CGFloat(hopLift * sin(.pi * q))
            ),
            tilt: 0.18 * sin(.pi * q),
            writing: false
        )
    }

    static func drawPen(_ context: inout GraphicsContext, size: CGFloat, phase: Double, dark: Bool) {
        let st = penState(phase)
        let color = MotionPalette.stroke(dark: dark)
        let wobble = st.writing ? penWobble * sin(2 * .pi * penWobbleFreq * phase) : 0
        let angle = penAngle + wobble + st.tilt
        let s = (penLenUnit * size) / penSvgLen
        let mainW = MotionLineWidth.width(for: size) * penWidthScale

        var pctx = context
        pctx.translateBy(x: st.pos.x * size, y: st.pos.y * size)
        pctx.rotate(by: .radians(angle))
        pctx.scaleBy(x: s, y: s)
        pctx.translateBy(x: -penTip.x, y: -penTip.y)

        let mainStyle = StrokeStyle(lineWidth: mainW / s, lineCap: .round, lineJoin: .round)
        for path in penMainPaths {
            pctx.stroke(path, with: .color(color), style: mainStyle)
        }
        if size >= penDetailMin {
            let detailStyle = StrokeStyle(lineWidth: mainW * 0.75 / s, lineCap: .round, lineJoin: .round)
            for path in penDetailPaths {
                pctx.stroke(path, with: .color(color), style: detailStyle)
            }
        }
    }

    static let spec = MotionSpec(
        id: "thinking-drafting-you",
        title: "Thinking|起草",
        subtitle: "4.4s · 钢笔写「祐」 · 无缝 · 纯墨",
        cycle: cycle
    ) { context, size, phase, dark in
        let m = DraftingMotion.self
        let color = MotionPalette.stroke(dark: dark)
        let w = MotionLineWidth.width(for: size) * m.widthScale

        var masterAlpha = 1.0
        var drift = CGPoint.zero
        let writeP: Double
        if phase < m.writeSpan.t0 {
            writeP = 0
        } else if phase < m.writeSpan.t1 {
            writeP = (phase - m.writeSpan.t0) / (m.writeSpan.t1 - m.writeSpan.t0)
        } else {
            writeP = 1
        }
        if phase >= m.fadeSpan.t0 {
            let q = MotionEase.clamp01((phase - m.fadeSpan.t0) / (m.fadeSpan.t1 - m.fadeSpan.t0))
            masterAlpha = 1 - MotionEase.smoothstep(q)
            drift = CGPoint(x: 0, y: m.sinkDrift * CGFloat(q))
        }
        if masterAlpha > 0, writeP > 0 {
            for (i, path) in m.strokes.enumerated() {
                let (t0, t1) = m.spans[i]
                let prog: Double
                if writeP >= t1 {
                    prog = 1
                } else if writeP <= t0 {
                    continue
                } else {
                    prog = (writeP - t0) / (t1 - t0)
                }
                path.drawWindow(
                    in: &context, size: size, tail: 0, head: prog,
                    style: .init(
                        color: color, width: w, taper: m.agingTaper, wrap: false,
                        masterAlpha: masterAlpha, drift: drift,
                        headDot: prog < 1 || phase < m.fadeSpan.t0
                    )
                )
            }
        }
        m.drawPen(&context, size: size, phase: phase, dark: dark)
    }
}

// MARK: - 搜索|拾音(斜雨涟漪,水面居中偏下)

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
        Lane(x0: 0.06, yLand: 0.71, born: 0.04, dur: 0.46, len: 0.22, alpha: 0.50, hit: false),
        Lane(x0: 0.22, yLand: 0.66, born: 0.10, dur: 0.44, len: 0.25, alpha: 0.72, hit: false),
        Lane(x0: 0.37, yLand: 0.69, born: 0.16, dur: 0.46, len: 0.26, alpha: 0.95, hit: true),
        Lane(x0: 0.55, yLand: 0.68, born: 0.22, dur: 0.42, len: 0.21, alpha: 0.62, hit: false),
        Lane(x0: 0.72, yLand: 0.73, born: 0.28, dur: 0.46, len: 0.24, alpha: 0.78, hit: false),
        Lane(x0: 0.88, yLand: 0.70, born: 0.34, dur: 0.44, len: 0.20, alpha: 0.46, hit: false),
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
