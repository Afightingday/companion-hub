import SwiftUI
import UIKit
import YushiKit

/// 单 Agent 会话页。
///
/// **这一版的唯一主张：版面不由我算，由系统算。**
///
/// 上一版把顶栏和输入条挂在一个 `GeometryReader` 钉死尺寸的盒子上，
/// 那个盒子不会因为键盘变矮，于是输入条永远不动 —— 只好自己听键盘通知、
/// 自己量顶栏高度、自己扣宿主已经给过的那一段（`ChatChrome`，已删）。
/// 键盘通知给的是「最终停在哪 + 动画多久」，不是逐帧位置；手指拖着收键盘的
/// 那 300ms 里输入条收不到任何消息，只能等键盘走完再「啪」地落下。这就是「不丝滑」。
///
/// 现在：
/// - 顶栏＝**系统导航栏**（`NavigationStack` + `.toolbar`）。玻璃、栏高、栏内版式、
///   正文滚到栏下的柔化全归系统。自绘的 `ChatHeaderBar` 与那层保险丝渐隐一并删。
///   ⚠️ 边缘返回手势**拿不到** —— 这一页是 `fullScreenCover` 盖上来的，栈里没有上一页可退。
///   要拿手势得改首页怎么打开它，那是另一件事，别在这儿硬做。
/// - 输入条＝`safeAreaInset(edge:.bottom)`，键盘避让是系统的（`HomeSceneView` 的
///   fullScreenCover 宿主早已实证「键盘避让全系统」），`.scrollDismissesKeyboard(.interactively)`
///   才真的连续；卷轴的上下留白由 inset 自动内缩，不再需要量高度回填 padding。
///
/// 三条骨架不变：消息不进容器；时间只在滚动时浮一枚整点胶囊；破坏性操作走系统动作单。
struct ChatScreen: View {
    let item: ContactListItem
    /// 宿主自己管返回时传进来（如首页的 fullScreenCover）；不传就退出当前呈现
    var onBack: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

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

    // 搜索
    @State private var query = ""
    @State private var hits: [String] = []
    @State private var hitIndex = 0
    @State private var searchTask: Task<Void, Never>?

    /// 面板只留一个出口。两个 `.sheet` 挂同一个视图上是 SwiftUI 的老雷，
    /// 后挂的那个会被吞掉；统一成 `sheet(item:)` 就没这回事。
    @State private var sheet: ChatSheet?

    // 浮层
    @State private var scrollPos = ScrollPosition(edge: .bottom)
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
    /// 安全区顶缘（＝导航栏底缘）在屏幕上的绝对 y。
    /// **只喂时间胶囊的取值门槛，不参与任何排版** —— 排版全由导航栏和 safeAreaInset 决定，
    /// 所以它写进 @State 也不会引起版面回环。
    @State private var contentTop: CGFloat = 108

    private let seeds = ["明早提醒我去河边", "这周我都干了什么", "把妈妈的腌菜方子记下来"]

    var body: some View {
        NavigationStack {
            thread
                .background { ChatBackdrop() }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                // 探针与浮丸都挂在导航栏之后：它们看到的安全区已经含顶栏了，
                // 自动落在栏正下方，不用再拿量出来的高度去垫。
                .overlay(alignment: .top) { safeTopProbe }
                .overlay(alignment: .top) { floatingPills }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .animation(.sceneStandard(0.24), value: toast)
                .animation(.sceneStandard(0.3), value: network.isOnline)
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
                .sheet(item: $sheet) { which in
                    switch which {
                    case .share(let text):
                        ChatShareSheet(text: text)
                            .ignoresSafeArea()
                    case .rename:
                        ChatRenameSheet(
                            initialName: name,
                            onChangeAvatar: { flash("头像换图还没接上") },
                            onCommit: { newName in
                                name = newName
                                commitName()
                            }
                        )
                    }
                }
        }
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
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("返回")
            }
            ToolbarItem(placement: .principal) {
                Button { sheet = .rename } label: {
                    HStack(spacing: 8) {
                        avatarThumb
                        Text(name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(YY.ink800)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                // 栏内标题位不该长成一颗玻璃钮；这里只要可点，不要按钮外观。
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityHint("编辑联系人")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { mode = .search } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索")
            }
        }
    }

    private var avatarThumb: some View {
        SceneAsset.image("assets/chat/seal-you.png")
            .resizable()
            .scaledToFit()
            .padding(4)
            .frame(width: 28, height: 28)
            .background(YY.sage100, in: Circle())
            .overlay { Circle().strokeBorder(YY.borderHair, lineWidth: 0.8) }
            .accessibilityHidden(true)
    }

    // MARK: - 卷轴

    private var thread: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 25) {
                if let session {
                    if session.isEmpty {
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
                        ForEach(session.rows) { row in
                            rowView(row, session: session)
                                .id(row.id)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            // 列宽钉死＝容器宽。竖轴 ScrollView 仍可能被超宽子项撑大内容列，
            // 钉住之后 trace / 审批卡的绘制越界不能再把整列居中推到 x=-16。
            .containerRelativeFrame(.horizontal)
            .scrollTargetLayout()
        }
        .scrollPosition($scrollPos)
        // 首屏落底
        .defaultScrollAnchor(.bottom)
        // 内容尺寸变化时保住「离底的距离」：流式增长跟着走，往上翻历史时
        // 前置插入不再把正在看的地方顶跑（旧版翻页跳一下就是这儿缺的）。
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        // 正文穿过导航栏 / 输入条时的柔化交给系统，替掉旧版整页 .mask 的每帧离屏合成
        .scrollEdgeEffectStyle(.soft, for: .vertical)
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

    // MARK: - 栏下浮层

    /// 零高探针：量的是**安全区顶缘**（导航栏底缘）在屏幕上的位置，
    /// 给时间胶囊当取值门槛。挂在 overlay 里所以自带安全区，不用自己加导航栏高度。
    private var safeTopProbe: some View {
        Color.clear
            .frame(height: 0)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { contentTop = $0 }
            .allowsHitTesting(false)
    }

    private var floatingPills: some View {
        VStack(spacing: 7) {
            if !network.isOnline {
                ChatOfflinePill()
            }
            ZStack {
                ChatTimePill(label: timeLabel, visible: timeVisible && mode != .select)
                if let toast {
                    ChatToast(text: toast)
                }
            }
        }
        .padding(.top, 8)
        .allowsHitTesting(false)
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
                ChatSearchDock(
                    query: $query,
                    hitLabel: hitLabel,
                    onPrev: { stepHit(-1) },
                    onNext: { stepHit(1) },
                    onClose: { mode = .idle }
                )
                .padding(.horizontal, 4)
            case .idle:
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
        withAnimation(.sceneOut(0.3)) { scrollPos.scrollTo(edge: .bottom) }
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
                flash("重答没有继续，已按服务器记录重新载入")
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
        let text = session.messages
            .filter { picked.contains($0.id) }
            .map { ($0.isUser ? "我：" : "\(who)：") + $0.text }
            .joined(separator: "\n\n")
        sheet = .share(text)
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

/// 本页所有面板的唯一出口
private enum ChatSheet: Identifiable {
    case share(String)
    case rename

    var id: String {
        switch self {
        case .share: return "share"
        case .rename: return "rename"
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
