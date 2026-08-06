import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 输入区上方那枚小签：引用别人的话，或正在改自己的话
struct ChatComposerChip: Equatable {
    enum Kind { case quote, edit }
    var kind: Kind
    var text: String
    /// 引用时带上被引消息的 id，发送时进 replyTo
    var replyTo: String?
}

/// 底部**悬浮输入条**。整条浮在卷轴之上（下面不垫任何衬底），厚磨砂压底。
///
/// 版式抄 GPT 客户端（2026-08-06 #5，以入库截图 P5/P6 为准）：
/// 没字时保持一行 [＋｜写点什么｜发送]；打进**任意一个字**（含组合中的拼音）
/// 立即变两行 —— 文字独占上行整幅宽度，＋和发送沉到下行，谁也不挤谁。
/// `TextField` 在两种版式里都占 HStack 的同一个结构位，身份不换，
/// 组合期不被打断（swiftui-native-pitfalls 原则三：跨界状态跟着身份走）。
///
/// 附件不再弹气泡动作单（2026-08-06 #2，抄 DeepSeek）：＋号把键盘顶下去，
/// 原位升起一块面板 —— 横滚的最近照片条＋「拍照 / 相册 / 文件」三大块。
struct ChatComposer: View {
    @Binding var draft: String
    @Binding var chip: ChatComposerChip?
    /// 焦点由 ChatScreen 持有：收键盘这件事发生在输入条**之外**
    /// （点卷轴空白、下滑手势），焦点关在这里就够不着（祐祐 2026-08-05 真机反馈）。
    /// 声明顺序＝逐成员构造器的参数顺序，挪位置要连调用点一起改。
    @FocusState.Binding var focused: Bool
    let streaming: Bool
    let offline: Bool
    var onSend: () -> Void
    var onStop: () -> Void
    var onAttachmentPicked: () -> Void

    @State private var attachOpen = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPicker = false
    @State private var filePicker = false
    @State private var cameraPicker = false

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !offline
    }

    /// 有一个字就展开成两行（P6→本轮 P1 的切换点就是第一个字符）
    private var expanded: Bool { !draft.isEmpty }

    /// 单行时正好是个胶囊；长到多行也保持同一枚圆角，不跟着变形
    private var shell: RoundedRectangle { RoundedRectangle(cornerRadius: 26, style: .continuous) }

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let chip {
                    chipRow(chip)
                        .transition(.opacity.combined(with: .offset(y: 7)))
                }

                HStack(alignment: .bottom, spacing: 6) {
                    if !expanded { plusButton }

                    TextField("写点什么", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .font(.system(size: 17))
                        .lineSpacing(17 * 0.28)
                        .foregroundStyle(YY.ink800)
                        .tint(YY.sage600)
                        .focused($focused)
                        .padding(.vertical, 9)
                        .padding(.leading, expanded ? 10 : 0)
                        .padding(.trailing, expanded ? 10 : 0)

                    if !expanded { trailingControl }
                }

                if expanded {
                    HStack(spacing: 6) {
                        plusButton
                        Spacer(minLength: 0)
                        trailingControl
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .yyFrostedThick(shell)
            .animation(.sceneHover(0.26), value: chip)
            .animation(.sceneStandard(0.2), value: streaming)
            .animation(.sceneStandard(0.22), value: expanded)

            if attachOpen {
                ChatAttachPanel(
                    onCamera: { cameraPicker = true },
                    onAlbum: { photoPicker = true },
                    onFile: { filePicker = true },
                    onPhotoTapped: onAttachmentPicked
                )
                .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .animation(.sceneStandard(0.26), value: attachOpen)
        // 键盘一回来（点回输入框），面板就让位 —— 两个「底部住户」只能住一个
        .onChange(of: focused) { _, isFocused in
            if isFocused, attachOpen { attachOpen = false }
        }
        .photosPicker(isPresented: $photoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard item != nil else { return }
            photoItem = nil
            onAttachmentPicked()
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.item]) { _ in
            onAttachmentPicked()
        }
        .fullScreenCover(isPresented: $cameraPicker) {
            ChatCameraPicker { onAttachmentPicked() }
                .ignoresSafeArea()
        }
    }

    // MARK: - 控件

    /// ＋号：开面板（键盘退位）；面板开着时转 45° 变 ×，再点收回
    private var plusButton: some View {
        Button {
            Haptic.lightTap()
            if attachOpen {
                attachOpen = false
            } else {
                focused = false
                attachOpen = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(YY.ink500)
                .rotationEffect(.degrees(attachOpen ? 45 : 0))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.sceneStandard(0.22), value: attachOpen)
        .accessibilityLabel(attachOpen ? "收起附件面板" : "附件")
    }

    /// 右端：生成中是停止，平时是发送
    @ViewBuilder
    private var trailingControl: some View {
        if streaming {
            Button(action: onStop) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(YY.cream50)
                    .frame(width: 12, height: 12)
                    .frame(width: 38, height: 38)
                    .background(YY.sage600, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停止生成")
            .transition(.opacity.combined(with: .scale(scale: 0.7)))
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(YY.cream50)
                    .frame(width: 38, height: 38)
                    .background(YY.sage500, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.38)
            .scaleEffect(canSend ? 1 : 0.9)
            .animation(.sceneStandard(0.24), value: canSend)
            .accessibilityLabel("发送")
            .transition(.opacity.combined(with: .scale(scale: 0.7)))
        }
    }

    private func chipRow(_ chip: ChatComposerChip) -> some View {
        HStack(spacing: 7) {
            Image(systemName: chip.kind == .quote ? "arrowshape.turn.up.left" : "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(YY.sage600)
            Text(chip.text)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(YY.sage700)
                .lineLimit(1)
                .truncationMode(.tail)
            Button {
                self.chip = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(YY.sage600)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消")
        }
        .padding(.leading, 12)
        .padding(.trailing, 3)
        .frame(height: 34)
        .background(YY.sage100.opacity(0.9), in: Capsule())
        .overlay { Capsule().strokeBorder(YY.sage200, lineWidth: 1) }
        .frame(maxWidth: 268, alignment: .leading)
        .padding(.leading, 6)
    }
}

// MARK: - 附件面板（#2，抄 DeepSeek：照片条 + 三大块）

/// 最近照片横滚一条，下面「拍照 / 相册 / 文件」三块并排。
/// 相册权限第一次打开面板时才要；拿不到就换一行安静的说明，不弹窗不拦路。
private struct ChatAttachPanel: View {
    var onCamera: () -> Void
    var onAlbum: () -> Void
    var onFile: () -> Void
    /// 点中条上某张照片。附件通道还没接上，行为与三大块一致，由宿主统一交代。
    var onPhotoTapped: () -> Void

    @State private var thumbs: [UIImage] = []
    @State private var authState: PHAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 12) {
            photoStrip
            HStack(spacing: 10) {
                bigOption("camera", label: "拍照", action: onCamera)
                bigOption("photo.on.rectangle", label: "相册", action: onAlbum)
                bigOption("paperclip", label: "文件", action: onFile)
            }
        }
        .task { await loadThumbs() }
    }

    @ViewBuilder
    private var photoStrip: some View {
        switch authState {
        case .denied, .restricted:
            Text("在设置里允许访问相册，最近的照片会排在这里")
                .font(.system(size: 12.5))
                .foregroundStyle(YY.ink400)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        default:
            // 拉取中与空相册都按满高留位，缩略图到了不跳版
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(thumbs.indices, id: \.self) { i in
                        Button(action: onPhotoTapped) {
                            Image(uiImage: thumbs[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(YY.borderHair, lineWidth: 0.8)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 88)
        }
    }

    private func bigOption(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(YY.ink600)
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundStyle(YY.ink600)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(YY.cream50.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(YY.borderHair, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    /// 权限 → 取最近 24 张的缩略图。重活全在后台线程同步跑完再一次性上屏，
    /// 逐张异步回调会乱序（Photos 的 resultHandler 不保序）。
    @MainActor
    private func loadThumbs() async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        authState = status
        guard status == .authorized || status == .limited, thumbs.isEmpty else { return }

        let images = await Task.detached(priority: .userInitiated) { () -> [UIImage] in
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 24
            let assets = PHAsset.fetchAssets(with: .image, options: options)

            let req = PHImageRequestOptions()
            req.isSynchronous = true
            req.deliveryMode = .highQualityFormat
            req.resizeMode = .fast
            req.isNetworkAccessAllowed = false // iCloud 远端的不等，本地有啥排啥

            var out: [UIImage] = []
            let side: CGFloat = 88 * 3 // @3x
            assets.enumerateObjects { asset, _, _ in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: CGSize(width: side, height: side),
                    contentMode: .aspectFill,
                    options: req
                ) { image, _ in
                    if let image { out.append(image) }
                }
            }
            return out
        }.value
        thumbs = images
    }
}

/// 相机：直接包 UIImagePickerController，别自制取景器
struct ChatCameraPicker: UIViewControllerRepresentable {
    var onPicked: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        }
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: ChatCameraPicker
        init(_ parent: ChatCameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.dismiss()
            parent.onPicked()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
