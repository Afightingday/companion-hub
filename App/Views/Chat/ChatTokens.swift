import SwiftUI

/// 「祐识 · 奶油宣纸」设计令牌 —— 逐值对位设计稿的 tokens/colors.css、effects.css、typography.css。
/// 会话页只用这一套；缓动复用 SceneTokens 里已经 1:1 对齐 motion.css 的四条曲线。
enum YY {
    // ── 宣纸奶油中性色 ──
    static let cream50 = Color(hex: 0xFEFEFC)
    static let cream100 = Color(hex: 0xFBFAF5)
    static let cream200 = Color(hex: 0xF8F7F1)
    static let cream300 = Color(hex: 0xF5F4EF)
    static let cream400 = Color(hex: 0xEDEBE1)
    static let cream500 = Color(hex: 0xE0DDD0)
    static let cream600 = Color(hex: 0xCDC9BB)

    // ── 森林墨 ──
    static let ink900 = Color(hex: 0x2B3123)
    static let ink800 = Color(hex: 0x353D2B)
    static let ink700 = Color(hex: 0x3E4637)
    static let ink600 = Color(hex: 0x4E5743)
    static let ink500 = Color(hex: 0x5F6A4F)
    static let ink400 = Color(hex: 0x7C876A)
    static let ink300 = Color(hex: 0x9AA488)
    static let ink200 = Color(hex: 0xBAC2A9)

    // ── 鼠尾草绿 ──
    static let sage700 = Color(hex: 0x5E6E44)
    static let sage600 = Color(hex: 0x6E7E52)
    static let sage500 = Color(hex: 0x8A9A6B)
    static let sage400 = Color(hex: 0xA3B187)
    static let sage300 = Color(hex: 0xC2CBAF)
    static let sage200 = Color(hex: 0xDCE2CF)
    static let sage100 = Color(hex: 0xECEFE2)
    static let sage50 = Color(hex: 0xF4F6EE)

    static let gold600 = Color(hex: 0xB39A57)
    static let gold500 = Color(hex: 0xC6B275)
    static let rose600 = Color(hex: 0xC58E86)
    static let rose500 = Color(hex: 0xD6AAA3)
    static let rose400 = Color(hex: 0xE3BFB9)
    static let rose300 = Color(hex: 0xEDD2CD)
    static let rose200 = Color(hex: 0xF5E5E2)

    // ── 语义别名 ──
    static let page = cream300           // --paper-page，纸纹合成后的最终页色
    static let borderHair = cream500
    static let borderDash = ink300
    static let danger = Color(hex: 0xC57B6E)

    /// 划词涂痕 / 搜索命中底色（设计稿 marker 常量）
    static let marker = Color(hex: 0xC2CBAF).opacity(0.62)
    static let markerDim = Color(hex: 0xC2CBAF).opacity(0.28)

    /// 阴影墨：rgba(62,70,55,·)，暖绿灰，永不用纯黑
    static let shadowInk = Color(hex: 0x3E4637)

    // ── 圆角 ──
    static let rXS: CGFloat = 6
    static let rSM: CGFloat = 10
    static let rMD: CGFloat = 14
    static let rLG: CGFloat = 18
    static let rXL: CGFloat = 24
    static let r2XL: CGFloat = 32

    // ── iOS 系统色（原生控件对位，不进品牌色板）──
    static let systemDestructive = Color(red: 1, green: 0.231, blue: 0.188)     // #FF3B30
    static let systemLabel = Color(red: 0.110, green: 0.110, blue: 0.118)       // #1C1C1E
}

extension View {
    /// --shadow-sm：0 2px 6px rgba(62,70,55,.07), 0 1px 2px rgba(62,70,55,.05)
    func yyShadowSM() -> some View {
        shadow(color: YY.shadowInk.opacity(0.07), radius: 3, y: 2)
            .shadow(color: YY.shadowInk.opacity(0.05), radius: 1, y: 1)
    }

    /// --shadow-md：0 6px 16px rgba(62,70,55,.09), 0 2px 5px rgba(62,70,55,.06)
    func yyShadowMD() -> some View {
        shadow(color: YY.shadowInk.opacity(0.09), radius: 8, y: 6)
            .shadow(color: YY.shadowInk.opacity(0.06), radius: 2.5, y: 2)
    }

    /// 可按的原生液态玻璃（返回键、搜索钮、多选工具钮）。
    /// interactive 那档带系统自己的按压折射，别再自己拿白半透 + ultraThinMaterial 拼。
    func yyGlassControl(_ shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
    }

    /// 不可按的悬浮玻璃（时间胶囊、吐司、输入胶囊）。
    /// 走 .clear 清透档 —— .regular 在浅色纸面上会泛白（b21 已被点名过一次）。
    func yyGlassFloat(_ shape: some Shape) -> some View {
        glassEffect(.clear, in: shape)
    }

    /// 纸纹：中性噪点 soft-light，只加质感、不改页面平均明度
    func yyPaperGrain() -> some View {
        overlay {
            SceneAsset.image("assets/grain.png")
                .resizable(resizingMode: .tile)
                .opacity(0.045)
                .blendMode(.softLight)
                .allowsHitTesting(false)
        }
    }
}

/// 时间戳 / 计数用等宽体（--font-mono）
extension Font {
    static func yyMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
