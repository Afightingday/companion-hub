import SwiftUI
import YushiKit

/// 会话总览页（云笺首页）：窗边手账工作室 + 三只 pet。
/// 1:1 移植 sandbox/youshi-home（2026-08-01 收官版）：
/// 房间 v3 母版单张直出 + 定稿微调（饱和 0.88/明度 0.98）、
/// 随机站位、拖拽摆放、未读三连跳 + 专属贴纸、撕拉拍立得速览卡、
/// 纸鹤+航迹+Youyou logo 前景（DECO 定稿 JSON）、搜索纸签、墨水瓶羽毛笔。
/// 原生化差异：底栏走系统 TabView；掀膜走 .pageCurl（B6）；
/// 视差由指针改陀螺仪（B5）；全局音效为 B12 首版。
struct HomeSceneView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    // 每次冷启动随机站位（不固定驻地）
    @State private var positions = PetPlacement.randomPositions()
    @State private var contacts: [PetKey: ContactListItem] = [:]
    /// 网关拉到过数据（决定未读/摘要用真数据还是设计稿兜底值）
    @State private var connected = false
    /// 进过门就放下信笺（服务端已读由 ChatView 标，刷新成功后清）
    @State private var readLocally: Set<PetKey> = []

    @State private var openPet: PetKey?
    @State private var chatPet: PetKey?
    @State private var dragPet: PetKey?

    @State private var parallax = MotionParallax()
    /// 滴墨声画同步的节拍器（onChange 里取到的才是新鲜状态）
    @State private var inkTick = 0

    /// 场景有事（开卡/拖拽），周边组件退淡让位
    private var quiet: Bool { openPet != nil || dragPet != nil }

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / SceneTokens.designW, geo.size.height / SceneTokens.designH)
            canvas
                .frame(width: SceneTokens.designW, height: SceneTokens.designH)
                .scaleEffect(k) // 目标机 iPhone 16 Pro Max 上 k=1
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .toolbar(openPet != nil ? .hidden : .visible, for: .tabBar)
        .fullScreenCover(item: $chatPet, onDismiss: { Task { await refresh() } }) { key in
            let spec = PET_SPECS.first { $0.key == key } ?? PET_SPECS[0]
            ChatSheetView(spec: spec, contact: contacts[key]) { chatPet = nil }
        }
        .onAppear { parallax.start() }
        .onDisappear { parallax.stop() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                parallax.stop()
                parallax.start() // 回前台以当前握持姿态重新归零
                Task { await refresh() }
            } else {
                parallax.stop()
            }
        }
        .onChange(of: inkTick) {
            if !quiet && openPet == nil { SoundPlayer.shared.play(.inkDrop) }
        }
        .task { await pollLoop() }
        .task { await inkMetronome() }
    }

    // MARK: - 440×956 设计画布

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            // ── 房间母版单张直出（±28 视差余量），只染背景不动 pet ──
            // 余量层必须再套一层 440×956 frame 封住布局足迹：否则 ZStack 取
            // 子视图联合尺寸被撑到 496×1012，整景居中裁切左上偏 28pt
            //（2026-08-01 真机实证：搜索钮切半、墨水瓶偏中央、四边出血）
            SceneAsset.image("assets/room-master.png")
                .resizable()
                .scaledToFill()
                .frame(width: SceneTokens.designW + 56, height: SceneTokens.designH + 56)
                .saturation(0.88)
                .colorMultiply(Color(white: 0.98))
                .offset(x: parallax.parX * -6, y: parallax.parY * -4)
                .frame(width: SceneTokens.designW, height: SceneTokens.designH)
                .allowsHitTesting(false)

            // ── mid：主人的 Youyou 手写 logo（DECO 定稿：22/87/123）──
            SceneAsset.image("assets/deco/logo-en.png")
                .resizable()
                .scaledToFit()
                .frame(width: 123)
                .offset(x: 22 + parallax.parX * -14, y: 87 + parallax.parY * -10)
                .allowsHitTesting(false)

            // ── pets：上远下近，拖拽中的压最上 ──
            ZStack(alignment: .topLeading) {
                ForEach(PET_SPECS) { spec in
                    let pos = positions[spec.key] ?? CGPoint(x: 220, y: 600)
                    ScenePetView(
                        spec: spec,
                        pos: pos,
                        unread: unread(for: spec),
                        dimmed: openPet != nil && openPet != spec.key,
                        active: openPet == spec.key,
                        onMove: { positions[spec.key] = $0 },
                        onDragState: { dragging in
                            dragPet = dragging ? spec.key : (dragPet == spec.key ? nil : dragPet)
                        },
                        onTap: {
                            openPet = spec.key
                            SoundPlayer.shared.play(.cardOpen)
                            Haptic.softTap()
                        })
                        .zIndex(dragPet == spec.key ? 30 : 1 + (pos.y / 40).rounded())
                }
            }
            .frame(width: SceneTokens.designW, height: SceneTokens.designH, alignment: .topLeading)

            // ── front：纸鹤 + 虚线航迹爱心，压在 pet 之上（DECO 定稿）──
            frontDeco
                .allowsHitTesting(false)

            // ── 纸纹 ──
            SceneAsset.image("assets/grain.png")
                .resizable(resizingMode: .tile)
                .frame(width: SceneTokens.designW, height: SceneTokens.designH)
                .opacity(0.05)
                .blendMode(.softLight)
                .allowsHitTesting(false)

            // ── 手账外壳件 ──
            ZStack(alignment: .bottomLeading) {
                Color.clear
                SearchNoteView(quiet: quiet)
                    .padding(.leading, 14)
                    .padding(.bottom, 122)
            }
            ZStack(alignment: .topLeading) {
                Color.clear
                QuillWellView(quiet: quiet)
                    .offset(x: SceneTokens.designW - 12 - 92, y: 705)
            }

            // ── 速览卡（模态：遮罩罩住一切，先点哪都是收卡）──
            if let key = openPet, let spec = PET_SPECS.first(where: { $0.key == key }) {
                QuickCardOverlay(
                    spec: spec,
                    petPos: positions[key] ?? CGPoint(x: 220, y: 600),
                    preview: preview(for: spec),
                    time: time(for: spec),
                    onClose: {
                        openPet = nil
                        SoundPlayer.shared.play(.cardClose)
                    },
                    onEnter: {
                        readLocally.insert(key) // 读过了，信笺就该放下
                        chatPet = key
                        openPet = nil
                        SoundPlayer.shared.play(.enterChat)
                    })
            }
        }
        .frame(width: SceneTokens.designW, height: SceneTokens.designH)
        .background(SceneTokens.paperPage)
        .clipped()
        .coordinateSpace(name: "scene")
    }

    private var frontDeco: some View {
        TimelineView(.animation) { timeline in
            let float = SceneWave.pingPong(timeline.date, period: 7)
            ZStack(alignment: .bottomLeading) {
                Color.clear
                // 航迹：镜像 = 心贴左缘、圈在右端接鹤（tx -3 / ty 172 / tw 84）
                SceneAsset.image("assets/deco/dashed-loop.png")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84)
                    .rotationEffect(.degrees(4))
                    .scaleEffect(x: -1)
                    .opacity(0.92)
                    .padding(.bottom, 172)
                    .offset(x: -3)

                // 纸鹤：轻浮沉，像被气流托着（cx 66 / cy 147 / cw 75）
                SceneAsset.image("assets/deco/crane.png")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 75)
                    .rotationEffect(.degrees(-7.5 + 3 * float))
                    .shadow(color: SceneTokens.shadowInk.opacity(0.16), radius: 4.5, y: 5)
                    .padding(.bottom, 147)
                    .offset(x: 66, y: -4 * float)
            }
            .frame(width: SceneTokens.designW, height: SceneTokens.designH, alignment: .bottomLeading)
            .offset(x: parallax.parX * 10, y: parallax.parY * 8)
        }
    }

    // MARK: - 数据：网关真数据优先，设计稿兜底值垫底

    private func unread(for spec: PetSpec) -> Int {
        if readLocally.contains(spec.key) { return 0 }
        if connected { return contacts[spec.key]?.unreadCount ?? 0 }
        return spec.unreadFallback
    }

    private func preview(for spec: PetSpec) -> String {
        contacts[spec.key]?.lastMessage?.text ?? spec.previewFallback
    }

    private func time(for spec: PetSpec) -> String {
        if let sentAt = contacts[spec.key]?.lastMessage?.sentAt {
            let shown = PaperFormat.shortTime(sentAt)
            if !shown.isEmpty { return shown }
        }
        return spec.timeFallback
    }

    @MainActor
    private func refresh() async {
        guard let client = appModel.client else { return }
        do {
            let items = try await client.listContacts()
            contacts = PetContactMatch.map(items)
            connected = true
            readLocally.removeAll() // 服务端口径回来了，本地补丁退位
        } catch {
            // 拉不到就保持上一份（或兜底值），页面不空
        }
    }

    private func pollLoop() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(45))
            await refresh()
        }
    }

    /// 与 QuillWellView 的滴墨动画同一时间基（参考纪元 mod 6s），
    /// 在 90% 触墨面时刻打点，onChange 侧取新鲜 quiet 决定响不响
    private func inkMetronome() async {
        while !Task.isCancelled {
            let t = Date().timeIntervalSinceReferenceDate
            let phase = t.truncatingRemainder(dividingBy: QuillWellView.dropPeriod)
            let hitAt = QuillWellView.dropPeriod * QuillWellView.dropHitPhase
            var wait = hitAt - phase
            if wait <= 0.05 { wait += QuillWellView.dropPeriod }
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            inkTick += 1
        }
    }
}
