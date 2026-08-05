import SwiftUI
import UIKit
import YushiKit

/// 单 Agent 会话页 —— 对位设计稿「Agent 对话页 v2」。
///
/// 三条骨架：
/// 1. 顶栏与输入胶囊都**浮**在纸上（下面不垫衬底），玻璃走系统原生液态玻璃；
/// 2. 消息不进容器 —— 你的话一圈虚线，祐识那边的话直接落在纸上；
/// 3. 时间不占版面：滚动时浮一枚**整点**胶囊，没有左拖露时间那套。
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

    // 多选
    @State private var picked: Set<String> = []
    @State private var confirmDeleteMany = false
    @State private var pendingDelete: String?
    @State private var pendingRetry: UiMessage?
    @State private var shareText: String?

    // 搜索
    @State private var query = ""
    @State private var hits: [String] = []
    @State private var hitIndex = 0
    @State private var searchTask: Task<Void, Never>?

    // 版面
    @State private var headerHeight: CGFloat = 108
    @State private var dockHeight: CGFloat = 76
    @State private var scrollPos = ScrollPosition(edge: .bottom)
    @State private var timeLabel = ""
    @State private var timeVisible = false
    @State private var timeTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var versionIndex: [String: Int] = [:]
    @State private var highlighted: String?
    /// 当前 hosting 树已经提供的底部 inset（含键盘变化）。ChatChrome 只补差值，
    /// 不能再把完整键盘高度叠上来。
    @State private var systemBottomInset: CGFloat = 0
    /// 整点锚存在一个普通对象里，**不是 @State 值**——
    /// 滚动时 y 每帧都在变，写进 @State 会每帧重建 body，白烧一整页的布局。
    @State private var timeAnchors = ChatTimeAnchors()
    /// 窗口级静态安全区与键盘遮挡。宿主已经给出的动态 bottom inset 在本页另行实量，
    /// 两者只补差值（见 ChatChrome）。
    @State private var chrome = ChatChrome()

    private let seeds = ["明早提醒我去河边", "这周我都干了什么", "把妈妈的腌菜方子记下来"]

    var body: some View {
        ZStack(alignment: .top) {
            ChatBackdrop()

            thread
                .overlay(alignment: .top) {
                    ChatTimePill(label: timeLabel, visible: timeVisible && mode != .select)
                        .padding(.top, max(0, headerHeight - 34))
                }

            ChatHeaderBar(
                mode: $mode,
                name: $name,
                offline: !network.isOnline,
                pickedCount: picked.count,
                safeTop: chrome.safeTop,
                onBack: { if let onBack { onBack() } else { dismiss() } },
                onCommitName: commitName,
                onChangeAvatar: { flash("头像换图还没接上") }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }

            if let toast {
                ChatToast(text: toast)
                    .padding(.top, headerHeight + 8)
            }
        }
        // 输入胶囊悬浮在卷轴之上 —— 走 overlay 而不是 safeAreaInset，
        // 才不会在底下垫出一条实色衬底。
        // 宿主会给一部分键盘避让，具体多少由这里实量；底栏只补剩余差值。
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: {
            systemBottomInset = max(0, $0)
        }
        .overlay(alignment: .bottom) { bottomBar(systemBottomInset: systemBottomInset) }
        .background(YY.page)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.sceneStandard(0.24), value: toast)
        .onAppear { chrome.start() }
        .onDisappear { chrome.stop() }
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
            if value != .search { hits = []; hitIndex = 0 }
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
        .confirmationDialog(
            "重新回答这条问题？",
            isPresented: Binding(get: { pendingRetry != nil }, set: { if !$0 { pendingRetry = nil } }),
            titleVisibility: .visible
        ) {
            Button("重新回答") {
                guard let message = pendingRetry else { return }
                pendingRetry = nil
                Task {
                    guard let session else { return }
                    if await session.retry(assistantId: message.id) {
                        versionIndex[message.id] = nil
                    } else {
                        flash("重答没有继续，已按服务器记录重新载入")
                    }
                }
            }
            Button("取消", role: .cancel) { pendingRetry = nil }
        } message: {
            Text("当前回答会被替换；取消不会改动对话。")
        }
        .sheet(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) {
            if let shareText {
                ChatShareSheet(text: shareText)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - 卷轴

    private var thread: some View {
        GeometryReader { viewport in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 25) {
                    if let session {
                        if session.isEmpty {
                            ChatEmptyState(seeds: seeds) { seed in
                                draft = seed
                                sendDraft()
                            }
                            .padding(.top, 60)
                        } else {
                            if !session.reachedTop {
                                ChatLoadMoreRow()
                                    .onAppear { Task { await session.loadMore() } }
                            }
                            if let error = session.loadError {
                                ChatLoadErrorRow(text: error) { Task { await session.load() } }
                            }
                            ForEach(session.rows) { row in
                                rowView(row, session: session)
                                    .id(row.id)
                            }
                        }
                    }
                }
                // 竖轴 ScrollView 仍可能被超宽子项撑大内容列；明确钉住列宽，
                // 让 trace/审批卡的绘制越界不能把整列居中推到 x=-16。
                .frame(width: max(0, viewport.size.width - 32), alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, headerHeight)
                // 最后一条要能翻到悬浮胶囊上方
                .padding(.bottom, dockHeight + 16)
                .scrollTargetLayout()
            }
            .scrollPosition($scrollPos)
            .scrollDismissesKeyboard(.interactively)
            .mask {
                // 正文到实际顶栏底缘才重新显现，不再穿过名字和按钮。
                GeometryReader { proxy in
                    let h = max(proxy.size.height, 1)
                    let revealStart = min(0.48, max(0, headerHeight - 24) / h)
                    let revealEnd = min(0.52, max(headerHeight, 1) / h)
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: revealStart),
                            .init(color: .black, location: revealEnd),
                            .init(color: .black, location: max(0.6, 1 - 22 / h)),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            // 这个回调每帧都响；只做一次 8pt 阈值比较，避免每帧重建 body。
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                guard abs(y - timeAnchors.lastOffset) > 8 else { return }
                timeAnchors.lastOffset = y
                refreshTimeLabel()
            }
            .onScrollPhaseChange { _, phase in
                if phase == .idle {
                    scheduleHideTimePill()
                } else {
                    showTimePill()
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
        }
    }

    // MARK: - 底部悬浮：输入胶囊 / 搜索条 / 多选工具条

    private func bottomBar(systemBottomInset: CGFloat) -> some View {
        Group {
            switch mode {
            case .select:
                ChatSelectionBar(
                    count: picked.count,
                    onShare: shareSelected,
                    onDelete: { confirmDeleteMany = true }
                )
            case .search:
                ChatSearchDock(
                    query: $query,
                    hitLabel: hitLabel,
                    onPrev: { stepHit(-1) },
                    onNext: { stepHit(1) },
                    onClose: { mode = .idle }
                )
                .padding(.horizontal, 4)
            case .idle, .contact:
                ChatComposer(
                    draft: $draft,
                    chip: $chip,
                    streaming: session?.isStreaming ?? false,
                    offline: !network.isOnline,
                    onSend: sendDraft,
                    onStop: { Task { await session?.abort() } },
                    onAttachmentPicked: { flash("附件通道还没接上，这次只寄出了文字") }
                )
                .padding(.horizontal, 12)
            }
        }
        // 只补系统没有给的那一段，避免完整键盘高度叠两次。
        .padding(.bottom, chrome.supplementalBottomInset(systemBottomInset: systemBottomInset) + 8)
        .animation(.sceneHover(0.28), value: mode)
        // 卷轴按这个高度留出底部余量，最后一条才不会藏在胶囊底下
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dockHeight = $0 }
    }

    // MARK: - 动作

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !(session?.isStreaming ?? false) else { return }
        let replyTo = chip?.kind == .quote ? chip?.replyTo : nil
        draft = ""
        chip = nil
        Haptic.softTap()
        scrollPos.scrollTo(edge: .bottom)
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
        pendingRetry = message
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

    private var hitLabel: String {
        hits.isEmpty ? "0 条" : "\(hitIndex + 1)/\(hits.count) 条"
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let q = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { hits = []; hitIndex = 0; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let session else { return }
            let found = await session.search(q)
            guard !Task.isCancelled else { return }
            hits = found
            hitIndex = 0
            if let first = found.first { await jump(to: first) }
        }
    }

    private func stepHit(_ delta: Int) {
        guard !hits.isEmpty else { return }
        hitIndex = (hitIndex + delta + hits.count) % hits.count
        let target = hits[hitIndex]
        Task { await jump(to: target) }
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

    /// 视口顶部当前落在哪个整点：取仍在顶栏之上的最后一个时间锚
    private var visibleTimeLabel: String {
        let threshold = headerHeight + 12
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
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(YY.ink400)
                .multilineTextAlignment(.center)
            Button("再试一次", action: onRetry)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(YY.sage700)
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
