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

    /// 不可按的悬浮玻璃（时间胶囊、吐司、离线丸）。
    /// 走 .clear 清透档 —— .regular 在浅色纸面上会泛白（b21 已被点名过一次）。
    func yyGlassFloat(_ shape: some Shape) -> some View {
        glassEffect(.clear, in: shape)
    }

    /// **厚磨砂**：输入条专用（祐祐 2026-08-05 点名）。
    ///
    /// 液态玻璃那套折射和动态高光挂在常驻的输入条上是错的 —— 正文从它背后滚过去时，
    /// 折射会跟着字一起动，整条边缘一直在呼吸，看久了发晕，也是掉帧的一份。
    /// 输入条要的是**安静的底**：厚磨砂压住背景，再叠一层乳白提亮，不反光不折射。
    func yyFrostedThick(_ shape: some InsettableShape) -> some View {
        background {
            shape.fill(.ultraThickMaterial)
            shape.fill(Color.white.opacity(0.38))
        }
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
        }
        .yyShadowMD()
    }
}

/// 会话页底纹 —— 祐祐生成的格纸背景（纸鹤 / 一枝叶 / 星芒 / 「Youyou」签名都在图里）。
///
/// 两点定法：
/// 1. **不再叠 `grain.png`**：这张图自带纸纹与网格，再叠一层噪点只会糊掉网格；
/// 2. 图是 853×1844（1:2.161），和 19.5:9 的机型几乎同比，`scaledToFill` 裁切极小；
///    万一遇上比例更方的机型，底下垫 `YY.page` 兜底，不会露白。
struct ChatBackdrop: View {
    var body: some View {
        SceneAsset.image("assets/chat/paper-bg.png")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // regions 显式给 .all：容器 + 键盘一起豁免。键盘弹起时壁纸寸步不让（#3），
            // 宿主侧还把它挂到了 NavigationStack 外面，双保险。
            .ignoresSafeArea(.all)
            .background(YY.page.ignoresSafeArea(.all))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - 自绘图标语言（2026-08-06 #15）
//
// 对标首页底栏那套 PNG 线稿（Media/art/tabbar/*.png）：**单色细线、圆头圆折、
// 无填充、无容器**。会话页所有自绘 glyph 从这里出——24 视框、1.7pt 描边、
// round cap/join；SF Symbols 该系统的照旧归系统。

enum YYGlyph {
    /// 统一描边：改粗细只许改这里
    static func stroke(_ width: CGFloat = 1.7) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

/// 重答/重试：手绕的一个圈，收笔越过起笔、带一个小箭头 ——
/// 「再来一遍」的手势本身。替换掉旧的 DS 弧+直角折（2026-08-06 #6/#14 点名难看）。
struct GlyphRetry: Shape {
    func path(in rect: CGRect) -> Path {
        let s = Double(min(rect.width, rect.height)) / 24
        let cx = Double(rect.midX)
        let cy = Double(rect.midY)
        var p = Path()

        // 圈：从上方偏左起笔，顺时针绕 335°，半径微涨 —— 像手画的，不是圆规画的
        let steps = 56
        let startDeg = -100.0
        let endDeg = 235.0
        var tail = CGPoint.zero
        var tangent = (dx: 1.0, dy: 0.0)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = (startDeg + (endDeg - startDeg) * t) * Double.pi / 180
            let r = (7.4 + 1.8 * t) * s
            let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
            if i == 0 {
                p.move(to: pt)
            } else {
                p.addLine(to: pt)
                if i == steps {
                    tangent = (dx: Double(pt.x - tail.x), dy: Double(pt.y - tail.y))
                }
            }
            tail = pt
        }

        // 箭头：两根倒刺沿收笔方向张开（±150°），一眼读出「转回去再来」
        let len = (tangent.dx * tangent.dx + tangent.dy * tangent.dy).squareRoot()
        guard len > 0 else { return p }
        let ux = tangent.dx / len
        let uy = tangent.dy / len
        let barb = 3.6 * s
        for deg in [150.0, -150.0] {
            let a = deg * Double.pi / 180
            let bx = ux * cos(a) - uy * sin(a)
            let by = ux * sin(a) + uy * cos(a)
            p.move(to: tail)
            p.addLine(to: CGPoint(x: Double(tail.x) + bx * barb, y: Double(tail.y) + by * barb))
        }
        return p
    }
}

/// 思考链的品牌图形（#17）：一缕卷起来的墨丝。不是星星，不带容器 ——
/// 想法还没成形，先卷着。
struct GlyphThoughtCurl: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        let steps = 56
        let turns = 1.7
        let rMax = 8.8 * Double(s)
        let rMin = 1.8 * Double(s)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = -Double.pi / 2.6 + t * turns * 2 * Double.pi
            let r = rMax - (rMax - rMin) * t
            let pt = CGPoint(x: c.x + CGFloat(cos(a) * r), y: c.y + CGFloat(sin(a) * r))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// 时间戳 / 计数用等宽体（--font-mono）
extension Font {
    static func yyMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
