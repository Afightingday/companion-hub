import SwiftUI

/// 单位空间里的采样路径:样条 → 折线 + 累积弧长表。
/// 支持按弧长分数取点/取段,以及带拖尾渐隐的可见窗口绘制。
/// 算法与 HTML 草样保持 1:1。
struct SampledPath {
    let pts: [CGPoint]
    let cum: [CGFloat]
    let total: CGFloat

    // MARK: 构造

    /// 三次贝塞尔段:p0 → p1,控制点 c1/c2
    struct Cubic {
        let p0, c1, c2, p1: CGPoint

        func point(at t: CGFloat) -> CGPoint {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(
                x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
                y: a * p0.y + b * c1.y + c * c2.y + d * p1.y
            )
        }
    }

    init(segments: [Cubic], perSegment: Int = 48) {
        var pts: [CGPoint] = []
        for (si, seg) in segments.enumerated() {
            let start = si == 0 ? 0 : 1
            if perSegment >= start {
                for i in start...perSegment {
                    pts.append(seg.point(at: CGFloat(i) / CGFloat(perSegment)))
                }
            }
        }
        var cum: [CGFloat] = [0]
        cum.reserveCapacity(pts.count)
        for i in 1..<pts.count {
            cum.append(cum[i - 1] + pts[i].distance(to: pts[i - 1]))
        }
        self.pts = pts
        self.cum = cum
        self.total = cum.last ?? 1
    }

    /// 闭合向心 Catmull-Rom(α = 0.5)
    static func closedCatmullRom(_ points: [CGPoint], perSegment: Int = 48) -> SampledPath {
        let n = points.count
        var segs: [Cubic] = []
        for i in 0..<n {
            segs.append(crSegment(
                points[(i - 1 + n) % n],
                points[i],
                points[(i + 1) % n],
                points[(i + 2) % n]
            ))
        }
        return SampledPath(segments: segs, perSegment: perSegment)
    }

    /// 开放向心 Catmull-Rom(端点重复)——手写笔画、巡访路线等非闭合线
    static func openCatmullRom(_ points: [CGPoint], perSegment: Int = 48) -> SampledPath {
        let n = points.count
        var segs: [Cubic] = []
        for i in 0..<(n - 1) {
            segs.append(crSegment(
                points[max(0, i - 1)],
                points[i],
                points[i + 1],
                points[min(n - 1, i + 2)]
            ))
        }
        return SampledPath(segments: segs, perSegment: perSegment)
    }

    /// 过定点二次贝塞尔:曲线在 t = 0.5 恰过 X(升为三次后采样)
    static func quadThrough(_ p0: CGPoint, _ x: CGPoint, _ p2: CGPoint) -> SampledPath {
        let mid = CGPoint(x: (p0.x + p2.x) / 2, y: (p0.y + p2.y) / 2)
        let ctrl = CGPoint(x: 2 * x.x - mid.x, y: 2 * x.y - mid.y)
        let c1 = CGPoint(x: p0.x / 3 + ctrl.x * 2 / 3, y: p0.y / 3 + ctrl.y * 2 / 3)
        let c2 = CGPoint(x: p2.x / 3 + ctrl.x * 2 / 3, y: p2.y / 3 + ctrl.y * 2 / 3)
        return SampledPath(segments: [Cubic(p0: p0, c1: c1, c2: c2, p1: p2)], perSegment: 96)
    }

    /// 向心 Catmull-Rom 四点 → 三次贝塞尔(标准公式)
    private static func crSegment(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> Cubic {
        let alpha: CGFloat = 0.5
        let eps: CGFloat = 1e-4
        let d1 = max(eps, pow(p0.distance(to: p1), alpha))
        let d2 = max(eps, pow(p1.distance(to: p2), alpha))
        let d3 = max(eps, pow(p2.distance(to: p3), alpha))

        func combine(_ a: CGPoint, _ ka: CGFloat, _ b: CGPoint, _ kb: CGFloat, _ c: CGPoint, _ kc: CGFloat, div: CGFloat) -> CGPoint {
            CGPoint(
                x: (a.x * ka + b.x * kb + c.x * kc) / div,
                y: (a.y * ka + b.y * kb + c.y * kc) / div
            )
        }

        let b1 = combine(p2, d1 * d1, p0, -(d2 * d2), p1, 2 * d1 * d1 + 3 * d1 * d2 + d2 * d2,
                         div: 3 * d1 * (d1 + d2))
        let b2 = combine(p1, d3 * d3, p3, -(d2 * d2), p2, 2 * d3 * d3 + 3 * d3 * d2 + d2 * d2,
                         div: 3 * d3 * (d3 + d2))
        return Cubic(p0: p1, c1: b1, c2: b2, p1: p2)
    }

    // MARK: 弧长取点

    /// 弧长分数 [0,1] → 点
    func point(at fraction: Double) -> CGPoint {
        let target = CGFloat(MotionEase.clamp01(fraction)) * total
        var lo = 0, hi = cum.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cum[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        let i = max(1, lo)
        let span = max(cum[i] - cum[i - 1], 1e-9)
        let t = (target - cum[i - 1]) / span
        return CGPoint(
            x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
            y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t
        )
    }

    /// [f0,f1] 之间的折线点列(含插值端点);区间过短返回 nil
    func slice(from f0: Double, to f1: Double) -> [CGPoint]? {
        let a = CGFloat(MotionEase.clamp01(f0)) * total
        let b = CGFloat(MotionEase.clamp01(f1)) * total
        guard b - a > 1e-9 else { return nil }
        var out: [CGPoint] = [point(at: f0)]
        for i in 0..<pts.count where cum[i] > a && cum[i] < b {
            out.append(pts[i])
        }
        out.append(point(at: f1))
        return out
    }

    // MARK: 可见窗口绘制

    struct WindowStyle {
        let color: Color
        let width: CGFloat
        /// 窗口尾部渐隐占比(0=尾,1=头)
        let taper: Double
        /// 闭合路线允许窗口跨过起终点
        let wrap: Bool
        /// 整体透明度(消散包络等)
        let masterAlpha: Double
        /// 整体平移(单位空间;墨沉等)
        let drift: CGPoint
        /// 头部圆点收口
        let headDot: Bool

        init(color: Color, width: CGFloat, taper: Double, wrap: Bool,
             masterAlpha: Double = 1, drift: CGPoint = .zero, headDot: Bool = true) {
            self.color = color
            self.width = width
            self.taper = taper
            self.wrap = wrap
            self.masterAlpha = masterAlpha
            self.drift = drift
            self.headDot = headDot
        }
    }

    /// 拖尾窗口:切成小片做透明度渐变;片间平头相接避免圆帽叠加,头部圆点收口。
    func drawWindow(in context: inout GraphicsContext, size: CGFloat, tail: Double, head: Double, style: WindowStyle) {
        guard style.masterAlpha > 0 else { return }
        let sliceCount = 28
        var spans: [(Double, Double)] = []
        if style.wrap {
            let t = ((tail.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
            let h = ((head.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
            if t < h { spans.append((t, h)) } else { spans.append((t, 1)); spans.append((0, h)) }
        } else {
            let t = max(0, tail), h = min(1, head)
            if h > t { spans.append((t, h)) }
        }
        let winLen = head - tail
        guard winLen > 1e-9 else { return }

        func place(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x + style.drift.x) * size, y: (p.y + style.drift.y) * size)
        }

        let strokeStyle = StrokeStyle(lineWidth: style.width, lineCap: .butt, lineJoin: .round)
        for (s0, s1) in spans {
            // 该 span 起点在窗口坐标(0=尾,1=头)里的位置
            let w0: Double
            if style.wrap {
                let t = ((tail.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
                w0 = (s0 >= t - 1e-9 ? s0 - t : s0 + 1 - t) / winLen
            } else {
                w0 = (s0 - tail) / winLen
            }
            let k = max(2, Int((Double(sliceCount) * (s1 - s0) / winLen).rounded()))
            for j in 0..<k {
                let f0 = MotionEase.lerp(s0, s1, Double(j) / Double(k))
                let f1 = MotionEase.lerp(s0, s1, Double(j + 1) / Double(k))
                let wMid = w0 + ((Double(j) + 0.5) / Double(k)) * (s1 - s0) / winLen
                let alpha = wMid < style.taper ? MotionEase.smoothstep(wMid / style.taper) : 1
                guard let segment = slice(from: f0, to: f1) else { continue }
                var path = Path()
                path.move(to: place(segment[0]))
                for p in segment.dropFirst() {
                    path.addLine(to: place(p))
                }
                context.stroke(
                    path,
                    with: .color(style.color.opacity(alpha * style.masterAlpha)),
                    style: strokeStyle
                )
            }
        }

        // 头部圆点收口
        guard style.headDot else { return }
        let headFraction = style.wrap
            ? ((head.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
            : min(1, head)
        let hp = place(point(at: headFraction))
        let r = style.width / 2
        context.fill(
            Path(ellipseIn: CGRect(x: hp.x - r, y: hp.y - r, width: r * 2, height: r * 2)),
            with: .color(style.color.opacity(style.masterAlpha))
        )
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func scaled(by size: CGFloat) -> CGPoint {
        CGPoint(x: x * size, y: y * size)
    }
}
