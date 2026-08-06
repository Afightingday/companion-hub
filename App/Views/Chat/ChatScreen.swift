import SwiftUI
import UIKit
import YushiKit

/// 单 Agent 会话页。
///
/// **主张一：版面不由我算，由系统算。** 两条 bar 都走系统（导航栏 + `safeAreaInset`），
/// 键盘避让、卷轴内缩、栏内版式全归它。自绘的 `ChatChrome` / `ChatHeaderBar` 已删。
/// ⚠️ 边缘返回手势拿不到 —— 这一页是 `fullScreenCover` 盖上来的，栈里没有上一页可退。
///
/// **主张二（2026-08-05 祐祐定）：滚动走 anchor-to-top-on-send，不是 IM 的 stick-to-bottom。**
/// 发出去的那条顶到视口顶端，回答在它下面自然生长；**流式期间不做任何自动滚动**，
/// 手动滚动永远优先。上一版用 `.defaultScrollAnchor(.bottom, for: .sizeChanges)` 死盯底部，
/// 结果自己的话被顶到输入框底下看不见了，键盘一弹还会把卷轴锚到空白区（整屏内容消失）。
/// 那个修饰符已拆，**别再加回来**。
struct ChatScreen: View {
    let item: ContactListItem
    /// 宿主自己管返回时传进来（如首页的 fullScreenCover）；不传就退出当前呈现
    var onBack: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var network = NetworkMonitor.shared
    @State private var session: ChatSession?
    @State private var mode: ChatMode = .idle
    @State private var draft = ""
    @State private var chip: ChatComposerChip?
    @State private var name = ""

    /// 输入框焦点放在页级：收键盘这件事发生在输入条**之外**（点空白、下滑）
    @FocusState private var inputFocused: Bool
    /// 改备注时导航栏标题位那个输入框的焦点
    @FocusState private var nameFocused: Bool

    // 多选
    @State private var picked: Set<String> = []
    @State private var confirmDeleteMany = false
    @State private var pendingDelete: String?
    @State private var shareText: String?

    // 搜索
    @State private var query = ""
    @State private var hits: [ChatSearchHit] = []
    @State private var searched = false
    @State private var searchTask: Task<Void, Never>?

    // 卷轴
    @State private var scrollPos = ScrollPosition(edge: .bottom)
    /// anchor-to-top 的重申任务：布局要几帧才把尾部空白撑出来，一次 scrollTo 常常扑空
    @State private var pinTask: Task<Void, Never>?
    /// 被顶到视口顶端的那条自己的消息。它把卷轴切成「历史」和「本轮」两段，
    /// 尾部补一块动态空白，保证本轮还没生成内容时也有地方可顶。
    @State private var pinnedUserId: String?
    @State private var viewportHeight: CGFloat = 0
    /// 被钉那条的顶缘 y（.scrollView 坐标）
    @State private var pinY: CGFloat = 0
    /// **空白之前**的内容末端 y。空白高度按 `contentEndY - pinY` 算 ——
    /// 探针必须在空白**上方**，否则「空白撑高 → 末端下移 → 空白再撑高」直接布局回环。
    @State private var contentEndY: CGFloat = 0
    /// 真正的内容末端（含空白），只喂悬浮钮判断「到底了没」，不参与排版所以不怕回环。
    @State private var tailEndY: CGFloat = 0

    // 方向感知悬浮钮
    @State private var nub: ChatNub = .hidden
    @State private var nubAccum: CGFloat = 0
    @State private var nubLastY: CGFloat?

    // 浮层
    @State private var timeLabel = ""
    @State private var timeVisible = false
    @State private var timeTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var versionIndex: [String: Int] = [:]
    @State private var highlighted: String?
    /// 整点锚存在一个普通对象里，**不是 @State 值**——
    /// 滚动时 y 每帧都在变，写进 @State 会每帧重建 body，白烧一整页的布局。
    @State private var timeAnchors = ChatTimeAnchors()
    /// 安全区顶缘（＝导航栏底缘）的绝对 y。**只喂时间胶囊的门槛，不参与排版**。
    @State private var contentTop: CGFloat = 108

    private let seeds = ["明早提醒我去河边", "这周我都干了什么", "把妈妈的腌菜方子记下来"]

    var body: some View {
        NavigationStack {
            thread
                // 悬浮钮在 safeAreaInset **之前**挂：它的底缘＝输入条上沿。
                // 之前挂在 safeAreaInset 之后，底缘是屏幕底，钮直接压在输入条上（#1）。
                .overlay(alignment: .bottom) { nubButton }
                // 搜索覆层也只罩卷轴区，不碰底下的搜索条
                .overlay { searchVeil }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                .overlay(alignment: .top) { safeTopProbe }
                .overlay(alignment: .top) { floatingPills }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .task {
                    if session == nil {
                        let made = ChatSession(client: model.client, item: item)
                        session = made
                        name = item.contact.name
                        await made.load()
                        name = made.contact?.name ?? item.contact.name
                    }
                }
                .onChange(of: query) { _, value in scheduleSearch(value) }
                .onChange(of: mode) { _, value in
                    if value != .select { picked = [] }
                    if value == .search { query = "" }
                    if value != .search { hits = []; searched = false }
                }
                // 自己的话一落地就把它顶到视口顶端（temp id → 真 id 会变两次，都要跟）
                .onChange(of: session?.lastUserMessageId) { _, id in
                    guard let id else { return }
                    pinToTop(id)
                }
                // ── 破坏性操作交给系统原生动作单 ──
                .confirmationDialog(
                    "删除 \(picked.count) 条消息？删除后无法恢复。",
                    isPresented: $confirmDeleteMany,
                    titleVisibility: .visible
                ) {
                    Button("删除消息", role: .destructive) {
                        let ids = picked
                        Task {
                            await session?.delete(ids: ids)
                            picked = []
                            mode = .idle
                            flash("已删除")
                        }
                    }
                    Button("取消", role: .cancel) {}
                }
                .confirmationDialog(
                    "删除这条消息？删除后无法恢复。",
                    isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("删除消息", role: .destructive) {
                        guard let id = pendingDelete else { return }
                        pendingDelete = nil
                        Task {
                            await session?.delete(ids: [id])
                            flash("已删除")
                        }
                    }
                    Button("取消", role: .cancel) { pendingDelete = nil }
                }
                .sheet(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) {
                    if let shareText {
                        ChatShareSheet(text: shareText)
                            .ignoresSafeArea()
                    }
                }
        }
        // 壁纸挂在 NavigationStack **外面**：栈内任何一层都可能跟着键盘调安全区，
        // 挂外面拿到的是 cover 的整幅边界，键盘开合与它无关（#3 壁纸被顶走）。
        .background { ChatBackdrop() }
    }

    // MARK: - 系统导航栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if mode == .select {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { mode = .idle }
            }
            ToolbarItem(placement: .principal) {
                Text(picked.isEmpty ? "选择消息" : "已选 \(picked.count) 条")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YY.ink700)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: goBack) {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("返回")
            }
            ToolbarItem(placement: .principal) { principalItem }
            if mode == .contact {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成", action: finishRename)
                }
            }
        }
        // 搜索钮不在顶栏上了：往上翻历史时那枚方向感知悬浮钮会变成放大镜（见 nubButton）
    }

    @ViewBuilder
    private var principalItem: some View {
        if mode == .contact {
            // 就地变输入框 —— 不弹面板（祐祐 2026-08-05：「弹一张编辑面板就是不好不喜欢」）
            TextField("名字", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 18.5, weight: .semibold))
                .foregroundStyle(YY.ink800)
                .tint(YY.sage500)
                .lineLimit(1)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit(finishRename)
                .frame(minWidth: 150)
        } else {
            // 点一下弹一张贴着它的小卡片：原生 Menu 就是那个长相，不用自绘
            Menu {
                Button {
                    mode = .contact
                    DispatchQueue.main.async { nameFocused = true }
                } label: {
                    Label("改名字", systemImage: "pencil")
                }
                Button {
                    flash("头像换图还没接上")
                } label: {
                    Label("换头像", systemImage: "photo")
                }
            } label: {
                HStack(spacing: 9) {
                    avatarThumb
                    Text(name)
                        .font(.system(size: 18.5, weight: .semibold))
                        .foregroundStyle(YY.ink800)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .accessibilityLabel(name)
            .accessibilityHint("联系人操作")
        }
    }

    private var avatarThumb: some View {
        SceneAsset.image("assets/chat/seal-you.png")
            .resizable()
            .scaledToFit()
            .padding(5)
            .frame(width: 34, height: 34)
            .background(YY.sage100, in: Circle())
            .overlay { Circle().strokeBorder(YY.borderHair, lineWidth: 0.8) }
            .accessibilityHidden(true)
    }

    private func finishRename() {
        nameFocused = false
        mode = .idle
        commitName()
    }

    /// 退回首页。键盘还挂着第一响应者时同帧撤 cover，系统偶发把这次撤场吃掉
    /// （#7「第一下点了没反应」的样子）——先放焦点，下一循环再退，一次点击稳定生效。
    private func goBack() {
        let hadFocus = inputFocused || nameFocused
        inputFocused = false
        nameFocused = false
        if hadFocus {
            Task { @MainActor in
                await Task.yield()
                if let onBack { onBack() } else { dismiss() }
            }
        } else if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    // MARK: - 卷轴

    private var thread: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 25) {
                if let session {
                    if !session.loaded {
                        // 首屏快照没回来之前什么都不画 —— 纸面本身就是加载态。
                        // 在这儿画空态就是「进页先闪一下空态再冒出历史」（#13）。
                    } else if session.isEmpty {
                        ChatEmptyState(seeds: seeds) { seed in
                            draft = seed
                            sendDraft()
                        }
                        .padding(.vertical, 40)
                    } else {
                        if !session.reachedTop {
                            ChatLoadMoreRow()
                                .onAppear { Task { await session.loadMore() } }
                        }
                        if let error = session.loadError {
                            ChatLoadErrorRow(text: error) { Task { await session.load() } }
                        }
                        // 行必须是 scrollTargetLayout 的**直接子项**：包进嵌套 VStack 的话
                        // scrollTo(id:) 就找不着被钉的那条，anchor-to-top 直接失灵。
                        ForEach(session.rows) { row in
                            rowView(row, session: session).id(row.id)
                        }
                        // 空白之前的末端：给空白高度当被减数
                        Color.clear
                            .frame(height: 0)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.frame(in: .scrollView).minY
                            } action: { contentEndY = $0 }
                        // 动态空白：本轮内容还撑不满一屏时补足，好让自己那条能真的顶到顶。
                        // 回答一长就自己缩没，不会在底下留一块空地。
                        Color.clear.frame(height: bottomSpacer)
                        // 真末端：只判断「到底了没」，给悬浮钮用
                        Color.clear
                            .frame(height: 0)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.frame(in: .scrollView).minY
                            } action: { tailEndY = $0 }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            // 列宽钉死＝容器宽，**且必须 leading**。默认的 .center 在任何一个子项超宽时
            // 会把溢出往两边分，左边那截直接被推出屏幕＝「首字被切」（b29 真机复现）。
            // leading 之下溢出只往右跑，最坏是右边被截，绝不会吃掉开头。
            .containerRelativeFrame(.horizontal, alignment: .leading)
            .scrollTargetLayout()
        }
        .scrollPosition($scrollPos)
        // 只钉**首屏**落底。绝不要 .sizeChanges —— 那是 stick-to-bottom，
        // 会把自己刚发的话顶到输入框底下，键盘一弹还会锚到空白区。
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        // .immediately：手一滑就收（#4）。.interactively 要一路拖到键盘边缘才开始让，
        // 在聊天里等于「往下滑键盘纹丝不动」。
        .scrollDismissesKeyboard(.immediately)
        // 内容不足一屏时也要能拖，否则下滑收键盘的手势根本没得触发
        .scrollBounceBehavior(.always)
        // 只柔化顶缘：底下的输入条已经是厚磨砂，不用再叠一层实时模糊（省一半开销）
        .scrollEdgeEffectStyle(.soft, for: .top)
        // 点卷轴任意空白处收键盘。simultaneous 才不会把气泡的长按/点击一起吃掉。
        .simultaneousGesture(
            TapGesture().onEnded {
                if inputFocused { inputFocused = false }
            }
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        // 这个回调每帧都响；只做一次 8pt 阈值比较，避免每帧重建 body。
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            guard abs(y - timeAnchors.lastOffset) > 8 else { return }
            timeAnchors.lastOffset = y
            refreshTimeLabel()
            updateNub(offsetY: y)
        }
        .onScrollPhaseChange { _, phase in
            // 手动滚动永远优先：手指一搭上卷轴，锚顶重申立刻作废
            if phase == .tracking || phase == .interacting {
                pinTask?.cancel()
            }
            if phase == .idle {
                scheduleHideTimePill()
            } else {
                showTimePill()
            }
        }
    }

    // MARK: - anchor-to-top-on-send 的算术

    /// 本轮（自己那条起）到目前为止占了多高。两个 y 都在 .scrollView 坐标里，
    /// 差值与滚动位置无关，卷轴怎么动都不影响它。
    private var pinnedTailHeight: CGFloat { max(0, contentEndY - pinY) }

    /// 补到「刚好能把自己那条顶到顶」为止。回答越长，这块空白越小，长到超过一屏就没了。
    private var bottomSpacer: CGFloat {
        guard pinnedUserId != nil else { return 0 }
        return max(0, viewportHeight - pinnedTailHeight - 16)
    }

    /// 把这条自己的消息顶到视口顶端。先落 pin 让尾部空白撑起来，再滚 ——
    /// 同一帧里滚是滚不动的，那时还没有可供上顶的空间。
    ///
    /// **只滚一次常常扑空**（#8 真机「发出去不动」）：空白高度靠 onGeometryChange
    /// 两次回报才算得出来，几帧之内目标位置一直在变，太早的那次 scrollTo 白滚。
    /// 这里对同一目标重申三次（50/300/950ms），布局稳到哪次就哪次生效；
    /// 用户手指一搭上卷轴整个任务作废（onScrollPhaseChange 里取消）。
    private func pinToTop(_ id: String) {
        pinnedUserId = id
        pinTask?.cancel()
        pinTask = Task { @MainActor in
            for delay in [50, 250, 650] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .sceneOut(0.38)) {
                    scrollPos.scrollTo(id: id, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: ChatRow, session: ChatSession) -> some View {
        switch row.kind {
        case .timeMarker(let iso):
            // 时间不在流里占一行，只留一个零高的锚点喂给浮动胶囊
            Color.clear
                .frame(height: 0)
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .scrollView).minY
                } action: { y in
                    timeAnchors.items[row.id] = (y, ChatTimePill.label(for: iso))
                }
        case .message(let message):
            Group {
                if message.isUser {
                    ChatMessageRow(
                        message: message,
                        selecting: mode == .select,
                        picked: picked.contains(message.id),
                        dimmed: isDimmed(message.id),
                        onPick: { togglePick(message.id) },
                        onAction: { act($0, on: message) }
                    )
                } else {
                    ChatAgentTurn(
                        message: message,
                        selecting: mode == .select,
                        picked: picked.contains(message.id),
                        dimmed: isDimmed(message.id),
                        streaming: message.status == .streaming,
                        versionIndex: versionIndex[message.id] ?? (message.versionCount - 1),
                        onPick: { togglePick(message.id) },
                        onAction: { act($0, on: message) },
                        onRetry: { retry(message) },
                        onVersion: { versionIndex[message.id] = $0 },
                        onApproval: { id, decision in
                            Task { await session.decide(approvalId: id, decision: decision) }
                        }
                    )
                }
            }
            .padding(.vertical, highlighted == message.id ? 4 : 0)
            .background(
                highlighted == message.id ? YY.marker.opacity(0.5) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .animation(.sceneStandard(0.36), value: highlighted)
            .modifier(ChatPinAnchor(active: message.id == pinnedUserId) { pinY = $0 })
        }
    }

    // MARK: - 方向感知悬浮钮

    /// 键盘弹着（#3）或不在闲逛模式时整个收起；形状是**正圆**玻璃（#1 #10），
    /// 走首页搜索钮同款 `.buttonStyle(.glass)` + `.buttonBorderShape(.circle)`（真机已验的组合）。
    private var nubShown: Bool { nub != .hidden && !inputFocused && mode == .idle }

    /// 往上翻历史 → 放大镜；往下滑 → 回底箭头；贴近底部 → 收起。
    /// 换态只换图标不换容器，用 symbol replace 过渡。
    private var nubButton: some View {
        Button {
            Haptic.lightTap()
            switch nub {
            case .search:
                inputFocused = false
                mode = .search
            case .toBottom:
                withAnimation(reduceMotion ? nil : .sceneOut(0.35)) {
                    scrollPos.scrollTo(edge: .bottom)
                }
            case .hidden:
                break
            }
        } label: {
            Image(systemName: nub == .search ? "magnifyingglass" : "arrow.down")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(YY.ink600)
                .frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace.downUp))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .opacity(nubShown ? 1 : 0)
        .scaleEffect(nubShown ? 1 : 0.85)
        .allowsHitTesting(nubShown)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.8),
            value: nub
        )
        .animation(.sceneStandard(0.24), value: nubShown)
        .padding(.bottom, 12) // 距输入条上沿（overlay 挂在 safeAreaInset 之前，底缘就是输入条上沿）
        .accessibilityLabel(nub == .search ? "搜索这个对话" : "回到最新")
        .accessibilityHidden(!nubShown)
    }

    /// 方向反转要**累计**超过 24pt 才切换。少了这道防抖，手指微微一抖图标就来回跳。
    private func updateNub(offsetY y: CGFloat) {
        defer { nubLastY = y }
        guard let last = nubLastY else { return }
        let dy = y - last
        guard dy != 0 else { return }

        // 同向累加，反向清零重计
        nubAccum = (dy > 0) == (nubAccum > 0) ? nubAccum + dy : dy

        // 贴近底部就收起（末端探针落在视口下缘 40pt 以内）
        if tailEndY <= viewportHeight + 40 {
            if nub != .hidden { nub = .hidden }
            return
        }
        if nubAccum <= -24, nub != .search {
            nub = .search              // 往上翻历史
        } else if nubAccum >= 24, nub != .toBottom {
            nub = .toBottom            // 往下滑
        }
        // 停手不自动隐藏：这里不做任何 idle 复位（祐祐点名「防抖别省，停止滚动不自动隐藏」）
    }

    // MARK: - 栏下浮层

    /// 零高探针：量安全区顶缘（导航栏底缘）在屏幕上的位置，给时间胶囊当门槛。
    private var safeTopProbe: some View {
        Color.clear
            .frame(height: 0)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { contentTop = $0 }
            .allowsHitTesting(false)
    }

    /// 三枚浮丸。动画**只挂在这儿** —— 上一版把 `.animation(value:)` 挂在整页上，
    /// 一个吐司就把整棵 ScrollView 卷进隐式动画里，滚动能不钝么。
    private var floatingPills: some View {
        VStack(spacing: 7) {
            if !network.isOnline {
                ChatOfflinePill()
            }
            ZStack {
                ChatTimePill(label: timeLabel, visible: timeVisible && (mode == .idle || mode == .contact))
                if let toast {
                    ChatToast(text: toast)
                }
            }
        }
        .padding(.top, 8)
        .allowsHitTesting(false)
        .animation(.sceneStandard(0.24), value: toast)
        .animation(.sceneStandard(0.3), value: network.isOnline)
    }

    // MARK: - 底部：输入胶囊 / 搜索条 / 多选工具条

    private var bottomBar: some View {
        Group {
            switch mode {
            case .select:
                ChatSelectionBar(
                    count: picked.count,
                    onShare: shareSelected,
                    onDelete: { confirmDeleteMany = true }
                )
            case .search:
                // 照抄会话首页（#12）：底下只有一条苹果原生搜索栏，命中都在上面的玻璃卡里
                NativeSearchBar(text: $query, placeholder: "搜索这个对话", onCancel: { mode = .idle })
                    .frame(height: 52)
                    .padding(.horizontal, 4)
            case .idle, .contact:
                ChatComposer(
                    draft: $draft,
                    chip: $chip,
                    focused: $inputFocused,
                    streaming: session?.isStreaming ?? false,
                    offline: !network.isOnline,
                    onSend: sendDraft,
                    onStop: { Task { await session?.abort() } },
                    onAttachmentPicked: { flash("附件通道还没接上，这次只寄出了文字") }
                )
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 8)
        .animation(.sceneHover(0.28), value: mode)
    }

    // MARK: - 动作

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !(session?.isStreaming ?? false) else { return }
        let replyTo = chip?.kind == .quote ? chip?.replyTo : nil
        draft = ""
        chip = nil
        Haptic.softTap()
        // 不在这里滚：等消息真的落进表里，onChange(lastUserMessageId) 会把它顶上去
        Task { await session?.send(text, replyTo: replyTo) }
    }

    private func act(_ action: ChatMessageAction, on message: UiMessage) {
        switch action {
        case .copy:
            UIPasteboard.general.string = message.text
            flash("已拷贝")
        case .edit:
            draft = message.text
            chip = ChatComposerChip(kind: .edit, text: "编辑这条", replyTo: nil)
        case .quote:
            chip = ChatComposerChip(kind: .quote, text: message.text, replyTo: message.id)
        case .select:
            mode = .select
            picked = [message.id]
        case .delete:
            pendingDelete = message.id
        }
    }

    private func retry(_ message: UiMessage) {
        guard let session, !session.isStreaming else { return }
        versionIndex[message.id] = nil
        Task {
            if !(await session.retry(assistantId: message.id)) {
                flash("这次重答没有继续")
            }
        }
    }

    private func togglePick(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    private func isDimmed(_ id: String) -> Bool {
        mode == .select && !picked.isEmpty && !picked.contains(id)
    }

    private func shareSelected() {
        guard let session, !picked.isEmpty else { return }
        let who = session.contact?.name ?? item.contact.name
        shareText = session.messages
            .filter { picked.contains($0.id) }
            .map { ($0.isUser ? "我：" : "\(who)：") + $0.text }
            .joined(separator: "\n\n")
    }

    private func commitName() {
        Task { await session?.updateContact(name: name) }
    }

    // MARK: - 搜索

    /// 会话内搜索覆层（#12，照抄首页 SearchVeilView 的骨架）：
    /// 轻压暗 8%＋顶部清透玻璃结果卡；底部那条原生搜索栏走 bottomBar。
    /// 挂在 safeAreaInset 之前，所以只罩卷轴区，搜索栏和键盘都在它上面。
    @ViewBuilder
    private var searchVeil: some View {
        if mode == .search {
            ZStack(alignment: .top) {
                // 空白处点一下＝收起搜索（和首页一个手感）
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { mode = .idle }

                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ChatSearchResultsCard(hits: hits, searched: searched, onPick: openHit)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
        }
    }

    /// 点中一条命中：收帘，翻到那条并柔光高亮
    private func openHit(_ id: String) {
        Haptic.lightTap()
        mode = .idle
        Task { await jump(to: id) }
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let q = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { hits = []; searched = false; return }
        searched = false
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let session else { return }
            let found = await session.search(q)
            guard !Task.isCancelled else { return }
            hits = found
            searched = true
        }
    }

    /// 命中可能还没加载进来 —— 先往上翻到它，再滚过去并柔光高亮一下
    private func jump(to id: String) async {
        guard let session else { return }
        guard await session.revealMessage(id: id) else {
            flash("这条在更早的地方，还没翻到")
            return
        }
        withAnimation(.sceneGentle(0.4)) {
            scrollPos.scrollTo(id: id, anchor: .center)
        }
        highlighted = id
        try? await Task.sleep(for: .milliseconds(900))
        if highlighted == id { highlighted = nil }
    }

    // MARK: - 整点胶囊与吐司

    /// 视口顶部当前落在哪个整点：取仍在导航栏之上的最后一个时间锚
    private var visibleTimeLabel: String {
        let threshold = contentTop + 12
        let all = timeAnchors.items.values
        if let nearest = all.filter({ $0.y <= threshold }).max(by: { $0.y < $1.y }) {
            return nearest.label
        }
        return all.min(by: { $0.y < $1.y })?.label ?? ""
    }

    /// 只在字**真的变了**的时候写 @State。滚动中绝大多数帧都在这里空转返回。
    private func refreshTimeLabel() {
        let label = visibleTimeLabel
        guard !label.isEmpty, label != timeLabel else { return }
        timeLabel = label
    }

    private func showTimePill() {
        timeTask?.cancel()
        timeTask = nil
        refreshTimeLabel()
        if !timeVisible { timeVisible = true }
    }

    private func scheduleHideTimePill() {
        timeTask?.cancel()
        timeTask = Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            timeVisible = false
        }
    }

    private func flash(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task {
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}

/// 悬浮钮的三态
private enum ChatNub: Equatable {
    case hidden, search, toBottom
}

/// 只给**被钉住的那一条**装测量和顶端边距。
///
/// 为什么不是无脑装在所有行上：`onGeometryChange` 是每帧回调，装满全表就是每帧
/// 跑一遍所有行的几何 —— 那正是这次要治的掉帧。这里全程只有一行装着。
/// 16pt 的边距**进这一行自己的 frame**，`scrollTo(id:anchor:.top)` 才把它算进去，
/// 顶上去之后正文离视口顶缘正好留这么多。
private struct ChatPinAnchor: ViewModifier {
    let active: Bool
    let onY: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if active {
            content
                .padding(.top, 16)
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .scrollView).minY
                } action: { onY($0) }
        } else {
            content
        }
    }
}

/// 整点锚的容身处。刻意不是 @Observable：写它不该触发重绘。
final class ChatTimeAnchors {
    var items: [String: (y: CGFloat, label: String)] = [:]
    /// 上一次真正处理过的滚动位移，用来把每帧回调掐成每 8 点一次。
    /// 同样放这儿：它一帧变一次，进 @State 就等于每帧重建 body。
    var lastOffset: CGFloat = .infinity
}

// MARK: - 卷轴顶端的两个小行

private struct ChatLoadMoreRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
                .tint(YY.ink300)
            Spacer()
        }
        .frame(height: 34)
    }
}

private struct ChatLoadErrorRow: View {
    let text: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(YY.ink400)
                .multilineTextAlignment(.center)
            // 统一报错行（#14）：全会话页「坏了、可以再试」都是这张脸
            ChatErrorNote(text: "再试一次", tone: .muted, onTap: onRetry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

/// 分享：系统原生分享单
struct ChatShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
