import SwiftUI

enum ChatMode: Equatable {
    case idle, search, select, contact
}

/// 顶栏浮在纸面上，本身不带底色。圆钮全走系统原生液态玻璃。
/// 常态 / 多选两副长相原位互换；改备注时名字就地长成输入框。
/// **搜索不在这条上** —— 对位会话总览页的范式，搜索条贴在键盘上方（见 ChatSearchDock）。
struct ChatHeaderBar: View {
    @Binding var mode: ChatMode
    @Binding var name: String
    let offline: Bool
    let pickedCount: Int
    /// 从 UIWindow 取得的真实顶部安全区。放在顶栏内部，绘制帧与命中帧才是同一个。
    let safeTop: CGFloat
    var onBack: () -> Void
    var onCommitName: () -> Void
    var onChangeAvatar: () -> Void

    @FocusState private var nameFocused: Bool

    private var isContact: Bool { mode == .contact }

    var body: some View {
        VStack(spacing: 10) {
            if mode == .select {
                selectBar
            } else {
                normalBar
            }
            if offline { offlinePill }
        }
        .padding(.horizontal, 12)
        .padding(.top, safeTop + 6)
        .padding(.bottom, 14)
        .animation(.sceneHover(0.28), value: mode)
        .animation(.sceneStandard(0.3), value: offline)
    }

    // MARK: - 常态 / 改备注

    private var normalBar: some View {
        HStack(spacing: 9) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(YY.ink600)
                    .frame(width: 42, height: 42)
            }
            // 首页同款真机已验证的原生玻璃 Button；不要把 interactive glass 挂在 label 上。
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("返回")

            HStack(spacing: 12) {
                avatar
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(YY.ink800)
                    .tint(YY.sage500)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .disabled(!isContact)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { finishContact() }
                    .padding(.horizontal, isContact ? 14 : 0)
                    .frame(minHeight: 36)
                    .background(
                        isContact
                            ? Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.09)
                            : .clear,
                        in: RoundedRectangle(cornerRadius: YY.rSM, style: .continuous)
                    )
                    .overlay {
                        if isContact {
                            RoundedRectangle(cornerRadius: YY.rSM, style: .continuous)
                                .strokeBorder(
                                    Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.1),
                                    lineWidth: 0.5
                                )
                        }
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard mode == .idle else { return }
                mode = .contact
                DispatchQueue.main.async { nameFocused = true }
            }

            rightPill
        }
    }

    private var avatar: some View {
        SceneAsset.image("assets/chat/seal-you.png")
            .resizable()
            .scaledToFit()
            .padding(isContact ? 7.4 : 6)
            .frame(width: isContact ? 56 : 46, height: isContact ? 56 : 46)
            .background(YY.sage100, in: Circle())
            .overlay { Circle().strokeBorder(YY.borderHair, lineWidth: 1) }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.55))
                    .frame(width: 22, height: 22)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .offset(x: 3, y: 3)
                    .opacity(isContact ? 1 : 0)
                    .scaleEffect(isContact ? 1 : 0.5)
            }
            .contentShape(Circle())
            .onTapGesture {
                guard isContact else { return }
                onChangeAvatar()
            }
            .animation(.sceneHover(0.3), value: isContact)
    }

    private var rightPill: some View {
        Button {
            if isContact { finishContact() } else { openSearch() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(YY.ink600)
                    .frame(width: isContact ? 0 : 18)
                    .opacity(isContact ? 0 : 1)
                    .clipped()
                if isContact {
                    Text("完成")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(YY.sage600)
                }
            }
            .frame(minWidth: 42, minHeight: 42)
            .padding(.horizontal, isContact ? 16 : 0)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(isContact ? "完成" : "搜索")
    }

    // MARK: - 多选

    private var selectBar: some View {
        HStack {
            Button { mode = .idle } label: {
                Text("取消")
                    .font(.system(size: 17))
                    .foregroundStyle(YY.sage600)
            }
            .buttonStyle(.plain)

            Text(pickedCount > 0 ? "已选 \(pickedCount) 条" : "选择消息")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(YY.ink700)
                .frame(maxWidth: .infinity)

            Color.clear.frame(width: 36, height: 1)
        }
        .frame(height: 42)
    }

    // MARK: - 离线

    private var offlinePill: some View {
        HStack(spacing: 7) {
            ChatPulseDot()
            Text("网络已断开")
                .font(.yyMono(11))
                .tracking(0.6)
                .foregroundStyle(YY.ink400)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 4)
        .overlay {
            Capsule().strokeBorder(YY.ink300, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .transition(.opacity)
    }

    // MARK: -

    private func openSearch() {
        mode = .search
    }

    private func finishContact() {
        nameFocused = false
        mode = .idle
        onCommitName()
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

/// 呼吸的小圆点（离线条用）
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
