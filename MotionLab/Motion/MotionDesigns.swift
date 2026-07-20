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
    /// 展板实寸档位。默认 20/24/28 pt(状态文字旁的小图标位)。
    /// 笔画密集的字形动画在小尺寸下并笔,需单独指定更大档位——实测见 DraftingMotion。
    var previewSizes: [CGFloat] = [20, 24, 28]
    let draw: (_ context: inout GraphicsContext, _ size: CGFloat, _ phase: Double, _ dark: Bool) -> Void
}

// MARK: - Thinking|起草 v10:曲率控速 + 分级停顿 + 收尾缩短

/// 墨迹成品 = 用户 PSD 分层的 9 笔位图(design-refs/you_oracle_fixed_canvas_package,
/// 画布 1052×1252,层号即笔顺,GlyphStrokes/*.png 打包为资源)。
/// 每层蒙版只揭示本层(零渗漏);字形按九层联合墨盒 (165,151,723,1024) 居中填满 glyphBox。
/// 位图以 destinationIn 混合染成墨色,适配纸/深双底。
/// 钢笔 = 用户 SVG,线宽 ×penWeight 加粗、整体放大,固定倾角 38° 纯平移。
///
/// v7 修复(用户 2026-07-19 反馈第 6 笔断裂):v6 的 median 是照字形结构手写的,从未与位图配准。
/// 第 6 笔轨迹反向且横穿「反C」空腔,蒙版扫过空腔无墨可揭 → 一笔裂成两段,末了靠时间片结束跳补;
/// 早现的那截孤墨其实是它自己的下横(恰在第 7 笔起始横段的高度上,故被误读为第 7 笔提前显现)。
/// 现改为从位图 alpha 反推中心线(见 layerDefs),配准误差归零,蒙版宽也随之收紧近半。
/// 常量与草样(motion-sketch.html v10)1:1。
enum DraftingMotion {
    static let cycle = 9.3           // v10:书写段仍 6.38s(用户已认可的速度),只压缩收尾

    // ---- 字形 ----
    /// 九层联合墨盒(画布像素)
    static let union = CGRect(x: 165, y: 151, width: 723, height: 1024)
    /// v8 版面(tools/motion-sketch/measure-glyph.mjs 实测推导):字高 0.80,宽 0.80×723/1024=0.5648。
    /// 水平按**墨重心**(union 内 0.5298)居中——右侧「右」比左侧「礻」重 19.8%,纯外框居中会显得偏右,
    /// 故据此左移 0.0168;垂直按外接框居中(竖直重心偏上 0.4249,若也按重心校正会把字压到底边)。
    /// 旧值 (0.176, 0.19, 0.438, 0.62) 左留白 0.176 / 右 0.386,字形整整偏左 10.5% 容器宽(用户指出)。
    static let glyphBox = CGRect(x: 0.2008, y: 0.10, width: 0.5648, height: 0.80)

    struct Layer {
        let name: String
        /// 单位空间放置矩形(由画布放置换算)
        let dest: CGRect
        /// 隐藏轨迹(仅驱动笔位/笔顺/蒙版,不显示)
        let median: SampledPath
        /// 蒙版宽(单位空间)
        let maskW: CGFloat
        /// 曲率时间扭曲表(见 makeWarp)
        let warp: CurvatureWarp
    }

    // ---- v9:曲率控速(去机械感) ----

    /// 二分之三次幂定律(two-thirds power law):人画曲线时速度与曲率呈 v ∝ κ^(-1/3),
    /// 弯得越急走得越慢。沿弧长匀速推进正是「机械感」的数学根源。
    /// t 为归一化时间刻度,索引即等弧长位置;速度比夹在 [1/range, range] 内,
    /// 免得直线段飙速、拐角处停死。
    struct CurvatureWarp {
        let t: [Double]
        let steps: Int
    }

    static func makeWarp(_ path: SampledPath,
                         exponent: Double,
                         speedRange: Double,
                         steps: Int = 200) -> CurvatureWarp {
        var v = [Double]()
        v.reserveCapacity(steps + 1)
        let d = 1.0 / Double(steps)
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            let a = path.point(at: max(0, f - d))
            let b = path.point(at: f)
            let c = path.point(at: min(1, f + d))
            let ab = hypot(Double(b.x - a.x), Double(b.y - a.y))
            let bc = hypot(Double(c.x - b.x), Double(c.y - b.y))
            let ca = hypot(Double(a.x - c.x), Double(a.y - c.y))
            let area = abs(Double(b.x - a.x) * Double(c.y - a.y)
                         - Double(c.x - a.x) * Double(b.y - a.y)) / 2
            let denom = ab * bc * ca
            let k = denom > 1e-12 ? 4 * area / denom : 0      // 三点外接圆曲率
            v.append(pow(k + 1e-4, -exponent))
        }
        let mean = v.reduce(0, +) / Double(v.count)
        for i in 0...steps {
            v[i] = min(speedRange, max(1 / speedRange, v[i] / mean))
        }
        var t = [0.0]
        t.reserveCapacity(steps + 1)
        for i in 1...steps {
            t.append(t[i - 1] + d / ((v[i] + v[i - 1]) / 2))   // dt = ds / v
        }
        let total = t[steps]
        for i in 0...steps { t[i] /= total }
        return CurvatureWarp(t: t, steps: steps)
    }

    /// 时间比例 p → 弧长比例
    static func warpAt(_ w: CurvatureWarp, _ p: Double) -> Double {
        let q = MotionEase.clamp01(p)
        var lo = 0
        var hi = w.steps
        while lo < hi {
            let mid = (lo + hi) / 2
            if w.t[mid] < q { lo = mid + 1 } else { hi = mid }
        }
        let i = max(1, lo)
        let span = w.t[i] - w.t[i - 1]
        let f = span > 1e-9 ? (q - w.t[i - 1]) / span : 0
        return (Double(i - 1) + f) / Double(w.steps)
    }

    /// 定义:画布放置 (x,y,w,h) + 轨迹(联合盒归一化坐标)+ 蒙版宽。层序即笔顺。
    ///
    /// v7:轨迹不再手写,由各层位图 alpha 反推——Zhang-Suen 细化取骨架,取最大连通分量的
    /// 图直径(双向 BFS)作中心线,按弧长重采样;首末沿切向各外延 0.8×笔半径,使圆头蒙版
    /// 罩住铺毫的笔尖。蒙版宽 = 2×笔半径(距离变换 85 分位)×1.4375,不再是拍脑袋的定值。
    /// 定向:长宽比 >2 的横画从左起,<0.5 的竖画从上起,复合形先按 y 后按 x 取起点。
    /// 实测各笔走完蒙版后的漏墨率 ≤0.18%(旧手写轨迹的 06 因穿过「反C」空腔而断笔)。
    static let layerDefs: [(n: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, median: [CGPoint], maskW: CGFloat)] = [
        // 01 上横
        ("01", 204, 151, 242, 72,
         [
          CGPoint(x: 0.0502, y: 0.0403), CGPoint(x: 0.1184, y: 0.0326), CGPoint(x: 0.1552, y: 0.0391),
          CGPoint(x: 0.1974, y: 0.0391), CGPoint(x: 0.2385, y: 0.0371), CGPoint(x: 0.2795, y: 0.0352),
          CGPoint(x: 0.3206, y: 0.0332), CGPoint(x: 0.3866, y: 0.0436)
         ], 0.0453),
        // 02 下横
        ("02", 178, 274, 310, 60,
         [
          CGPoint(x: 0.0078, y: 0.1593), CGPoint(x: 0.0814, y: 0.1533), CGPoint(x: 0.1291, y: 0.1523),
          CGPoint(x: 0.1784, y: 0.1504), CGPoint(x: 0.229, y: 0.1504), CGPoint(x: 0.2783, y: 0.1484),
          CGPoint(x: 0.3271, y: 0.1455), CGPoint(x: 0.3756, y: 0.144), CGPoint(x: 0.4473, y: 0.1448)
         ], 0.04),
        // 03 中竖
        ("03", 301, 307, 72, 805,
         [
          CGPoint(x: 0.2782, y: 0.1475), CGPoint(x: 0.2407, y: 0.2359), CGPoint(x: 0.2379, y: 0.3122),
          CGPoint(x: 0.2407, y: 0.3877), CGPoint(x: 0.2324, y: 0.4624), CGPoint(x: 0.2324, y: 0.5396),
          CGPoint(x: 0.2268, y: 0.6151), CGPoint(x: 0.2268, y: 0.6881), CGPoint(x: 0.2227, y: 0.764),
          CGPoint(x: 0.2227, y: 0.8403), CGPoint(x: 0.2153, y: 0.9404)
         ], 0.04),
        // 04 左竖
        ("04", 165, 385, 90, 565,
         [
          CGPoint(x: 0.0803, y: 0.2389), CGPoint(x: 0.0761, y: 0.3189), CGPoint(x: 0.0733, y: 0.3702),
          CGPoint(x: 0.083, y: 0.4195), CGPoint(x: 0.0788, y: 0.4696), CGPoint(x: 0.0678, y: 0.5185),
          CGPoint(x: 0.0705, y: 0.5682), CGPoint(x: 0.0609, y: 0.6175), CGPoint(x: 0.0539, y: 0.6676),
          CGPoint(x: 0.0429, y: 0.7165), CGPoint(x: -0.009, y: 0.7696)
         ], 0.0453),
        // 05 右竖
        ("05", 429, 368, 51, 582,
         [
          CGPoint(x: 0.3997, y: 0.2176), CGPoint(x: 0.39, y: 0.2884), CGPoint(x: 0.39, y: 0.3424),
          CGPoint(x: 0.39, y: 0.3963), CGPoint(x: 0.39, y: 0.4503), CGPoint(x: 0.39, y: 0.5042),
          CGPoint(x: 0.39, y: 0.5582), CGPoint(x: 0.3942, y: 0.6109), CGPoint(x: 0.397, y: 0.6616),
          CGPoint(x: 0.4025, y: 0.7139), CGPoint(x: 0.4179, y: 0.7841)
         ], 0.0313),
        // 06 横折(反C):左上起笔 → 向右 → 右侧下弯 → 沿下横向左回勾
        ("06", 527, 176, 361, 311,
         [
          CGPoint(x: 0.5311, y: 0.049), CGPoint(x: 0.666, y: 0.0479), CGPoint(x: 0.7703, y: 0.0557),
          CGPoint(x: 0.8718, y: 0.0684), CGPoint(x: 0.946, y: 0.1152), CGPoint(x: 0.9599, y: 0.188),
          CGPoint(x: 0.9115, y: 0.2507), CGPoint(x: 0.8297, y: 0.2939), CGPoint(x: 0.7271, y: 0.3027),
          CGPoint(x: 0.6199, y: 0.3037), CGPoint(x: 0.4898, y: 0.2901)
         ], 0.0435),
        // 07 长竖钩
        ("07", 544, 291, 340, 884,
         [
          CGPoint(x: 0.5252, y: 0.1543), CGPoint(x: 0.6907, y: 0.1699), CGPoint(x: 0.8166, y: 0.1976),
          CGPoint(x: 0.8935, y: 0.2732), CGPoint(x: 0.9046, y: 0.3703), CGPoint(x: 0.9073, y: 0.4682),
          CGPoint(x: 0.9142, y: 0.5666), CGPoint(x: 0.9198, y: 0.6637), CGPoint(x: 0.9198, y: 0.764),
          CGPoint(x: 0.9295, y: 0.8615), CGPoint(x: 0.9514, y: 0.9875)
         ], 0.0488),
        // 08 匣:实为 U 形开口向上,非闭合方框
        ("08", 540, 534, 216, 344,
         [
          CGPoint(x: 0.5624, y: 0.3778), CGPoint(x: 0.5546, y: 0.4704), CGPoint(x: 0.5574, y: 0.5381),
          CGPoint(x: 0.5615, y: 0.6054), CGPoint(x: 0.5836, y: 0.6669), CGPoint(x: 0.6714, y: 0.6826),
          CGPoint(x: 0.7531, y: 0.6606), CGPoint(x: 0.7718, y: 0.5976), CGPoint(x: 0.7759, y: 0.5303),
          CGPoint(x: 0.7759, y: 0.4626), CGPoint(x: 0.7682, y: 0.37)
         ], 0.0417),
        // 09 匣内横
        ("09", 575, 656, 148, 61,
         [
          CGPoint(x: 0.5516, y: 0.5679), CGPoint(x: 0.5969, y: 0.5278), CGPoint(x: 0.641, y: 0.5244),
          CGPoint(x: 0.687, y: 0.5244), CGPoint(x: 0.7301, y: 0.5215), CGPoint(x: 0.7943, y: 0.5339)
         ], 0.0383),
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
            let median = SampledPath.openCatmullRom(mapped)
            return Layer(
                name: def.n, dest: dest, median: median, maskW: def.maskW,
                warp: DraftingMotion.makeWarp(median,
                                              exponent: DraftingMotion.curveExponent,
                                              speedRange: DraftingMotion.curveSpeedRange)
            )
        }
    }()

    /// 分笔位图(打包资源;缺失时该层跳过,动画不崩)
    static let strokeImages: [Image?] = {
        DraftingMotion.layerDefs.map { def in
            UIImage(named: "stroke-" + def.n).map { Image(uiImage: $0) }
        }
    }()

    static let strokeGap = 0.020    // 笔画间提笔基数(占书写段比例)

    // ---- v9:去机械感(用户反馈「还是很硬」) ----
    /// 曲率控速:v ∝ κ^(-curveExponent),速度比夹在 [1/curveSpeedRange, curveSpeedRange]
    static let curveExponent = 0.3333
    static let curveSpeedRange = 1.40
    /// 等时性(isochrony):笔越长写得越快,故时间片 ∝ 长度^alpha 而非 ∝ 长度
    static let isochronyAlpha = 0.65
    /// 笔画间停顿按字形层级分级(8 个间隙,倍率乘以 strokeGap)。
    /// 祐 = 礻(1-5) + 右,右 = 𠂇(6-7) + 口(8-9);部件边界处换气,故显著加长。
    static let gapScale: [Double] = [1.0, 1.35, 0.9, 0.9, 2.4, 1.2, 1.9, 1.0]
    static let gaps: [Double] = DraftingMotion.gapScale.map { $0 * DraftingMotion.strokeGap }

    /// 时间片:等时性 + 分级停顿
    static let spans: [(Double, Double)] = {
        let paths = DraftingMotion.layers
        let w = paths.map { pow(Double($0.median.total), DraftingMotion.isochronyAlpha) }
        let sumW = w.reduce(0, +)
        let sumGap = DraftingMotion.gaps.reduce(0, +)
        var spans: [(Double, Double)] = []
        var t = 0.0
        for i in 0..<paths.count {
            let share = (1 - sumGap) * (w[i] / sumW)
            spans.append((t, t + share))
            t += share + (i < DraftingMotion.gaps.count ? DraftingMotion.gaps[i] : 0)
        }
        return spans
    }()

    // ---- 时间线 ----
    static let writeSpan = (t0: 0.024, t1: 0.710)   // 书写 6.38s
    static let hoverEnd = 0.766              // [writeEnd, hoverEnd] 悬笔端详
    static let fadeSpan = (t0: 0.780, t1: 0.927)   // 墨沉消散
    static let returnSpan = (t0: 0.766, t1: 0.971) // 回笔(与消散重叠)
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

    // ---- v8 书写节奏:落笔 → 行笔 → 收笔。占比按本笔时间片计 ----
    static let downFrac = 0.08           // 落笔:墨不动,笔从 landHeight 降到纸面
    static let upFrac = 0.10             // 收笔:墨已满,笔提起离纸
    static let landHeight: CGFloat = 0.024   // 落笔起始高度(单位空间;随 v8 字形放大同步上调)
    static let liftHeight: CGFloat = 0.032   // 收笔抬起高度
    static let liftDrift: CGFloat = 0.016    // 收笔沿出锋方向的顺势带出
    /// 行笔速度曲线。峰值 1.72× 均速、起速 46%、收速 26%——加减速读得出但不甩鞭。
    /// 试过 Material (.40,0,.20,1),峰值 2.73× 且两端归零,配上静止段反而更顿挫。
    static let travelBezier: (Double, Double, Double, Double) = (0.45, 0.30, 0.45, 0.75)

    private static func bezAxis(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let m = 1 - t
        return 3 * m * m * t * a + 3 * m * t * t * b + t * t * t
    }

    /// 三次贝塞尔缓动:x→t 用二分(24 次即到浮点精度,且无牛顿迭代的收敛风险)
    static func travelEase(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let (x1, y1, x2, y2) = travelBezier
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<24 {
            let t = (lo + hi) / 2
            if bezAxis(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return bezAxis((lo + hi) / 2, y1, y2)
    }

    struct Rhythm {
        let prog: Double
        let lift: CGFloat
        let drift: CGFloat
    }

    /// 单笔节奏:落笔(墨不动,笔降到纸面) → 行笔(墨随缓动推进) → 收笔(墨已满,笔提起带出)。
    /// prog 同时驱动蒙版揭示与笔位,两者必须同源——各算各的,笔就会脱离墨的前沿。
    static func strokeRhythm(_ i: Int, _ wp: Double) -> Rhythm {
        let (t0, t1) = spans[i]
        let u = MotionEase.clamp01((wp - t0) / (t1 - t0))
        if u < downFrac {
            let q = u / downFrac
            return Rhythm(prog: 0, lift: landHeight * CGFloat(1 - MotionEase.smoothstep(q)), drift: 0)
        }
        if u > 1 - upFrac {
            let q = (u - (1 - upFrac)) / upFrac
            let s = CGFloat(MotionEase.smoothstep(q))
            return Rhythm(prog: 1, lift: liftHeight * s, drift: liftDrift * s)
        }
        // 行笔:先过整笔的加减速曲线,再经曲率时间扭曲映射到弧长(拐角自动放慢)
        let tt = travelEase((u - downFrac) / (1 - downFrac - upFrac))
        return Rhythm(prog: warpAt(layers[i].warp, tt), lift: 0, drift: 0)
    }


    /// 单笔内的笔尖位置(含离纸高度与出锋带出)
    static func strokePenPos(_ i: Int, _ wp: Double) -> CGPoint {
        let r = strokeRhythm(i, wp)
        let path = layers[i].median
        var p = path.point(at: r.prog)
        if r.drift > 0 {
            let a = path.point(at: 0.96)
            let b = path.point(at: 1)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len = max(hypot(dx, dy), 1e-6)
            p = CGPoint(x: p.x + dx / len * r.drift, y: p.y + dy / len * r.drift)
        }
        return CGPoint(x: p.x, y: p.y - r.lift)
    }

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

    /// 书写进度 wp∈[0,1] → 笔尖(笔画内含落笔/收笔;笔画间飞渡小弧)
    static func tipAt(_ wp: Double) -> CGPoint {
        for i in 0..<layers.count {
            let (t0, t1) = spans[i]
            if wp <= t1 {
                if wp >= t0 {
                    return strokePenPos(i, wp)
                }
                // 飞渡:自上一笔的收笔位(已离纸)落到下一笔的落笔位(悬在 landHeight)
                let prevEnd = strokePenPos(i - 1, spans[i - 1].1)
                let s0 = layers[i].median.point(at: 0)
                let curStart = CGPoint(x: s0.x, y: s0.y - landHeight)
                let g0 = spans[i - 1].1
                let q = (wp - g0) / (t0 - g0)
                let s = MotionEase.smoothstep(q)
                return CGPoint(
                    x: prevEnd.x + (curStart.x - prevEnd.x) * CGFloat(s),
                    y: prevEnd.y + (curStart.y - prevEnd.y) * CGFloat(s) - CGFloat(gapLift * sin(.pi * q))
                )
            }
        }
        return strokePenPos(layers.count - 1, 1)
    }

    /// 全局相位 → 笔尖位置与笔杆倾靠。写 → 悬 → 回笔 → 蓄势 → 写……全程连续。
    static func penState(_ p: Double) -> TipState {
        let startPos = layers[0].median.point(at: 0)
        let endPos = layers[layers.count - 1].median.point(at: 1)
        if p >= writeSpan.t0, p < writeSpan.t1 {
            return TipState(pos: tipAt((p - writeSpan.t0) / (writeSpan.t1 - writeSpan.t0)))
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
        pctx.rotate(by: .radians(penAngle))     // 固定倾角(v9 试过随行笔方向倾靠,抖动明显,已回退)
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

    /// 尺寸档位:实测(接触表 dpr-study,按 @1x/@2x/@3x 设备像素渲染)——
    /// 「祐」九笔密集,20 pt 三竖粘连、24–28 pt 临界并笔,36 pt 起笔笔分明。
    /// 故起草不进 20–28 pt 的小图标位,单列 36/44/56 pt(用户 2026-07-20 拍板)。
    static let spec = MotionSpec(
        id: "thinking-drafting-you",
        title: "Thinking|起草",
        subtitle: "9.3s · 钢笔写「祐」 · 曲率控速 · 36 pt 起",
        cycle: cycle,
        previewSizes: [36, 44, 56]
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
                        // 活动层:蒙版只揭示本层(消散阶段所有层已写完,不与蒙版并存)。
                        // 进度与笔位同源(strokeRhythm),落笔段 prog=0 故此时无墨。
                        let prog = m.strokeRhythm(i, writeP).prog
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
