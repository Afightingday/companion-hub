import SwiftUI

/// 私人线条动画的共享词汇:色板、线宽档、缓动。
/// 几何一律在单位空间 [0,1]²(y 向下)设计,渲染时按目标尺寸缩放。
/// 常量与 HTML 草样(motion-sketch.html)保持 1:1,改动需两边同步。
enum MotionPalette {
    /// PaperTheme.ink —— 抹茶深墨(纸面上的主体线色)
    static let ink = Color(motionHex: 0x2C382E)
    /// PaperTheme.matchaSoft —— 深底上的亮墨
    static let inkOnDark = Color(motionHex: 0xE7EBDA)
    /// 雨蓝(动画专用点缀,不在 PaperTheme 内)
    static let rainBlue = Color(motionHex: 0x6E94AD)
    static let rainBlueOnDark = Color(motionHex: 0x7FA6BE)
    /// PaperTheme.blush —— 腮红(本轮未用,留给「记忆|回泉」)
    static let blush = Color(motionHex: 0xE2B3B7)
    /// 暖金(动画专用,留给「时间|候潮」)
    static let warmGold = Color(motionHex: 0xC9A25E)

    /// 展板底色
    static let paperBg = Color(motionHex: 0xF5F2E8)
    static let paperCard = Color(motionHex: 0xFBF9F1)
    static let darkBg = Color(motionHex: 0x202823)
    static let inkMuted = Color(motionHex: 0x7C8477)
    static let inkMutedOnDark = Color(motionHex: 0x9AA394)

    static func stroke(dark: Bool) -> Color { dark ? inkOnDark : ink }
    static func rain(dark: Bool) -> Color { dark ? rainBlueOnDark : rainBlue }
}

/// 线宽档:20/24/28 pt 的光学修正(小尺寸相对更粗)。
/// 其他尺寸(如放大预览)按 24 pt 档等比放大,忠实呈现 24 pt 观感。
enum MotionLineWidth {
    static let table: [CGFloat: CGFloat] = [20: 1.55, 24: 1.75, 28: 1.95]
    static let refSize: CGFloat = 24

    static func width(for size: CGFloat) -> CGFloat {
        if let w = table[size] { return w }
        return table[refSize]! * size / refSize
    }
}

enum MotionEase {
    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    static func smoothstep(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * (3 - 2 * t)
    }

    static func easeInOutSine(_ x: Double) -> Double {
        -(cos(.pi * x) - 1) / 2
    }

    static func easeOutCubic(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }

    static func easeInQuad(_ x: Double) -> Double { x * x }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

extension Color {
    /// PaperTheme 同款 sRGB 十六进制;标签取 motionHex 以免与主 App 的 init(hex:) 冲突
    init(motionHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
