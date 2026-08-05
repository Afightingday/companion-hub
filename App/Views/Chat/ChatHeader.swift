import SwiftUI

/// 会话页的三副面孔。
/// `.contact`（改备注）2026-08-05 移除 —— 顶栏搬上系统导航栏之后它不再是一种「页面状态」，
/// 而是一张独立的编辑面板（见 `ChatRenameSheet`）。
enum ChatMode: Equatable {
    case idle, search, select
}

/// 编辑联系人：从顶栏里搬出来的。
///
/// 旧版是在自绘顶栏上做原位编辑 —— 头像从 46 长到 56、冒出相机角标、右边的搜索钮
/// 变成「完成」。系统导航栏只有 44pt，那套原位形变塞不进去，硬塞就是把导航栏改造成
/// 一个假顶栏，等于白搬。苹果自己也是把改名放进独立面板（信息、通讯录都是）。
///
/// 只在「完成」时回写；取消什么都不动。
struct ChatRenameSheet: View {
    let initialName: String
    var onChangeAvatar: () -> Void
    var onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                avatarButton
                TextField("名字", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 17))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(commit)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(YY.cream100)
            .navigationTitle("编辑联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: commit)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            draft = initialName
            // 面板刚上来那一帧焦点给不进去（旧顶栏那处也是 DispatchQueue.main.async 绕的）
            try? await Task.sleep(for: .milliseconds(220))
            focused = true
        }
    }

    private var avatarButton: some View {
        Button(action: onChangeAvatar) {
            SceneAsset.image("assets/chat/seal-you.png")
                .resizable()
                .scaledToFit()
                .padding(10)
                .frame(width: 76, height: 76)
                .background(YY.sage100, in: Circle())
                .overlay { Circle().strokeBorder(YY.borderHair, lineWidth: 1) }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(YY.ink500)
                        .frame(width: 26, height: 26)
                        .background(.white, in: Circle())
                        .shadow(color: YY.shadowInk.opacity(0.18), radius: 2, y: 1)
                        .offset(x: 2, y: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更换头像")
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}

/// 断网提示：不占导航栏的位置，作为一枚浮丸挂在栏下。
/// 底下垫玻璃 —— 光有虚线圈的话，正文从后面滚过去时字会糊在一起。
struct ChatOfflinePill: View {
    var body: some View {
        HStack(spacing: 7) {
            ChatPulseDot()
            Text("网络已断开")
                .font(.yyMono(11))
                .tracking(0.6)
                .foregroundStyle(YY.ink400)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 5)
        .yyGlassFloat(Capsule())
        .overlay {
            Capsule().strokeBorder(YY.ink300, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .transition(.opacity.combined(with: .offset(y: -6)))
        .allowsHitTesting(false)
    }
}

/// 会话内搜索：对位会话总览页的范式 —— 直接用那边同一枚 `NativeSearchBar`（UISearchBar 原件，
/// 自带放大镜/清空/取消与拼音组合期保护），贴在键盘上方。
/// 卷轴留在原地继续显示命中高亮；命中计数与上下跳做成一枚窄玻璃丸浮在搜索条正上方。
struct ChatSearchDock: View {
    @Binding var query: String
    let hitLabel: String
    var onPrev: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 9) {
            if hasQuery {
                HStack(spacing: 2) {
                    Text(hitLabel)
                        .font(.yyMono(12))
                        .tracking(0.5)
                        .foregroundStyle(YY.ink500)
                        .padding(.trailing, 6)
                    stepper("chevron.up", action: onPrev)
                    stepper("chevron.down", action: onNext)
                }
                .padding(.leading, 15)
                .padding(.trailing, 5)
                .padding(.vertical, 4)
                .yyGlassFloat(Capsule())
                .transition(.opacity.combined(with: .offset(y: 6)))
            }

            NativeSearchBar(text: $query, placeholder: "搜索这个对话", onCancel: onClose)
                .frame(height: 52)
        }
        .animation(.sceneStandard(0.24), value: hasQuery)
    }

    private func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(YY.ink500)
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 呼吸的小圆点（离线丸用）
struct ChatPulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(YY.ink400)
            .frame(width: 5, height: 5)
            .opacity(dim ? 0.35 : 1)
            .scaleEffect(dim ? 0.8 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.sceneStandard(0.8).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}
