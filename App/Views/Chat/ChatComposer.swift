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

/// 底部信笺。附件走系统原生动作单 + PhotosPicker / 相机 / 文件选择器。
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let chip {
                chipRow(chip)
                    .transition(.opacity.combined(with: .offset(y: 7)))
            }

            TextField("写点什么", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.system(size: 15.5))
                .lineSpacing(15.5 * 0.5)
                .foregroundStyle(YY.ink800)
                .tint(YY.sage600)
                .focused($focused)
                .padding(.horizontal, 3)
                .padding(.top, 3)
                .padding(.bottom, 5)

            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    ghostButton("plus", label: "附件") { attachSheet = true }
                    ghostButton("camera", label: "拍照") { cameraPicker = true }
                }
                Spacer(minLength: 8)
                if streaming {
                    Button(action: onStop) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(YY.cream50)
                            .frame(width: 11, height: 11)
                            .frame(width: 34, height: 34)
                            .background(YY.sage600, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("停止生成")
                    .transition(.opacity)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(YY.cream50)
                            .frame(width: 34, height: 34)
                            .background(YY.sage500, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.38)
                    .animation(.sceneStandard(0.24), value: canSend)
                    .accessibilityLabel("发送")
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(YY.cream50, in: RoundedRectangle(cornerRadius: YY.rXL, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: YY.rXL, style: .continuous)
                .strokeBorder(YY.borderHair, lineWidth: 1)
        }
        .yyShadowComposer()
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
        HStack(spacing: 6) {
            Image(systemName: chip.kind == .quote ? "arrowshape.turn.up.left" : "pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(YY.sage600)
            Text(chip.text)
                .font(.system(size: 12.5, weight: .bold))
                .kerning(0.12)
                .foregroundStyle(YY.sage700)
                .lineLimit(1)
                .truncationMode(.tail)
            Button {
                self.chip = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(YY.sage600)
                    .frame(width: 23, height: 23)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 31)
        .background(YY.cream300, in: Capsule())
        .overlay { Capsule().strokeBorder(YY.cream500, lineWidth: 1) }
        .frame(maxWidth: 260, alignment: .leading)
    }

    private func ghostButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(YY.ink500)
                .frame(width: 34, height: 34)
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
