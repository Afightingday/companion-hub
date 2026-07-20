import SwiftUI
import UIKit

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

// MARK: - Thinking|起草 v6:用户九层分笔素材

/// 墨迹成品 = 用户 PSD 分层的 9 笔位图(design-refs/you_oracle_fixed_canvas_package,
/// 画布 1052×1252,层号即笔顺,GlyphStrokes/*.png 打包为资源)。
/// 每层蒙版只揭示本层(零渗漏);字形按九层联合墨盒 (165,151,723,1024) 居中填满 glyphBox。
/// 位图以 destinationIn 混合染成墨色,适配纸/深双底。
/// 钢笔 = 用户 SVG,线宽 ×penWeight 加粗、整体放大,固定倾角 38° 纯平移。
/// 常量与草样(motion-sketch.html v6)1:1。
enum DraftingMotion {
    static let cycle = 4.4

    // ---- 字形 ----
    /// 九层联合墨盒(画布像素)
    static let union = CGRect(x: 165, y: 151, width: 723, height: 1024)
    /// 0.62×(723/1024)=0.438,按联合盒居中填满
    static let glyphBox = CGRect(x: 0.176, y: 0.19, width: 0.438, height: 0.62)

    struct Layer {
        let name: String
        /// 单位空间放置矩形(由画布放置换算)
        let dest: CGRect
        /// 隐藏轨迹(仅驱动笔位/笔顺/蒙版,不显示)
        let median: SampledPath
        /// 蒙版宽(单位空间)
        let maskW: CGFloat
    }

    /// 定义:画布放置 (x,y,w,h) + 轨迹(联合盒归一化坐标)+ 蒙版宽。层序即笔顺。
    static let layerDefs: [(n: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, median: [CGPoint], maskW: CGFloat)] = [
        ("01", 204, 151, 242, 72,
         [CGPoint(x: 0.062, y: 0.040), CGPoint(x: 0.20, y: 0.030), CGPoint(x: 0.378, y: 0.035)], 0.075),
        ("02", 178, 274, 310, 60,
         [CGPoint(x: 0.025, y: 0.150), CGPoint(x: 0.23, y: 0.143), CGPoint(x: 0.442, y: 0.147)], 0.072),
        ("03", 301, 307, 72, 805,
         [CGPoint(x: 0.230, y: 0.162), CGPoint(x: 0.242, y: 0.55), CGPoint(x: 0.236, y: 0.930)], 0.078),
        ("04", 165, 385, 90, 565,
         [CGPoint(x: 0.078, y: 0.235), CGPoint(x: 0.048, y: 0.50), CGPoint(x: 0.060, y: 0.772)], 0.075),
        ("05", 429, 368, 51, 582,
         [CGPoint(x: 0.398, y: 0.218), CGPoint(x: 0.406, y: 0.50), CGPoint(x: 0.400, y: 0.772)], 0.065),
        ("06", 527, 176, 361, 311,
         [CGPoint(x: 0.607, y: 0.261), CGPoint(x: 0.648, y: 0.115), CGPoint(x: 0.80, y: 0.038),
          CGPoint(x: 0.94, y: 0.068), CGPoint(x: 0.995, y: 0.185)], 0.085),
        ("07", 544, 291, 340, 884,
         [CGPoint(x: 0.63, y: 0.165), CGPoint(x: 0.82, y: 0.20), CGPoint(x: 0.945, y: 0.30),
          CGPoint(x: 0.965, y: 0.60), CGPoint(x: 0.92, y: 0.985)], 0.075),
        ("08", 540, 534, 216, 344,
         [CGPoint(x: 0.545, y: 0.400), CGPoint(x: 0.70, y: 0.385), CGPoint(x: 0.800, y: 0.405),
          CGPoint(x: 0.812, y: 0.545), CGPoint(x: 0.790, y: 0.690), CGPoint(x: 0.63, y: 0.705),
          CGPoint(x: 0.532, y: 0.68), CGPoint(x: 0.522, y: 0.52), CGPoint(x: 0.540, y: 0.415)], 0.085),
        ("09", 575, 656, 148, 61,
         [CGPoint(x: 0.572, y: 0.525), CGPoint(x: 0.67, y: 0.516), CGPoint(x: 0.765, y: 0.522)], 0.068),
    ]

    static let layers: [Layer] = {
        let box = DraftingMotion.glyphBox
        let u = DraftingMotion.union
        return DraftingMotion.layerDefs.map { def in
            let mapped = def.median.map { p in
                CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
            }
            let dest = CGRect(
                x: box.minX + (def.x - u.minX) / u.width * box.width,
                y: box.minY + (def.y - u.minY) / u.height * box.height,
                width: def.w / u.width * box.width,
                height: def.h / u.height * box.height
            )
            return Layer(name: def.n, dest: dest, median: SampledPath.openCatmullRom(mapped), maskW: def.maskW)
        }
    }()

    /// 分笔位图(打包资源;缺失时该层跳过,动画不崩)
    static let strokeImages: [Image?] = {
        DraftingMotion.layerDefs.map { def in
            UIImage(named: "stroke-" + def.n).map { Image(uiImage: $0) }
        }
    }()

    static let strokeGap = 0.020    // 笔画间提笔(占书写段比例)

    static let spans: [(Double, Double)] = {
        let paths = DraftingMotion.layers
        let gap = DraftingMotion.strokeGap
        let totalLen = paths.reduce(CGFloat(0)) { $0 + $1.median.total }
        let gaps = Double(paths.count - 1) * gap
        var spans: [(Double, Double)] = []
        var t = 0.0
        for m in paths {
            let share = (1 - gaps) * Double(m.median.total / totalLen)
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

    // ---- 笔 ----
    static let penLenUnit: CGFloat = 0.40    // 笔长(单位空间,放大)
    static let penSvgLen: CGFloat = 199      // SVG 空间笔长(y 27→226)
    static let penTip = CGPoint(x: 128, y: 226)
    static let penAngle = 38.0 * Double.pi / 180   // 用户 SVG 的书写倾角,固定
    static let penWeight: CGFloat = 1.6      // 线宽加粗系数
    static let penDetailMin: CGFloat = 64    // 画布小于此值省略细节线
    static let penMinPt: CGFloat = 0.7       // 笔线宽保底(pt)
    static let gapLift = 0.045
    static let hopLift = 0.12
    static let hoverBob = 0.007

    /// 用户钢笔 SVG(256 空间),w = 原始 stroke-width。主体:笔身胶囊 + 握位四线 + 笔尖 V
    static let penMain: [(path: Path, w: CGFloat)] = {
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
            (body, 4),
            (line(CGPoint(x: 117, y: 139), CGPoint(x: 121, y: 171)), 4),
            (line(CGPoint(x: 139, y: 139), CGPoint(x: 135, y: 171)), 4),
            (line(CGPoint(x: 117, y: 139), CGPoint(x: 139, y: 139)), 3),
            (line(CGPoint(x: 121, y: 171), CGPoint(x: 135, y: 171)), 3),
            (nib, 4),
        ]
    }()

    /// 细节线:帽缝、笔夹、尖肩、呼吸孔、笔缝
    static let penDetail: [(path: Path, w: CGFloat)] = {
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
            (line(CGPoint(x: 113, y: 55), CGPoint(x: 143, y: 55)), 3),
            (clip, 3),
            (shoulder, 2.3),
            (Path(ellipseIn: CGRect(x: 125, y: 184, width: 6, height: 6)), 2.3),
            (line(CGPoint(x: 128, y: 190), CGPoint(x: 128, y: 223)), 2.3),
        ]
    }()

    struct TipState {
        let pos: CGPoint
    }

    /// 书写进度 wp∈[0,1] → 笔尖(轨迹内沿线;笔画间提笔小弧)
    static func tipAt(_ wp: Double) -> (pos: CGPoint, lift: Double) {
        for i in 0..<layers.count {
            let (t0, t1) = spans[i]
            if wp <= t1 {
                if wp >= t0 {
                    return (layers[i].median.point(at: (wp - t0) / (t1 - t0)), 0)
                }
                let prevEnd = layers[i - 1].median.point(at: 1)
                let curStart = layers[i].median.point(at: 0)
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
        return (layers[layers.count - 1].median.point(at: 1), 0)
    }

    /// 全局相位 → 笔尖位置。写 → 悬 → 回笔 → 蓄势 → 写……全程连续,固定倾角纯平移。
    static func penState(_ p: Double) -> TipState {
        let startPos = layers[0].median.point(at: 0)
        let endPos = layers[layers.count - 1].median.point(at: 1)
        if p >= writeSpan.t0, p < writeSpan.t1 {
            let t = tipAt((p - writeSpan.t0) / (writeSpan.t1 - writeSpan.t0))
            return TipState(pos: CGPoint(x: t.pos.x, y: t.pos.y - CGFloat(t.lift)))
        }
        if p >= writeSpan.t1, p < hoverEnd {
            let q = (p - writeSpan.t1) / (hoverEnd - writeSpan.t1)
            return TipState(pos: CGPoint(x: endPos.x, y: endPos.y - CGFloat(hoverBob * sin(2 * .pi * q))))
        }
        var q = 1.0
        if p >= returnSpan.t0, p < returnSpan.t1 {
            q = (p - returnSpan.t0) / (returnSpan.t1 - returnSpan.t0)
        }
        if q >= 1 {
            let poiseLen = 1 - returnSpan.t1 + writeSpan.t0
            let q2 = p >= returnSpan.t1 ? (p - returnSpan.t1) / poiseLen : (p + 1 - returnSpan.t1) / poiseLen
            let bob = 0.004 + hoverBob * 0.6 * sin(.pi * MotionEase.clamp01(q2))
            return TipState(pos: CGPoint(x: startPos.x, y: startPos.y - CGFloat(bob)))
        }
        let s = MotionEase.smoothstep(q)
        return TipState(pos: CGPoint(
            x: endPos.x + (startPos.x - endPos.x) * CGFloat(s),
            y: endPos.y + (startPos.y - endPos.y) * CGFloat(s) - CGFloat(hopLift * sin(.pi * q))
        ))
    }

    static func drawPen(_ context: inout GraphicsContext, size: CGFloat, phase: Double, dark: Bool) {
        let st = penState(phase)
        let color = MotionPalette.stroke(dark: dark)
        let s = (penLenUnit * size) / penSvgLen

        var pctx = context
        pctx.translateBy(x: st.pos.x * size, y: st.pos.y * size)
        pctx.rotate(by: .radians(penAngle))     // 固定倾角
        pctx.scaleBy(x: s, y: s)
        pctx.translateBy(x: -penTip.x, y: -penTip.y)

        for entry in penMain {
            pctx.stroke(
                entry.path,
                with: .color(color),
                style: StrokeStyle(lineWidth: max(entry.w * penWeight, penMinPt / s), lineCap: .round, lineJoin: .round)
            )
        }
        if size >= penDetailMin {
            for entry in penDetail {
                pctx.stroke(
                    entry.path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: max(entry.w * penWeight, penMinPt / s), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    static let spec = MotionSpec(
        id: "thinking-drafting-you",
        title: "Thinking|起草",
        subtitle: "4.4s · 钢笔写「祐」 · 九层分笔 · 纯墨",
        cycle: cycle
    ) { context, size, phase, dark in
        let m = DraftingMotion.self
        let ink = MotionPalette.stroke(dark: dark)

        let writeP: Double
        if phase < m.writeSpan.t0 {
            writeP = 0
        } else if phase < m.writeSpan.t1 {
            writeP = (phase - m.writeSpan.t0) / (m.writeSpan.t1 - m.writeSpan.t0)
        } else {
            writeP = 1
        }
        var masterAlpha = 1.0
        var driftY: CGFloat = 0
        if phase >= m.fadeSpan.t0 {
            let q = MotionEase.clamp01((phase - m.fadeSpan.t0) / (m.fadeSpan.t1 - m.fadeSpan.t0))
            masterAlpha = 1 - MotionEase.smoothstep(q)
            driftY = m.sinkDrift * CGFloat(q)
        }

        if writeP > 0, masterAlpha > 0 {
            for (i, layer) in m.layers.enumerated() {
                let (t0, t1) = m.spans[i]
                let done = writeP >= t1
                if !done, writeP <= t0 { continue }
                guard let image = m.strokeImages[i] else { continue }
                let destRect = CGRect(
                    x: layer.dest.minX * size,
                    y: (layer.dest.minY + driftY) * size,
                    width: layer.dest.width * size,
                    height: layer.dest.height * size
                )
                context.drawLayer { lctx in
                    if !done {
                        // 活动层:蒙版只揭示本层(消散阶段所有层已写完,不与蒙版并存)
                        let prog = (writeP - t0) / (t1 - t0)
                        guard let pts = layer.median.slice(from: 0, to: prog), pts.count > 1 else { return }
                        var polyline = Path()
                        polyline.move(to: pts[0].scaled(by: size))
                        for p in pts.dropFirst() {
                            polyline.addLine(to: p.scaled(by: size))
                        }
                        lctx.clip(to: polyline.strokedPath(
                            StrokeStyle(lineWidth: layer.maskW * size, lineCap: .round, lineJoin: .round)
                        ))
                    }
                    // 染墨:先铺墨色,再以位图 alpha 作 destinationIn
                    lctx.fill(Path(destRect), with: .color(ink.opacity(masterAlpha)))
                    lctx.blendMode = .destinationIn
                    lctx.draw(image, in: destRect)
                }
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
