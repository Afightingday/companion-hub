# 雨施流形 · iOS（SwiftUI）

自建「AI 伙伴网关」的原生 iOS 客户端。App 本体不含任何服务与密钥：
网关地址与访问令牌在 App 内「案头」页**运行时**填写——地址进 UserDefaults，
令牌只进 iOS 钥匙串。仓库与构建产物里没有秘密，因此可以公开。

## 结构

```text
project.yml            XcodeGen 工程定义（Yushi.xcodeproj 由它生成，不入库）
Core/                  YushiKit：模型 / SSE 解析 / 网关客户端 —— 纯 Swift 零依赖，Linux 可测
App/                   SwiftUI 界面层（需 Xcode / macOS 编译）
.github/workflows/     CI：Linux 单测 + macOS 无签名 IPA
```

## 构建与安装

每次 push，CI 自动出 `yushi-unsigned-ipa` 产物（无签名 IPA），
用 SideStore / AltStore 类工具以自己的 Apple ID 自签安装。
本地有 Mac 时：

```bash
brew install xcodegen
xcodegen generate
open Yushi.xcodeproj   # 免费 Apple ID 选 Personal Team 即可真机安装（7 天有效）
```

核心包单测（任何平台，含 Linux）：

```bash
swift test --package-path Core
```

## 批次进度

- [x] 第 1 批：骨架 + 设计令牌 + GatewayClient + 云笺列表 + 只读聊天 + 案头连接设置
- [ ] 第 2 批：发送 + SSE 流式（Last-Event-ID 续流）+ 过程卡片（思考/工具/引用）+ 审批信封 + Markdown
- [ ] 第 3 批：群聊（说话人多路复用）
- [ ] 第 4 批：食帖 / 留声（快捷指令播放）/ 光阴瓶 / 各类表单
- [ ] 第 5 批：本地通知 / EventKit / 手感打磨

## 约定

- **最低 iOS 26**：全量拥抱 Liquid Glass（`.glassEffect()` / `GlassEffectContainer` 等），不写 17–25 的 availability 兼容分支——唯一用户自装（iPhone 16 Pro Max），没有兼容负担
- bundle id 固定 `app.yushi.ios`（免费 Apple ID 的 App ID 名额只占 1 个）
- 事件模型与网关侧 schema 互为镜像：未知事件包成 raw 透传，不丢弃、不抹平
- CI 安全基线：GITHUB_TOKEN 只读；不使用 pull_request_target；外来 PR 首次运行需人工批准
