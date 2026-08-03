import SwiftUI

/// 聊天页自己的纸艺语言。数值来自「祐识 · 奶油宣纸」设计系统，
/// 但布局只服务 Conversation Screen，不污染全局 SceneTokens。
enum ChatPaperPalette {
    static let page = Color(hex: 0xF5F4EF)
    static let paperHigh = Color(hex: 0xFEFEFC)
    static let paper = Color(hex: 0xF8F7F1)
    static let paperRaised = Color(hex: 0xFBFAF5)
    static let paperInset = Color(hex: 0xEDEBE1)
    static let paperEdge = Color(hex: 0xE0DDD0)

    static let inkStrong = Color(hex: 0x353D2B)
    static let ink = Color(hex: 0x3E4637)
    static let inkMuted = Color(hex: 0x5F6A4F)
    static let inkFaint = Color(hex: 0x7C876A)
    static let inkGhost = Color(hex: 0x9AA488)

    static let sageDeep = Color(hex: 0x5E6E44)
    static let sage = Color(hex: 0x8A9A6B)
    static let sageSoft = Color(hex: 0xC2CBAF)
    static let sageWash = Color(hex: 0xECEFE2)
    static let sageMist = Color(hex: 0xF4F6EE)

    static let gold = Color(hex: 0xC6B275)
    static let goldWash = Color(hex: 0xEFE7CF)
    static let rose = Color(hex: 0xD6AAA3)
    static let roseWash = Color(hex: 0xF5E5E2)
    static let danger = Color(hex: 0xC57B6E)
}

/// 一张被手工裁过的纸：四角不等、底边略有起伏，刻意避开标准圆角卡片感。
struct ChatPaperCut: InsettableShape {
    var corner: CGFloat = 18
    var foldedCorner: Bool = false
    private var insetAmount: CGFloat = 0

    init(corner: CGFloat = 18, foldedCorner: Bool = false) {
        self.corner = corner
        self.foldedCorner = foldedCorner
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let c = max(6, min(corner - insetAmount, min(r.width, r.height) * 0.24))
        var path = Path()

        path.move(to: CGPoint(x: r.minX + c * 0.82, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c * (foldedCorner ? 1.34 : 0.76), y: r.minY + 0.8))
        if foldedCorner {
            path.addLine(to: CGPoint(x: r.maxX - 4, y: r.minY + c * 0.72))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + c * 1.16))
        } else {
            path.addQuadCurve(
                to: CGPoint(x: r.maxX, y: r.minY + c),
                control: CGPoint(x: r.maxX, y: r.minY)
            )
        }
        path.addLine(to: CGPoint(x: r.maxX - 0.7, y: r.maxY - c * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: r.maxX - c * 0.88, y: r.maxY),
            control: CGPoint(x: r.maxX, y: r.maxY)
        )
        path.addLine(to: CGPoint(x: r.minX + c * 1.10, y: r.maxY - 0.9))
        path.addQuadCurve(
            to: CGPoint(x: r.minX, y: r.maxY - c * 0.88),
            control: CGPoint(x: r.minX, y: r.maxY)
        )
        path.addLine(to: CGPoint(x: r.minX + 0.8, y: r.minY + c * 0.64))
        path.addQuadCurve(
            to: CGPoint(x: r.minX + c * 0.82, y: r.minY),
            control: CGPoint(x: r.minX, y: r.minY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ChatPaperCut {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// 纸边铅笔线：不是规则 Divider，三段轻微错位制造手绘感。
struct ChatPencilRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: y + 0.5))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: y - 0.4),
            control1: CGPoint(x: rect.minX + rect.width * 0.28, y: y - 1.1),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: y + 1.0)
        )
        return path
    }
}

struct ChatWashiTape: View {
    var color: Color = ChatPaperPalette.goldWash
    var width: CGFloat = 54

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 2,
            bottomLeadingRadius: 4,
            bottomTrailingRadius: 2,
            topTrailingRadius: 5,
            style: .continuous
        )
        .fill(color.opacity(0.84))
        .overlay {
            ChatPencilRule()
                .stroke(ChatPaperPalette.inkGhost.opacity(0.16), lineWidth: 0.7)
                .padding(.horizontal, 5)
        }
        .frame(width: width, height: 15)
        .rotationEffect(.degrees(-2.2))
        .blendMode(.multiply)
        .accessibilityHidden(true)
    }
}

private struct ChatPaperTextureModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            SceneAsset.image("assets/grain.png")
                .resizable(resizingMode: .tile)
                .opacity(0.042)
                .blendMode(.softLight)
                .mask(content)
                .allowsHitTesting(false)
        }
    }
}

private struct ChatPaperShadowModifier: ViewModifier {
    var raised: Bool

    func body(content: Content) -> some View {
        content
            .shadow(
                color: SceneTokens.shadowInk.opacity(raised ? 0.09 : 0.055),
                radius: raised ? 12 : 6,
                x: 0,
                y: raised ? 7 : 3
            )
            .shadow(
                color: SceneTokens.shadowInk.opacity(raised ? 0.045 : 0.025),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

extension View {
    func chatPaperTexture() -> some View {
        modifier(ChatPaperTextureModifier())
    }

    func chatPaperShadow(raised: Bool = false) -> some View {
        modifier(ChatPaperShadowModifier(raised: raised))
    }
}

extension String {
    /// Swift 的 hashValue 每次启动会变；手账纸片的位置必须跨启动稳定。
    private var chatStableSeed: UInt64 {
        unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { value, scalar in
            (value ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
    }

    var chatStableTilt: Double {
        let step = Int(chatStableSeed % 9) - 4
        return Double(step) * 0.14
    }

    var chatScrapbookVariant: Int {
        Int(chatStableSeed % 3)
    }
}
