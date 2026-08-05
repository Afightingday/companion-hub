import SwiftUI
import SwiftStreamingMarkdown
import UIKit

/// 祐识那边的正文渲染 —— 交给 microsoft/SwiftStreamingMarkdown（MIT，钉 v0.7.0）。
///
/// **为什么不是自己解析。** 流式排版真正难的是两件事，两件都不是祐识特有的：
/// 1. 新来的字要**逐词淡入**，而已经落纸的字一个像素都不许动 ——
///    包里是 UITextView + CADisplayLink，只对新追加的那段 range 改前景色 alpha；
/// 2. 模型吐到一半的 `**加粗` 还没吐右边的 `**`，标准解析器会当普通文字，
///    下一个 token 到了才变粗 —— 于是整段重排、闪一下。包里有个投机重写器
///    (`PartialEmphasisRewriter`)，抢先把这半截当粗体渲染，所以不跳版。表格同理。
///
/// 上一版我们是「流式期间显示原始 markdown 源码（星号都露着），写完那一刻一次性排版」，
/// 那一下就是祐祐说的跳版。同时也没有代码块 / 列表 / 表格 —— 现在一并有了。
///
/// 中文可用：分词走系统 `.byWords/.localized`，中文会切成「今天」这样的词，
/// 不是整句一坨闪（读过 `NSAttributedString+.splitIntoWords` 确认，不是猜的）。
enum ChatMarkdown {

    /// 正文字号与色，跟原来那行 `Text` 对齐（17.5 / ink700）
    static let bodySize: CGFloat = 17.5

    /// 流式中：新来的词淡入。
    static let streaming = makeConfig(animate: true)

    /// 已定稿：不再淡入。
    ///
    /// 为什么不干脆全程开着 —— 包里 `makeUIView` 一创建就整块 alpha 0→1 淡一次，
    /// 而 LazyVStack 是滚到哪儿才创建哪一行。全程开着的话，往上翻历史时
    /// 每条旧消息都会重新淡入一遍，那是错的。
    static let settled = makeConfig(animate: false)

    // MARK: - 纸面配色

    private static func makeConfig(animate: Bool) -> MarkdownRenderConfig {
        MarkdownRenderConfig(
            shouldAnimateText: animate,
            blockQuoteStyle: .init(
                textFonts: fonts(bodySize, italic: true),
                textColor: YY.ink500
            ),
            headingStyle: .init(
                h1Font: fonts(22, weight: .semibold),
                h2Font: fonts(20, weight: .semibold),
                h3Font: fonts(18.5, weight: .semibold),
                h4Font: fonts(bodySize, weight: .semibold),
                h5Font: fonts(bodySize, weight: .semibold),
                h6Font: fonts(bodySize, weight: .semibold),
                textColor: YY.ink800
            ),
            orderedListStyle: .init(textFonts: fonts(bodySize), textColor: YY.ink700),
            paragraphStyle: .init(textFonts: fonts(bodySize), textColor: YY.ink700),
            tableStyle: .init(
                textFonts: fonts(15),
                headerTextColor: YY.ink800,
                regularTextColor: YY.ink700,
                headerBackgroundColor: YY.cream400,
                borderColor: YY.cream500,
                actionButtonColor: YY.sage600
            ),
            inlineStyle: .init(
                boldTextColor: YY.ink800,
                linkTextFont: font(bodySize, weight: .regular),
                linkTextColor: YY.sage700,
                linkUnderlineStyle: .single,
                codeTextFont: .monospacedSystemFont(ofSize: 15.5, weight: .regular),
                codeTextColor: YY.ink600,
                codeBackgroundColor: YY.cream400,
                codeUnderlineColor: .clear
            ),
            // 引文药丸是 Copilot 的形态，祐识这边没有任何来源会吐它 ——
            // 开着只会让形如 `【1】` 的正文被误吃。关掉。
            citationConfig: .init(
                isEnabled: false,
                font: font(12, weight: .regular),
                textColor: YY.ink500,
                backgroundColor: YY.cream400
            ),
            // 代码块走**浅色**：包的默认是深底（Copilot 那个长相），
            // 一块深色方砖砸在宣纸上太扎眼。.xcode 主题在浅色外观下是深字浅底。
            codeBlockConfig: .init(
                theme: .xcode,
                backgroundColor: YY.cream400,
                foregroundColor: YY.ink400,
                codeTextFonts: fonts(14.5, mono: true),
                chromeTextFonts: fonts(12)
            ),
            // 包的默认 30 是给 Copilot 那种大字号版面的，落在 17.5 的正文上会散架
            blockSpacing: 14,
            // 「选更多文字」会弹一张它自带的全文选中面板 —— 又一个 Copilot 形态，
            // 且我们已经有长按行菜单里的拷贝/多选。关掉。
            textSelectionConfig: .init(isEnabled: false),
            thematicBreakColor: YY.cream500
        )
    }

    // MARK: - 字体零件

    private static func font(
        _ size: CGFloat,
        weight: UIFont.Weight = .regular,
        italic: Bool = false,
        mono: Bool = false
    ) -> UIFont {
        let base = mono
            ? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        guard italic, let slanted = base.fontDescriptor.withSymbolicTraits(.traitItalic) else {
            return base
        }
        return UIFont(descriptor: slanted, size: size)
    }

    /// 一档字号的四个变体。`preferredLineHeight` 这里给不给都没用 ——
    /// 包在正文那条路上把行距写死成 5pt（`BlockView` 里的 `lineSpacing: 5`），
    /// 只有「选更多文字」那张面板才读它。我们原来是 7pt，这 2pt 的差认了，
    /// 真要对齐得往上游提 PR，不值得为它开分叉。
    private static func fonts(
        _ size: CGFloat,
        weight: UIFont.Weight = .regular,
        italic: Bool = false,
        mono: Bool = false
    ) -> TextFonts {
        TextFonts(
            normal: font(size, weight: weight, italic: italic, mono: mono),
            italic: font(size, weight: weight, italic: true, mono: mono),
            bold: font(size, weight: .semibold, italic: italic, mono: mono),
            boldItalic: font(size, weight: .semibold, italic: true, mono: mono),
            preferredLetterSpacing: nil,
            preferredLineHeight: nil
        )
    }
}

/// 祐识那边的正文。不进任何容器，直接落在纸上（这条口径没变）。
struct ChatMarkdownBody: View {
    let text: String
    /// 只在流式中为真
    let animate: Bool

    var body: some View {
        MarkdownView(text: text, config: animate ? ChatMarkdown.streaming : ChatMarkdown.settled)
            .frame(maxWidth: .infinity, alignment: .leading)
            // ⚠️ 每段正文底下都是一个 `isSelectable = true` 的 UITextView，
            // 而那个属性写死在包内部，够不着。放着不管，它会把长按吃掉，
            // 祐祐设计的那张行菜单（编辑/引用/拷贝/多选/删除）就再也弹不出来。
            //
            // 这里整块关掉命中，把长按原样还给外层 `.contextMenu`。
            // **代价**：正文里的链接点不动了，代码块右上角那枚拷贝钮也点不动。
            // 装机看过之后再决定是定向放行，还是索性把长按让给系统文本选中
            // （包里有 `textContextMenu` 可以把我们的菜单项塞进系统编辑菜单）。
            .allowsHitTesting(false)
    }
}
