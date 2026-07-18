import SwiftUI
import YushiKit

/// 云笺：联系人与小群列表（未读角标 + 最近一条）
struct YunjianView: View {
    @Environment(AppModel.self) private var model

    @State private var contacts: [ContactListItem] = []
    @State private var groups: [GroupListItem] = []
    @State private var loadError: String?
    @State private var loadedOnce = false

    var body: some View {
        NavigationStack {
            Group {
                if model.client == nil {
                    ContentUnavailableView {
                        Label("还没连上网关", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("去「案头」填网关地址（Tailscale 的 https://…ts.net），联系人就都回来了")
                            .foregroundStyle(PaperTheme.inkMuted)
                    }
                } else if let loadError, contacts.isEmpty, groups.isEmpty {
                    ContentUnavailableView {
                        Label("拉取失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError).foregroundStyle(PaperTheme.inkMuted)
                    } actions: {
                        Button("重试") { Task { await reload() } }
                    }
                } else {
                    conversationList
                }
            }
            .background(PaperTheme.paperBg)
            .navigationTitle("云笺")
            .task {
                if !loadedOnce { await reload() }
            }
            .refreshable { await reload() }
        }
    }

    private var conversationList: some View {
        List {
            if !groups.isEmpty {
                Section("小群") {
                    ForEach(groups) { item in
                        NavigationLink(value: Route.group(item)) {
                            GroupRow(item: item)
                        }
                        .listRowBackground(PaperTheme.paperCard)
                    }
                }
            }
            Section(groups.isEmpty ? "" : "联系人") {
                ForEach(contacts) { item in
                    NavigationLink(value: Route.contact(item)) {
                        ContactRow(item: item)
                    }
                    .listRowBackground(PaperTheme.paperCard)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .contact(let item):
                ChatView(item: item)
            case .group:
                ComingSoonPlain(text: "群聊在第 3 批迁进来（说话人多路复用）；先用网页版")
            }
        }
    }

    enum Route: Hashable {
        case contact(ContactListItem)
        case group(GroupListItem)
    }

    @MainActor
    private func reload() async {
        guard let client = model.client else { return }
        do {
            async let contactsTask = client.listContacts()
            async let groupsTask = client.listGroups()
            let (loadedContacts, loadedGroups) = try await (contactsTask, groupsTask)
            contacts = loadedContacts
            groups = loadedGroups
            loadError = nil
            loadedOnce = true
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - 行

struct AvatarView: View {
    let text: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(PaperTheme.matchaSoft)
            if text.hasPrefix("http"), let url = URL(string: text) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Text(text.isEmpty ? "🌱" : text)
                    .font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
    }
}

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : String(count))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(PaperTheme.matcha))
        }
    }
}

private struct ContactRow: View {
    let item: ContactListItem

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(text: item.contact.avatarUrl ?? "🌱")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.contact.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PaperTheme.ink)
                Text(item.lastMessage?.text ?? item.contact.signature ?? "…")
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.inkMuted)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let sentAt = item.lastMessage?.sentAt {
                    Text(PaperFormat.shortTime(sentAt))
                        .font(.caption2)
                        .foregroundStyle(PaperTheme.inkMuted)
                }
                UnreadBadge(count: item.unreadCount)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct GroupRow: View {
    let item: GroupListItem

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(text: "👥")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.conversation.title ?? "小群")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PaperTheme.ink)
                Text(item.lastMessage?.text ?? "\(item.memberIds.count) 位成员")
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.inkMuted)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let sentAt = item.lastMessage?.sentAt {
                    Text(PaperFormat.shortTime(sentAt))
                        .font(.caption2)
                        .foregroundStyle(PaperTheme.inkMuted)
                }
                UnreadBadge(count: item.unreadCount)
            }
        }
        .padding(.vertical, 2)
    }
}
