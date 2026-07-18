import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            YunjianView()
                .tabItem { Label("云笺", systemImage: "ellipsis.bubble") }
            ComingSoonView(title: "食帖", subtitle: "美食档案 · 第 4 批搬进来", systemImage: "fork.knife")
                .tabItem { Label("食帖", systemImage: "fork.knife") }
            ComingSoonView(title: "留声", subtitle: "歌词日志 · 第 4 批搬进来（含快捷指令播放）", systemImage: "music.note")
                .tabItem { Label("留声", systemImage: "music.note") }
            ComingSoonView(title: "光阴瓶", subtitle: "每日聚合 · 第 4 批搬进来", systemImage: "hourglass")
                .tabItem { Label("光阴瓶", systemImage: "hourglass") }
            AntouView()
                .tabItem { Label("案头", systemImage: "lamp.desk") }
        }
    }
}

/// 占位页：网页版仍可用，此处只标注迁移批次
struct ComingSoonView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ZStack {
                PaperTheme.paperBg.ignoresSafeArea()
                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                } description: {
                    Text(subtitle)
                        .foregroundStyle(PaperTheme.inkMuted)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 导航内的轻量占位（不带 NavigationStack）
struct ComingSoonPlain: View {
    let text: String

    var body: some View {
        ZStack {
            PaperTheme.paperBg.ignoresSafeArea()
            Text(text)
                .font(.footnote)
                .foregroundStyle(PaperTheme.inkMuted)
                .padding()
        }
    }
}
