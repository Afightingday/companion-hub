import SwiftUI
import YushiKit

/// 案头：网关连接设置（地址 + 令牌）。
/// 这是「公仓无密钥」的关键设计：地址与令牌都在运行时填，绝不进代码与 IPA。
struct AntouView: View {
    @Environment(AppModel.self) private var model
    @State private var testing = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    TextField("https://你的机器名.xxx.ts.net", text: $model.gatewayURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("访问令牌（网关 AUTH_TOKEN，可选）", text: $model.authToken)
                    Button {
                        Task {
                            testing = true
                            await model.testConnection()
                            testing = false
                        }
                    } label: {
                        if testing {
                            ProgressView()
                        } else {
                            Text("测试连接")
                        }
                    }
                    connectionRow
                } header: {
                    Text("网关")
                } footer: {
                    Text("地址即 Tailscale Serve 给出的 https://…ts.net。令牌只存本机钥匙串。聊天数据都在你的网关与云端，App 只是壳。")
                }

                Section("迁移进度") {
                    LabeledContent("这一批", value: "聊天核心：发送 · 流式 · 过程行 · 审批卡")
                    LabeledContent("第 3 批", value: "群聊")
                    LabeledContent("第 4 批", value: "食帖 · 留声")
                }

                Section("版本") {
                    LabeledContent("App", value: "0.2.0（第 2 批聊天核心）")
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperTheme.paperBg)
            .navigationTitle("案头")
        }
    }

    @ViewBuilder
    private var connectionRow: some View {
        switch model.connection {
        case .unknown:
            EmptyView()
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon")
                .font(.footnote)
                .foregroundStyle(PaperTheme.danger)
        case .ok(let health):
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "网关在线 · v\(health.version ?? "?") · 存储 \(health.store ?? "?")",
                    systemImage: "checkmark.seal"
                )
                .font(.footnote)
                .foregroundStyle(PaperTheme.matchaDeep)

                if let providers = health.providers {
                    ForEach(providers.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                        Text("\(entry.key)：\(stateLabel(entry.value.state))\(entry.value.detail.map { "（\($0)）" } ?? "")")
                            .font(.caption2)
                            .foregroundStyle(PaperTheme.inkMuted)
                    }
                }
                if let memoryd = health.memoryd {
                    Text("memoryd：\(stateLabel(memoryd.state))")
                        .font(.caption2)
                        .foregroundStyle(PaperTheme.inkMuted)
                }
            }
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "online": return "在线"
        case "offline": return "离线"
        case "not_configured": return "未配置"
        default: return state
        }
    }
}
