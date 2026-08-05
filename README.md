# 祐识 · iOS（SwiftUI）

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
- [x] 第 1.5 批：会话总览页原生化（设计稿 2026-08-01 收官版 1:1 移植）——
      窗边手账工作室场景 / 三只 pet（随机站位·拖拽·三连跳·专属贴纸）/
      撕拉拍立得速览卡（掀膜走原生 `UIPageViewController(.pageCurl)`，B6）/
      陀螺仪视差（CoreMotion，B5）/ 全局音效首版（B12，`tools/gen-assets.mjs` 程序化合成）
- [x] 第 2 批（2026-08-02）：聊天核心 —— 发送（乐观气泡）+ SSE 流式（TurnEventEnvelope 信封 +
      Last-Event-ID 续流 + 掉线重连 + gone 回落拉历史）+ 事件归约器（Core/ChatReducer，
      对位 web applyEvent.ts）+ 思考/工具 TraceLine 行 + 审批纸卡 + 停止生成 + 行内 Markdown。
      同批网关侧：Codex adapter 迁 app-server v2（0.145.0 真机校准，thread 持久化进 KV）；
      Claude 底稿/补丁填实（tidal-echo 素材库改写）。信封动效后续批次打磨
- [x] 全量 Markdown（2026-08-05）：正文换成 SwiftStreamingMarkdown ——
      边流边排、新词淡入、代码块 / 列表 / 表格 / LaTeX 一并有了。
      原来「流式期间露原始星号、写完那一刻一次性排版」的跳版就此消失
- [ ] 第 3 批：群聊（说话人多路复用）
- [ ] 第 4 批：食帖 / 留声（快捷指令播放）/ 光阴瓶 / 各类表单
- [ ] 第 5 批：本地通知 / EventKit / 手感打磨

## 第三方依赖

- [`microsoft/SwiftStreamingMarkdown`](https://github.com/microsoft/SwiftStreamingMarkdown)
  `5f7c04e`（= tag v0.7.0，MIT）—— 会话页正文的流式 Markdown 渲染内核。选它是因为流式排版真正难的
  两件事都不是祐识特有的：**只对新追加的那段逐词淡入**（UITextView + CADisplayLink），
  以及**把吐到一半的 `**加粗` 投机重写成粗体**，好让下一个 token 到达时不整段重排。
  按 CLAUDE.md 第 0 条借内核、不自研。**钉的是提交哈希不是版本号**——它自己把
  `highlightswift` / `iosMath` 钉在裸提交上，SPM 不许「按版本号引用的包」再依赖
  「按提交引用的包」，写 `exactVersion` 解不出依赖图。升级＝人看过 diff 再换哈希。
  它带进来的传递依赖：`swift-markdown`(cmark-gfm)、`HighlightSwift`、`iosMath`、
  `SwiftUI-Shimmer`、`ordo-one/equatable`（Swift 宏，故 CI 编译带 `-skipMacroValidation`）。
  纸面配色在 `App/Views/Chat/ChatMarkdown.swift` 里一次性配好，不散落各处。

## 第三方资产

- 字体 `App/Media/fonts/LXGWWenKaiScreen.ttf`（霞鹜文楷屏幕阅读版）：
  SIL OFL 1.1 授权，许可证随包（同目录 `OFL-LICENSE.txt`）
- `App/Media/{art,assets}/` 内 PNG 均为祐祐验收定稿件，
  与设计稿仓 `sandbox/youshi-home/public/` 逐字节同源；音效与纸纹由
  `node tools/gen-assets.mjs` 确定性生成，可复现

## 约定

- **最低 iOS 26**：全量拥抱 Liquid Glass（`.glassEffect()` / `GlassEffectContainer` 等），不写 17–25 的 availability 兼容分支——唯一用户自装（iPhone 16 Pro Max），没有兼容负担
- bundle id 固定 `app.yushi.ios`（免费 Apple ID 的 App ID 名额只占 1 个）
- 事件模型与网关侧 schema 互为镜像：未知事件包成 raw 透传，不丢弃、不抹平
- CI 安全基线：GITHUB_TOKEN 只读；不使用 pull_request_target；外来 PR 首次运行需人工批准
