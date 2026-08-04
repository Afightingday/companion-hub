import SwiftUI
import UIKit
import YushiKit

/// 单 Agent 会话页 —— 对位设计稿「Agent 对话页 v2」。
///
/// 三条骨架：
/// 1. 顶栏浮在纸上、不带底色，常态 / 搜索 / 多选三副长相原位互换；
/// 2. 消息不进容器 —— 你的话一圈虚线，祐识那边的话直接落在纸上；
/// 3. 时间与日期都不占版面：日戳滚动时浮现，单条时间要左拖才露出来。
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
    @State private var shareText: String?

    // 搜索
    @State private var query = ""
    @State private var hits: [String] = []
    @State private var hitIndex = 0
    @State private var searchTask: Task<Void, Never>?

    // 版面
    @State private var headerHeight: CGFloat = 108
    @State private var scrollPos = ScrollPosition(edge: .bottom)
    @State private var dragX: CGFloat = 0
    @State private var dayLabel = ""
    @State private var dayVisible = false
    @State private var dayTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var versionIndex: [String: Int] = [:]
    @State private var highlighted: String?
    /// 日界锚点存在一个普通对象里，**不是 @State 值**——
    /// 滚动时 y 每帧都在变，写进 @State 会每帧重建 body，白烧一整页的布局。
    @State private var dayAnchors = ChatDayAnchors()

    private let seeds = ["明早提醒我去河边", "这周我都干了什么", "把妈妈的腌菜方子记下来"]

    var body: some View {
        ZStack(alignment: .top) {
            YY.page
                .ignoresSafeArea()
                .yyPaperGrain()
                .ignoresSafeArea()

            thread
                .overlay(alignment: .top) {
                    ChatDayPill(label: dayLabel, visible: dayVisible && mode == .idle)
                        .padding(.top, max(0, headerHeight - 30))
                }

            ChatHeaderBar(
                mode: $mode,
                name: $name,
                query: $query,
                offline: !network.isOnline,
                hitLabel: hitLabel,
                pickedCount: picked.count,
                onBack: { if let onBack { onBack() } else { dismiss() } },
                onCommitName: commitName,
                onChangeAvatar: { flash("头像换图还没接上") },
                onPrevHit: { stepHit(-1) },
                onNextHit: { stepHit(1) }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }

            if let toast {
                ChatToast(text: toast)
                    .padding(.top, headerHeight + 8)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .background(YY.page)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.sceneStandard(0.24), value: toast)
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
        .sheet(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) {
            if let shareText {
                ChatShareSheet(text: shareText)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - 卷轴

    private var thread: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
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
            .padding(.horizontal, 16)
            .padding(.top, headerHeight)
            .padding(.bottom, 10)
            .offset(x: -dragX)
            .animation(.linear(duration: 0.14), value: dragX)
            .scrollTargetLayout()
        }
        .scrollPosition($scrollPos)
        .scrollDismissesKeyboard(.interactively)
        .mask {
            // 顶端淡出：内容滑到顶栏底下时化掉，而不是被硬切。
            // 停止点必须按**绝对点数**算——用百分比的话，屏幕一高，
            // 淡出带就够不到顶栏底缘，正文会直接压在名字和搜索键上。
            GeometryReader { proxy in
                let h = max(proxy.size.height, 1)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: min(0.4, 34 / h)),
                        .init(color: .black, location: min(0.8, 70 / h)),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .simultaneousGesture(revealGesture)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, _ in
            pulseDayPill()
        }
    }

    @ViewBuilder
    private func rowView(_ row: ChatRow, session: ChatSession) -> some View {
        switch row.kind {
        case .dayMarker(let iso):
            // 日期不在流里占一行，只留一个零高的锚点喂给浮动胶囊
            Color.clear
                .frame(height: 0)
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .scrollView).minY
                } action: { y in
                    dayAnchors.items[row.id] = (y, ChatDayPill.label(for: iso))
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

    // MARK: - 底部：输入信笺 / 多选工具条

    @ViewBuilder
    private var bottomBar: some View {
        if mode == .select {
            ChatSelectionBar(
                count: picked.count,
                onShare: shareSelected,
                onDelete: { confirmDeleteMany = true }
            )
            .padding(.bottom, 8)
        } else if mode != .search {
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
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 左拖露时间

    private var revealGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard mode != .select else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragX = min(58, max(0, -value.translation.width - 4))
            }
            .onEnded { _ in dragX = 0 }
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
        versionIndex[message.id] = nil
        Task { await session.retry(assistantId: message.id) }
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

    // MARK: - 日戳与吐司

    /// 视口顶部当前落在哪一天：取仍在顶栏之上的最后一个日界锚点
    private var visibleDayLabel: String {
        let threshold = headerHeight + 12
        let all = dayAnchors.items.values
        if let nearest = all.filter({ $0.y <= threshold }).max(by: { $0.y < $1.y }) {
            return nearest.label
        }
        return all.min(by: { $0.y < $1.y })?.label ?? ""
    }

    private func pulseDayPill() {
        let label = visibleDayLabel
        guard !label.isEmpty else { return }
        if dayLabel != label { dayLabel = label }
        if !dayVisible { dayVisible = true }
        dayTask?.cancel()
        dayTask = Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            dayVisible = false
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

/// 日界锚点的容身处。刻意不是 @Observable：写它不该触发重绘。
final class ChatDayAnchors {
    var items: [String: (y: CGFloat, label: String)] = [:]
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
