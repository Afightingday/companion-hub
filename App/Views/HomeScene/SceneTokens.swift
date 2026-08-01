import SwiftUI
import UIKit

/// 会话总览页专用令牌 —— 镜像设计稿 sandbox/youshi-home/src/styles/tokens.css。
/// 只放本页用到的值；PaperTheme 是 packages/paper-ui 的镜像，别混进来。
enum SceneTokens {
    // ── 宣纸奶油中性色 ──
    static let cream100 = Color(hex: 0xFBFAF5)
    static let cream300 = Color(hex: 0xF5F4EF)
    static let cream500 = Color(hex: 0xE0DDD0)

    // ── 森林墨 ──
    static let ink900 = Color(hex: 0x2B3123)
    static let ink800 = Color(hex: 0x353D2B)
    static let ink600 = Color(hex: 0x4E5743)
    static let ink500 = Color(hex: 0x5F6A4F)
    static let ink400 = Color(hex: 0x7C876A)
    static let ink300 = Color(hex: 0x9AA488)

    // ── 鼠尾草绿 ──
    static let sage300 = Color(hex: 0xC2CBAF)
    static let sage400 = Color(hex: 0xA3B187)
    static let sage600 = Color(hex: 0x6E7E52)
    static let sage700 = Color(hex: 0x5E6E44)

    /// 阴影墨（--shadow-* 里的 rgba(62,70,55,…) 基色 = ink-700）
    static let shadowInk = Color(hex: 0x3E4637)
    /// 开卡遮罩 rgba(43,49,35,.16)
    static let scrim = Color(hex: 0x2B3123).opacity(0.16)
    static let paperPage = Color(hex: 0xF5F4EF)

    /// 设计稿坐标系 = iPhone 16 Pro Max 440×956pt，1:1 落地
    static let designW: CGFloat = 440
    static let designH: CGFloat = 956
}

// MARK: - 缓动（tokens.css 的四条贝塞尔）

extension Animation {
    /// --ease-standard: cubic-bezier(0.4, 0.14, 0.3, 1)
    static func sceneStandard(_ d: Double) -> Animation { .timingCurve(0.4, 0.14, 0.3, 1, duration: d) }
    /// --ease-out: cubic-bezier(0.2, 0.7, 0.3, 1)
    static func sceneOut(_ d: Double) -> Animation { .timingCurve(0.2, 0.7, 0.3, 1, duration: d) }
    /// --ease-gentle: cubic-bezier(0.32, 0.72, 0.28, 1)
    static func sceneGentle(_ d: Double) -> Animation { .timingCurve(0.32, 0.72, 0.28, 1, duration: d) }
    /// --ease-hover: cubic-bezier(0.34, 1.2, 0.64, 1)（带过冲）
    static func sceneHover(_ d: Double) -> Animation { .timingCurve(0.34, 1.2, 0.64, 1, duration: d) }
}

// MARK: - 资产加载（Media 以文件夹引用打包，子路径保留；不能叫 Resources——iOS 会误判包布局）

enum SceneAsset {
    private static var cache: [String: UIImage] = [:]

    /// 路径与设计稿 public/ 同构，如 "art/claude-idle.png"、"assets/room-master.png"
    static func uiImage(_ path: String) -> UIImage {
        if let hit = cache[path] { return hit }
        let ns = path as NSString
        let name = (ns.lastPathComponent as NSString).deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "png" : ns.pathExtension
        let dir = ns.deletingLastPathComponent
        var url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Media/" + dir)
        if url == nil { url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: dir) }
        if url == nil { url = Bundle.main.url(forResource: name, withExtension: ext) }
        let image = url.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage()
        cache[path] = image
        return image
    }

    static func image(_ path: String) -> Image { Image(uiImage: uiImage(path)) }
}

// MARK: - 字体（LXGW WenKai Screen，--font-note / --font-hand 一体承担）

enum SceneFont {
    /// PostScript 名；万一注册名不同，运行时按家族名兜底找一次
    private static let resolved: String? = {
        if UIFont(name: "LXGWWenKaiScreen", size: 12) != nil { return "LXGWWenKaiScreen" }
        for family in UIFont.familyNames where family.lowercased().contains("wenkai") {
            if let name = UIFont.fontNames(forFamilyName: family).first { return name }
        }
        return nil
    }()

    /// 手写体（覆膜摘要、添新识、名牌）
    static func note(_ size: CGFloat) -> Font {
        if let name = resolved { return .custom(name, size: size) }
        return .system(size: size, design: .serif)
    }
}

// MARK: - 波形小工具（把 CSS 无限往返动画换成时间轴函数）

enum SceneWave {
    /// ease-in-out 往返 0→1→0；delay 语义同 CSS animation-delay（负值=提前相位）
    static func pingPong(_ date: Date, period: Double, delay: Double = 0) -> Double {
        let t = date.timeIntervalSinceReferenceDate - delay
        let u = ((t.truncatingRemainder(dividingBy: period)) + period).truncatingRemainder(dividingBy: period) / period
        return 0.5 - 0.5 * cos(2 * .pi * u)
    }

    /// 循环进度 0..<1
    static func cycle(_ date: Date, period: Double, delay: Double = 0) -> Double {
        let t = date.timeIntervalSinceReferenceDate - delay
        return ((t.truncatingRemainder(dividingBy: period)) + period).truncatingRemainder(dividingBy: period) / period
    }

    /// 分段关键帧插值（每段 ease-in-out，对位 CSS 默认逐段缓动）
    static func keyframes(_ u: Double, _ frames: [(Double, Double)]) -> Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        if u <= first.0 { return first.1 }
        if u >= last.0 { return last.1 }
        for i in 1..<frames.count where u <= frames[i].0 {
            let (t0, v0) = frames[i - 1]
            let (t1, v1) = frames[i]
            let raw = t1 - t0 < 1e-9 ? 1 : (u - t0) / (t1 - t0)
            let eased = raw < 0.5 ? 2 * raw * raw : 1 - 2 * (1 - raw) * (1 - raw)
            return v0 + (v1 - v0) * eased
        }
        return last.1
    }
}
