import SwiftUI
import UIKit

/// B6：拍立得覆膜的原生软翻页（2026-08-01 祐祐收官清单②）。
/// Demo 的 CoverLift 硬翻牌在正式版换成 UIPageViewController(.pageCurl)——
/// 公开 UIKit API、跟手、可半途回弹，本身即软卷页，以「软」为准绳。
/// 页序（isDoubleSided）：[膜面, 膜背(素色镜像), 揭示页(底卡同区域)]，
/// 翻走落在揭示页上→与真身底卡无缝重合→通知外层摘膜。
/// 摘要/时间/掀开提示手写在膜面空白正中央，随膜一起翻走。
///
/// 容器必须是膜的「实测可见框」（cardSize 内衬 insets）：拍立得 PNG 画布
/// 四周有透明余白，若按整卡挂载，pageCurl 会连隐形边一起卷、系统卷页
/// 阴影涂满透明区——真机上就是「黑乎乎一大页」（2026-08-01 实证）。
/// 三页都按整卡尺寸铺图再往左上挪 insets，页内像素与底卡逐点对位。
struct CoverCurlView: UIViewControllerRepresentable {
    let coverPath: String
    /// 底卡图路径：给揭示页画「翻完后该露出的那块」，卷页影有实底可落
    let cardPath: String
    let preview: String
    let time: String
    /// 整卡设计尺寸（246×328）
    let cardSize: CGSize
    /// 膜可见框在整卡里的内衬（各 cover.png alpha 包围盒实测）
    let insets: EdgeInsets
    var onCurlStart: () -> Void
    var onCancelled: () -> Void
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)])
        pvc.isDoubleSided = true
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        // 膜要能越出卡面（覆膜容器不裁切，docs/09 铁律③）
        pvc.view.clipsToBounds = false
        context.coordinator.buildPages(self)
        pvc.setViewControllers([context.coordinator.pages[0]], direction: .forward, animated: false)
        // 只留拖拽掀膜；点按翻页禁用（demo 口径：捻住一角，轻轻掀开）
        for recognizer in pvc.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: CoverCurlView
        var pages: [UIViewController] = []
        private let filmState = FilmNoteState()

        init(_ parent: CoverCurlView) {
            self.parent = parent
            super.init()
        }

        func buildPages(_ parent: CoverCurlView) {
            let face = UIHostingController(rootView: FilmFaceView(
                coverPath: parent.coverPath, preview: parent.preview,
                time: parent.time, cardSize: parent.cardSize,
                insets: parent.insets, state: filmState))
            let back = UIHostingController(rootView: FilmBackView(
                coverPath: parent.coverPath, cardSize: parent.cardSize, insets: parent.insets))
            let reveal = UIHostingController(rootView: FilmRevealView(
                cardPath: parent.cardPath, cardSize: parent.cardSize, insets: parent.insets))
            for vc in [face, back, reveal] {
                vc.view.backgroundColor = .clear
            }
            pages = [face, back, reveal]
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let i = pages.firstIndex(of: viewController), i + 1 < pages.count else { return nil }
            return pages[i + 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            nil // 掀开不可复封（demo 同口径）
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                willTransitionTo pendingViewControllers: [UIViewController]) {
            filmState.hintHidden = true
            parent.onCurlStart()
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            if completed, pageViewController.viewControllers?.first === pages.last {
                let done = parent.onDone
                DispatchQueue.main.async { done() }
            } else if !completed {
                filmState.hintHidden = false
                parent.onCancelled()
            }
        }
    }
}

/// 膜面提示的可变状态（掀动即隐、松手复现）
final class FilmNoteState: ObservableObject {
    @Published var hintHidden = false
}

/// 膜面：整卡覆膜图按可见框偏移映射 + 空白区手写摘要
///（card.css .cover-lift__note 对位：横 72%、纵 65% 都相对整卡换算）
struct FilmFaceView: View {
    let coverPath: String
    let preview: String
    let time: String
    let cardSize: CGSize
    let insets: EdgeInsets
    @ObservedObject var state: FilmNoteState

    var body: some View {
        let pageW = cardSize.width - insets.leading - insets.trailing
        let pageH = cardSize.height - insets.top - insets.bottom
        ZStack(alignment: .topLeading) {
            SceneAsset.image(coverPath)
                .resizable()
                .frame(width: cardSize.width, height: cardSize.height)
                .offset(x: -insets.leading, y: -insets.top)

            VStack(spacing: 0) {
                Text(preview)
                    .font(SceneFont.note(14.5))
                    .foregroundStyle(SceneTokens.ink600)
                    .lineSpacing(4)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 7)
                Text(time)
                    .font(SceneFont.note(11.5))
                    .foregroundStyle(SceneTokens.ink600.opacity(0.62))
                Text("捻住一角，轻轻掀开")
                    .font(SceneFont.note(12))
                    .tracking(1.4)
                    .foregroundStyle(SceneTokens.sage600)
                    .opacity(state.hintHidden ? 0 : 0.85)
                    .animation(.sceneStandard(0.2), value: state.hintHidden)
                    .padding(.top, 13)
            }
            .frame(width: cardSize.width * 0.72)
            .position(x: cardSize.width / 2 - insets.leading,
                      y: cardSize.height * 0.65 - insets.top)
        }
        .frame(width: pageW, height: pageH, alignment: .topLeading)
    }
}

/// 膜背：同一张剪影图压成素色纸背（brightness 1.12 / saturate .22 / contrast .92 的近似），
/// 沿门轴镜像（demo 里背面绕铰链翻 180°）——先裁到可见框再整页镜像
struct FilmBackView: View {
    let coverPath: String
    let cardSize: CGSize
    let insets: EdgeInsets

    var body: some View {
        SceneAsset.image(coverPath)
            .resizable()
            .frame(width: cardSize.width, height: cardSize.height)
            .saturation(0.22)
            .brightness(0.09)
            .contrast(0.92)
            .offset(x: -insets.leading, y: -insets.top)
            .frame(width: cardSize.width - insets.leading - insets.trailing,
                   height: cardSize.height - insets.top - insets.bottom,
                   alignment: .topLeading)
            .scaleEffect(x: -1)
    }
}

/// 揭示页：不再用全透明页——pageCurl 过程中的卷页阴影要有实底可落，
/// 全透明页会让系统把影子涂在遮罩/照片上，读作「黑乎乎」。
/// 画的就是底卡同一区域，翻完与下方真身逐点重合，摘膜瞬间无缝。
struct FilmRevealView: View {
    let cardPath: String
    let cardSize: CGSize
    let insets: EdgeInsets

    var body: some View {
        SceneAsset.image(cardPath)
            .resizable()
            .frame(width: cardSize.width, height: cardSize.height)
            .offset(x: -insets.leading, y: -insets.top)
            .frame(width: cardSize.width - insets.leading - insets.trailing,
                   height: cardSize.height - insets.top - insets.bottom,
                   alignment: .topLeading)
    }
}
