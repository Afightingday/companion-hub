import SwiftUI

enum ChatMode: Equatable {
    case idle, search, select, contact
}

/// 顶栏浮在纸面上，本身不带底色。
/// 三副长相原位互换：常态 / 会话内搜索 / 多选；改备注时名字就地长成输入框。
struct ChatHeaderBar: View {
    @Binding var mode: ChatMode
    @Binding var name: String
    @Binding var query: String
    let offline: Bool
    let hitLabel: String
    let pickedCount: Int
    var onBack: () -> Void
    var onCommitName: () -> Void
    var onChangeAvatar: () -> Void
    var onPrevHit: () -> Void
    var onNextHit: () -> Void

    @FocusState private var nameFocused: Bool
    @FocusState private var queryFocused: Bool

    private var isContact: Bool { mode == .contact }

    var body: some View {
        VStack(spacing: 9) {
            switch mode {
            case .idle, .contact: normalBar
            case .search: searchBar
            case .select: selectBar
            }
            if offline { offlinePill }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .animation(.sceneHover(0.28), value: mode)
        .animation(.sceneStandard(0.3), value: offline)
    }

    // MARK: - 常态 / 改备注

    private var normalBar: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YY.ink600)
                    .frame(width: 36, height: 36)
                    .yyGlassPill(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            HStack(spacing: 11) {
                avatar
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(YY.ink800)
                    .tint(YY.sage500)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .disabled(!isContact)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { finishContact() }
                    .padding(.horizontal, isContact ? 13 : 0)
                    .frame(minHeight: 32)
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
            .padding(isContact ? 6.8 : 5.5)
            .frame(width: isContact ? 52 : 42, height: isContact ? 52 : 42)
            .background(YY.sage100, in: Circle())
            .overlay { Circle().strokeBorder(YY.borderHair, lineWidth: 1) }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.55))
                    .frame(width: 20, height: 20)
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
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(YY.ink600)
                    .frame(width: isContact ? 0 : 17)
                    .opacity(isContact ? 0 : 1)
                    .clipped()
                if isContact {
                    Text("完成")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(YY.sage600)
                }
            }
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, isContact ? 15 : 0)
            .yyGlassPill(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isContact ? "完成" : "搜索")
    }

    // MARK: - 会话内搜索

    private var searchBar: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(YY.searchFieldInk)
                    TextField("搜索这个对话", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundStyle(YY.ink800)
                        .tint(YY.sage600)
                        .focused($queryFocused)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(
                                    Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(YY.searchFieldFill, in: RoundedRectangle(cornerRadius: YY.rSM, style: .continuous))

                Button {
                    query = ""
                    mode = .idle
                } label: {
                    Text("取消")
                        .font(.system(size: 16))
                        .foregroundStyle(YY.sage600)
                }
                .buttonStyle(.plain)
            }

            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 6) {
                    Text(hitLabel)
                        .font(.yyMono(10.5))
                        .tracking(0.63)
                        .foregroundStyle(YY.ink400)
                    Rectangle()
                        .fill(.clear)
                        .frame(height: 1)
                        .overlay {
                            GeometryReader { proxy in
                                Path { p in
                                    p.move(to: CGPoint(x: 0, y: 0.5))
                                    p.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
                                }
                                .stroke(YY.borderDash, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            }
                        }
                        .opacity(0.7)
                    hitStepper("chevron.up", action: onPrevHit)
                    hitStepper("chevron.down", action: onNextHit)
                }
                .padding(.horizontal, 2)
                .transition(.opacity)
            }
        }
        .onAppear { queryFocused = true }
    }

    private func hitStepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(YY.ink400)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 多选

    private var selectBar: some View {
        HStack {
            Button { mode = .idle } label: {
                Text("取消")
                    .font(.system(size: 16))
                    .foregroundStyle(YY.sage600)
            }
            .buttonStyle(.plain)

            Text(pickedCount > 0 ? "已选 \(pickedCount) 条" : "选择消息")
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(YY.ink700)
                .frame(maxWidth: .infinity)

            Color.clear.frame(width: 32, height: 1)
        }
        .frame(height: 34)
    }

    // MARK: - 离线

    private var offlinePill: some View {
        HStack(spacing: 6) {
            ChatPulseDot()
            Text("网络已断开")
                .font(.yyMono(10))
                .tracking(0.6)
                .foregroundStyle(YY.ink400)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 3)
        .overlay {
            Capsule().strokeBorder(YY.ink300, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .transition(.opacity)
    }

    // MARK: -

    private func openSearch() {
        query = ""
        mode = .search
    }

    private func finishContact() {
        nameFocused = false
        mode = .idle
        onCommitName()
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
