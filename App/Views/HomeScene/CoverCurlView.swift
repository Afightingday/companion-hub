import SwiftUI
import UIKit

/// B6：拍立得覆膜的原生软翻页（2026-08-01 祐祐收官清单②）。
/// Demo 的 CoverLift 硬翻牌在正式版换成 UIPageViewController(.pageCurl)——
/// 公开 UIKit API、跟手、可半途回弹，本身即软卷页，以「软」为准绳。
/// 页序（isDoubleSided）：[膜面, 膜背(素色镜像), 透明揭示页]，
/// 翻走落在透明页上→穿透看到底卡→通知外层摘膜。
/// 摘要/时间/掀开提示手写在膜面空白正中央，随膜一起翻走。
struct CoverCurlView: UIViewControllerRepresentable {
    let coverPath: String
    let preview: String
    let time: String
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
                time: parent.time, state: filmState))
            let back = UIHostingController(rootView: FilmBackView(coverPath: parent.coverPath))
            let reveal = UIViewController()
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

/// 膜面：整卡覆膜图 + 空白区手写摘要（card.css .cover-lift__note 对位）
struct FilmFaceView: View {
    let coverPath: String
    let preview: String
    let time: String
    @ObservedObject var state: FilmNoteState

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                SceneAsset.image(coverPath)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)

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
                .frame(width: w * 0.72)
                .position(x: w / 2, y: h * 0.65)
            }
        }
        .background(Color.clear)
    }
}

/// 膜背：同一张剪影图压成素色纸背（brightness 1.12 / saturate .22 / contrast .92 的近似），
/// 沿门轴镜像（demo 里背面绕铰链翻 180°）
struct FilmBackView: View {
    let coverPath: String

    var body: some View {
        GeometryReader { geo in
            SceneAsset.image(coverPath)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .saturation(0.22)
                .brightness(0.09)
                .contrast(0.92)
                .scaleEffect(x: -1)
        }
        .background(Color.clear)
    }
}
