import SwiftUI

/// pet：手绘立绘（PNG 四态）+ 拖拽 + 深度缩放 —— 1:1 移植 src/components/Pet.tsx + pet.css。
/// 摆放坐标 = 脚底落点，立绘以底边中点锚定；y 越小（越远）体量越小。
/// 有未读：不出数字角标——小人隔一阵三连跳（28/25/22 定稿），
/// 周身按祐祐拼版散布专属贴纸，放缩+闪烁。
struct ScenePetView: View {
    let spec: PetSpec
    let pos: CGPoint
    let unread: Int
    let dimmed: Bool
    /// 速览卡开着的是不是这只：开着就换开心脸
    let active: Bool
    var onMove: (CGPoint) -> Void
    var onDragState: (Bool) -> Void
    var onTap: () -> Void

    // ── 跳跳定稿参数（2026-07-31 祐祐三连跳 28/25/22）──
    private static let hopRest = 1.8
    private static let hopCrouchT = 0.21
    private static let hopRiseT = 0.15
    private static let hopFallT = 0.15
    private static let hopLandT = 0.07
    private static let hopGapT = 0.02
    private static let hopCrouch: CGFloat = 0.8
    private static let hopJumps: [CGFloat] = [28, 25, 22]

    private static let tapSlop: CGFloat = 6

    @State private var pressing = false
    @State private var dragging = false
    @State private var settling = false
    /// 待机脸：从 PET_IDLE_POOL 里随机轮换（六审「五态全接」）
    @State private var idleFace: PetState = .idle

    // 拖拽簿记（起点 + 起始时刻 + 是否已越过 tap 阈值）
    @State private var grabOrigin: CGPoint?
    @State private var grabDate = Date.distantPast
    @State private var grabMoved = false
    /// 拖拽时环境波形定格在此刻（对位 CSS animation-play-state: paused）
    @State private var freezeDate: Date?

    // 跳跳变换（专职 hopper 层，谁都盖不掉它）
    @State private var hopY: CGFloat = 0
    @State private var hopSX: CGFloat = 1
    @State private var hopSY: CGFloat = 1
    @State private var hopTask: Task<Void, Never>?

    // 落纸回弹（pet-land 关键帧，作用在 body 层）
    @State private var landY: CGFloat = 0
    @State private var landSX: CGFloat = 1
    @State private var landSY: CGFloat = 1
    @State private var settleTask: Task<Void, Never>?
    @State private var shuffleTask: Task<Void, Never>?

    private var hasMail: Bool { unread > 0 }

    private var visState: PetState {
        if dragging { return .happy }
        // 九审：开卡=举信递话（三只一致）。曾用 happy——Claude 那张是
        // 单腿站姿，未读没清时跳跳还在跑，单脚跳滑稽；举信+跳本就是
        // 有信的标准动作，不违和
        if active || hasMail { return .letter }
        return idleFace
    }

    var body: some View {
        let depth = PetPlacement.depthScale(pos.y)
        let h = PetPlacement.baseHeight * depth
        let w = h * 0.62

        TimelineView(.animation) { timeline in
            let now = dragging ? (freezeDate ?? timeline.date) : timeline.date
            let breathe = SceneWave.pingPong(now, period: 3.6, delay: -spec.phase)
            let sway = SceneWave.pingPong(now, period: 5.6, delay: -spec.phase)

            ZStack(alignment: .topLeading) {
                shadowView(w: w, breathe: breathe)

                // body（sway/press/drag/land）> hopper（跳跳）> art（呼吸）
                artStack(h: h, breathe: breathe)
                    .frame(width: w, height: h, alignment: .bottom)
                    .scaleEffect(x: hopSX, y: hopSY, anchor: .bottom)
                    .offset(y: hopY)
                    .modifier(BodyTransform(
                        pressing: pressing, dragging: dragging,
                        landY: landY, landSX: landSX, landSY: landSY,
                        settling: settling, swayDeg: -0.9 + 1.8 * sway))

                if hasMail && !dragging {
                    particles(w: w, h: h, now: timeline.date)
                }
            }
            .frame(width: w, height: h, alignment: .bottom)
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .position(x: pos.x, y: pos.y - h / 2)
        .opacity(dimmed ? 0.4 : 1)
        .animation(.sceneStandard(0.32), value: dimmed)
        .gesture(dragGesture)
        .onChange(of: hasMail) { syncHopTask() }
        .onChange(of: dragging) { syncHopTask() }
        .onChange(of: pressing) { syncHopTask() }
        .onAppear {
            syncHopTask()
            startIdleShuffle()
        }
        .onDisappear {
            stopHop(animated: false) // 离场也得复位，别把落地压扁帧带回下次亮相
            shuffleTask?.cancel()
            shuffleTask = nil
        }
        .accessibilityLabel("\(spec.name)，\(hasMail ? "有新消息" : "暂无新消息")")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 立绘（四态全挂树上做交叉淡入，切换不闪白）

    private func artStack(h: CGFloat, breathe: Double) -> some View {
        ZStack(alignment: .bottom) {
            ForEach(PetState.allCases, id: \.self) { state in
                SceneAsset.image(spec.art(state))
                    .resizable()
                    .scaledToFit()
                    .frame(height: h)
                    .opacity(visState == state ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.26), value: visState) // 换姿态比眨眼慢半拍
        .scaleEffect(
            x: 1 - 0.012 * breathe,
            y: 1 + 0.02 * breathe,
            anchor: .bottom
        )
        .shadow(color: SceneTokens.shadowInk.opacity(0.1), radius: 1.5, y: 2)
    }

    // MARK: - 落地软影

    private func shadowView(w: CGFloat, breathe: Double) -> some View {
        let base = SceneTokens.shadowInk
        return Ellipse()
            .fill(RadialGradient(
                stops: [
                    .init(color: base.opacity(0.22), location: 0),
                    .init(color: base.opacity(0.1), location: 0.48),
                    .init(color: base.opacity(0), location: 0.74),
                ],
                center: .center, startRadius: 0, endRadius: w * 0.37))
            .frame(width: w * 0.74, height: 18)
            .scaleEffect(
                x: dragging ? 1.24 : 1 - 0.05 * breathe,
                y: dragging ? 1.06 : 1)
            .opacity(dragging ? 0.4 : 1 - 0.15 * breathe)
            .animation(.sceneHover(0.2), value: dragging)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .offset(y: 2) // CSS bottom:-7 + 高 18 → 椭圆中心在容器底缘下 2pt
            .allowsHitTesting(false)
    }

    // MARK: - 未读贴纸（每只专属槽位，进场放射 + 待机放缩闪烁）

    @ViewBuilder
    private func particles(w: CGFloat, h: CGFloat, now: Date) -> some View {
        let slots = PET_SLOTS[spec.key] ?? []
        ForEach(Array(slots.enumerated()), id: \.offset) { i, slot in
            let size = w * slot.s
            let bd = 1.15 + Double((i * 29) % 7) / 7 * 0.45
            let bdel = -Double((i * 41) % 13) / 13 * 1.4 - spec.phase
            let u = SceneWave.cycle(now, period: bd, delay: bdel)
            let rot = SceneWave.keyframes(u, [(0, -1.5), (0.3, 1), (0.72, 1.5), (1, -1.5)])
            let scale = SceneWave.keyframes(u, [(0, 0.88), (0.3, 1.12), (0.72, 1.08), (1, 0.88)])
            let alpha = SceneWave.keyframes(u, [(0, 0.5), (0.3, 1), (0.72, 1), (1, 0.5)])

            SceneAsset.image("art/particles/\(spec.key.rawValue)/p\(slot.p).png")
                .resizable()
                .scaledToFit()
                .frame(width: size)
                .rotationEffect(.degrees(slot.r + rot))
                .scaleEffect(scale)
                .opacity(alpha)
                .shadow(color: SceneTokens.shadowInk.opacity(0.1), radius: 1, y: 1)
                .position(x: slot.x * w, y: slot.y * h)
                .allowsHitTesting(false)
                .zIndex(-1) // 人物始终在贴纸前（2026-07-31 祐祐定）
                .transition(.asymmetric(
                    insertion: AnyTransition.modifier(
                        active: ParticleFx(dx: w / 2 - slot.x * w, dy: h * 0.4 - slot.y * h, scale: 0.15, opacity: 0),
                        identity: ParticleFx(dx: 0, dy: 0, scale: 1, opacity: 1))
                        .animation(.interpolatingSpring(stiffness: 250, damping: 19).delay(Double(i) * 0.045)),
                    removal: AnyTransition.scale(scale: 0.3).combined(with: .opacity)
                        .animation(.easeOut(duration: 0.2))))
        }
    }

    // MARK: - 拖拽 / 点按

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("scene"))
            .onChanged { value in
                if grabOrigin == nil {
                    grabOrigin = pos
                    grabDate = Date()
                    grabMoved = false
                    freezeDate = Date()
                    settleTask?.cancel()
                    settling = false
                    landY = 0; landSX = 1; landSY = 1
                    withAnimation(.sceneStandard(0.12)) { pressing = true }
                }
                guard let origin = grabOrigin else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if !grabMoved && hypot(dx, dy) > Self.tapSlop {
                    grabMoved = true
                    withAnimation(.sceneHover(0.2)) {
                        pressing = false
                        dragging = true
                    }
                    onDragState(true)
                    SoundPlayer.shared.play(.paperLift)
                    Haptic.softTap()
                }
                guard grabMoved else { return }
                onMove(CGPoint(
                    x: min(PetPlacement.maxX, max(PetPlacement.minX, origin.x + dx)),
                    y: min(PetPlacement.maxY, max(PetPlacement.minY, origin.y + dy))))
            }
            .onEnded { _ in
                let began = grabDate
                grabOrigin = nil
                withAnimation(.sceneStandard(0.12)) { pressing = false }
                if grabMoved {
                    withAnimation(.sceneHover(0.2)) { dragging = false }
                    onDragState(false)
                    let safe = PetPlacement.resolveDrop(pos)
                    if safe != pos {
                        withAnimation(.sceneOut(0.32)) { onMove(safe) }
                    }
                    runSettle()
                    SoundPlayer.shared.play(.paperDrop)
                    Haptic.lightTap()
                } else if Date().timeIntervalSince(began) < 0.6 {
                    onTap()
                }
            }
    }

    /// pet-land：0% (-8, 1.05, 0.96) → 40% (0, 1.07, 0.91) → 70% (0, 0.975, 1.035) → 100% 静
    private func runSettle() {
        settleTask?.cancel()
        settling = true
        landY = -8; landSX = 1.05; landSY = 0.96
        settleTask = Task { @MainActor in
            let total = 0.46
            withAnimation(.sceneOut(total * 0.4)) { landY = 0; landSX = 1.07; landSY = 0.91 }
            try? await Task.sleep(for: .seconds(total * 0.4))
            guard !Task.isCancelled else { return }
            withAnimation(.sceneOut(total * 0.3)) { landSX = 0.975; landSY = 1.035 }
            try? await Task.sleep(for: .seconds(total * 0.3))
            guard !Task.isCancelled else { return }
            withAnimation(.sceneOut(total * 0.3)) { landSX = 1; landSY = 1 }
            try? await Task.sleep(for: .seconds(total * 0.3))
            settling = false
        }
    }

    // MARK: - 跳跳（有信才跳；拖拽即停）

    private func syncHopTask() {
        // 手一按住（pressing）就停跳：别等越过拖拽阈值才打断半空的那一跳
        let shouldHop = hasMail && !dragging && !pressing
        guard shouldHop else {
            stopHop()
            return
        }
        guard hopTask == nil else { return }
        hopTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(spec.phase)) // 三只错峰
            while !Task.isCancelled {
                await hopCycle()
            }
        }
    }

    /// 停跳 = 取消 + 跳跳层复位，两件事必须绑死。
    /// 复位曾挂在「hopTask 非空」的分支上，而 onDisappear（切 tab、开聊天
    /// fullScreenCover）先把 task 取消置了 nil 又不复位：若此刻正停在落地
    /// 压扁帧（sY 0.84~0.88，全周期占四分之一强），回页后要么扁着干等
    /// phase+1.8s 到下一轮才被救回，要么这中间信已读、hasMail 转 false——
    /// 两个分支都不进，小人就永久扁着（2026-08-03 Claude 实证）
    private func stopHop(animated: Bool = true) {
        hopTask?.cancel()
        hopTask = nil
        guard hopY != 0 || hopSX != 1 || hopSY != 1 else { return }
        guard animated else {
            hopY = 0; hopSX = 1; hopSY = 1
            return
        }
        withAnimation(.sceneOut(0.15)) { hopY = 0; hopSX = 1; hopSY = 1 }
    }

    @MainActor
    private func hopCycle() async {
        // 取消检查必须在写状态之前：睡眠被取消后若不设防，后续 seg 会把
        // 「落地压扁」帧补写进去、恢复段又被跳过——拖拽打断时小人就定格
        // 在压缩态，直到下一轮跳循环才被救回（2026-08-01 真机实证）
        func seg(_ duration: Double, _ change: () -> Void) async {
            guard !Task.isCancelled else { return }
            withAnimation(.sceneOut(duration)) { change() }
            try? await Task.sleep(for: .seconds(duration))
        }
        let crouch = Self.hopCrouch
        let cx = 1 + (1 - crouch) * 0.62 // 蹲下横向变宽（体积守恒近似）
        let squash: CGFloat = 0.88
        let sqx = 1 + (1 - squash) * 0.75
        let stretch: CGFloat = 1.07

        try? await Task.sleep(for: .seconds(Self.hopRest))
        if Task.isCancelled { return }
        await seg(Self.hopCrouchT) { hopSX = cx; hopSY = crouch } // 下蹲蓄力

        for (i, jumpH) in Self.hopJumps.enumerated() {
            if Task.isCancelled { return }
            let last = i == Self.hopJumps.count - 1
            await seg(Self.hopRiseT) { hopY = -jumpH; hopSX = 2 - stretch; hopSY = stretch }
            await seg(Self.hopFallT) { hopY = 0; hopSX = sqx; hopSY = squash }
            if !Task.isCancelled {
                SoundPlayer.shared.play(.hopLand, volume: Float(jumpH / 28) * Float(jumpH / 28))
            }
            if !last {
                await seg(Self.hopLandT) { hopSX = 1 + (cx - 1) * 0.55; hopSY = crouch + 0.07 }
                await seg(max(0.01, Self.hopGapT)) { hopSX = 1 + (cx - 1) * 0.7; hopSY = crouch + 0.04 }
            }
        }
        await seg(Self.hopLandT) { hopSX = 0.99; hopSY = 1.015 } // 末次缓冲回弹
        await seg(0.18) { hopY = 0; hopSX = 1; hopSY = 1 }       // 站定
    }

    // MARK: - 待机脸轮换（六审：letter/happy 留语义，其余隔一阵随机换）

    private func startIdleShuffle() {
        shuffleTask?.cancel()
        shuffleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5 + spec.phase * 2.3)) // 三只错峰
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 7...13)))
                guard !Task.isCancelled else { return }
                let pool = PET_IDLE_POOL.filter { $0 != idleFace }
                idleFace = pool.randomElement() ?? .idle
            }
        }
    }
}

// MARK: - body 层变换（sway 与按住/拎起/落纸互斥，对位 CSS 层级）

private struct BodyTransform: ViewModifier {
    let pressing: Bool
    let dragging: Bool
    let landY: CGFloat
    let landSX: CGFloat
    let landSY: CGFloat
    let settling: Bool
    let swayDeg: Double

    func body(content: Content) -> some View {
        if dragging {
            // 抓起来：抬高、放大、微倾（pet.css 注释与 pet-land 起点共同锚定的口径）
            content
                .scaleEffect(1.07, anchor: .bottom)
                .rotationEffect(.degrees(-2.5), anchor: .bottom)
                .offset(y: -10)
        } else if settling {
            content
                .scaleEffect(x: landSX, y: landSY, anchor: .bottom)
                .offset(y: landY)
        } else if pressing {
            content.scaleEffect(x: 0.965, y: 0.945, anchor: .bottom)
        } else {
            content.rotationEffect(.degrees(swayDeg), anchor: .bottom)
        }
    }
}

/// 贴纸进场：从人物身前中心放射到槽位
private struct ParticleFx: ViewModifier, Animatable {
    var dx: CGFloat
    var dy: CGFloat
    var scale: CGFloat
    var opacity: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(dx, dy), AnimatablePair(scale, opacity)) }
        set {
            dx = newValue.first.first
            dy = newValue.first.second
            scale = newValue.second.first
            opacity = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(x: dx, y: dy)
            .opacity(opacity)
    }
}
