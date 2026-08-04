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

/// 底部**悬浮胶囊**。整条浮在卷轴之上（下面不垫任何衬底），玻璃走系统原生液态玻璃。
/// 附件走系统原生动作单 + PhotosPicker / 相机 / 文件选择器。
struct ChatComposer: View {
    @Binding var draft: String
    @Binding var chip: ChatComposerChip?
    let streaming: Bool
    let offline: Bool
    var onSend: () -> Void
    var onStop: () -> Void
    var onAttachmentPicked: () -> Void

    @FocusState private var focused: Bool
    @State private var attachSheet = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPicker = false
    @State private var filePicker = false
    @State private var cameraPicker = false

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !offline
    }

    /// 单行时正好是个胶囊；长到多行也保持同一枚圆角，不跟着变形
    private var shell: some Shape { RoundedRectangle(cornerRadius: 26, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let chip {
                chipRow(chip)
                    .transition(.opacity.combined(with: .offset(y: 7)))
            }

            HStack(alignment: .bottom, spacing: 6) {
                ghostButton("plus", label: "附件") { attachSheet = true }

                TextField("写点什么", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .font(.system(size: 17))
                    .lineSpacing(17 * 0.28)
                    .foregroundStyle(YY.ink800)
                    .tint(YY.sage600)
                    .focused($focused)
                    .padding(.vertical, 9)

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
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .yyGlassFloat(shell)
        .animation(.sceneHover(0.26), value: chip)
        .animation(.sceneStandard(0.2), value: streaming)
        // ── 附件：系统原生动作单，不自制面板 ──
        .confirmationDialog("添加", isPresented: $attachSheet, titleVisibility: .visible) {
            Button("拍照") { cameraPicker = true }
            Button("照片图库") { photoPicker = true }
            Button("选择文件") { filePicker = true }
            Button("取消", role: .cancel) {}
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

    private func ghostButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(YY.ink500)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
