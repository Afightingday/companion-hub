import SwiftUI

/// 全局播放时钟:所有卡片共享同一虚拟时间,支持播放/暂停/重播/慢速。
/// 状态切换时重新锚定,保证相位连续。
final class MotionClock: ObservableObject {
    @Published private(set) var isPlaying = true
    @Published private(set) var speed: Double = 1
    private var anchorVirtual: Double = 0
    private var anchorDate = Date()

    func virtualTime(now: Date) -> Double {
        guard isPlaying else { return anchorVirtual }
        return anchorVirtual + now.timeIntervalSince(anchorDate) * speed
    }

    private func reanchor() {
        anchorVirtual = virtualTime(now: Date())
        anchorDate = Date()
    }

    func togglePlay() {
        reanchor()
        isPlaying.toggle()
    }

    func setSpeed(_ value: Double) {
        reanchor()
        speed = value
    }

    func restart() {
        anchorVirtual = 0
        anchorDate = Date()
    }
}

/// 单个动画画布:按逻辑尺寸 1:1 渲染一枚设计
struct MotionCell: View {
    let spec: MotionSpec
    let size: CGFloat
    let dark: Bool
    @ObservedObject var clock: MotionClock

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !clock.isPlaying)) { timeline in
            Canvas { context, _ in
                let vt = clock.virtualTime(now: timeline.date)
                let phase = vt.truncatingRemainder(dividingBy: spec.cycle) / spec.cycle
                spec.draw(&context, size, phase, dark)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 展板:首批原型评审用。启动即自动播放(CI 录制 10 秒无交互)。
struct MotionLabView: View {
    @StateObject private var clock = MotionClock()

    private let trueSizes: [CGFloat] = [20, 24, 28]

    var body: some View {
        ZStack {
            MotionPalette.paperBg.ignoresSafeArea()

            VStack(spacing: 16) {
                header
                ForEach(MotionCatalog.all) { spec in
                    card(for: spec)
                }
                controls
                Text("20/24/28 pt 实寸 · 纸/深双底 · 放大格按 24 pt 观感等比")
                    .font(.system(size: 10))
                    .foregroundStyle(MotionPalette.inkMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text("雨施流形 · Motion Lab")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(MotionPalette.ink)
            Text("首批原型 · v5(蒙版揭示真迹 / 笔原线宽)")
                .font(.system(size: 11))
                .foregroundStyle(MotionPalette.inkMuted)
        }
    }

    private func card(for spec: MotionSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(spec.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(MotionPalette.ink)
                Text(spec.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(MotionPalette.inkMuted)
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 14) {
                MotionCell(spec: spec, size: 112, dark: false, clock: clock)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(MotionPalette.paperCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MotionPalette.ink.opacity(0.08), lineWidth: 1)
                    )

                VStack(spacing: 8) {
                    sizeRow(for: spec, dark: false)
                    sizeRow(for: spec, dark: true)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MotionPalette.paperCard)
        )
        .shadow(color: Color(motionHex: 0x281418).opacity(0.05), radius: 10, x: 0, y: 8)
    }

    private func sizeRow(for spec: MotionSpec, dark: Bool) -> some View {
        HStack(spacing: 12) {
            Text(dark ? "深底" : "纸面")
                .font(.system(size: 9))
                .foregroundStyle(dark ? MotionPalette.inkMutedOnDark : MotionPalette.inkMuted)
                .frame(width: 26, alignment: .leading)

            ForEach(trueSizes, id: \.self) { size in
                VStack(spacing: 2) {
                    MotionCell(spec: spec, size: size, dark: dark, clock: clock)
                    Text("\(Int(size))")
                        .font(.system(size: 8))
                        .foregroundStyle(dark ? MotionPalette.inkMutedOnDark : MotionPalette.inkMuted)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(dark ? MotionPalette.darkBg : MotionPalette.paperCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MotionPalette.ink.opacity(dark ? 0 : 0.08), lineWidth: 1)
        )
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(clock.isPlaying ? "暂停" : "播放") {
                clock.togglePlay()
            }
            Button("重播") {
                clock.restart()
            }
            Picker("速度", selection: Binding(
                get: { clock.speed },
                set: { clock.setSpeed($0) }
            )) {
                Text("1×").tag(1.0)
                Text("0.25×").tag(0.25)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
        }
        .font(.system(size: 13))
        .buttonStyle(.bordered)
        .tint(MotionPalette.ink)
    }
}

#Preview {
    MotionLabView()
}
