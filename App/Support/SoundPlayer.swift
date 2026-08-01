import AVFoundation
import UIKit

/// B12 音效引擎：全部素材由 tools/gen-assets.mjs 程序化合成（纸声/轻物落桌调性）。
/// - .ambient + mixWithOthers：不打断用户在放的歌，跟随静音拨片
/// - 每枚音效备两只 player 轮换，快速连击（跳跳三连）不互相掐断
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// 音效总闸。v2 真机听感仍「不自然」（2026-08-01 祐祐），整体退回无声；
    /// 素材与全部调用点保留，后续调好参数把这里拨回 true（或挂进案头开关）。
    /// 触觉反馈不走这里，照常。
    static let enabled = false

    enum Effect: String, CaseIterable {
        case tabTick = "tab-tick"       // 底栏切页
        case paperLift = "paper-lift"   // 拎起 pet
        case paperDrop = "paper-drop"   // 落定
        case hopLand = "hop-land"       // 跳跳落地（按跳高衰减音量）
        case cardOpen = "card-open"     // 开卡
        case cardClose = "card-close"   // 收卡
        case filmCurl = "film-curl"     // 掀膜起手
        case filmFly = "film-fly"       // 掀膜翻走
        case inkDrop = "ink-drop"       // 墨水瓶滴墨
        case enterChat = "enter-chat"   // 展笺进对话
    }

    /// 各音效基础音量（哑光手账：整体压低，跳跳/滴墨更轻）
    private static let baseGain: [Effect: Float] = [
        .tabTick: 0.42, .paperLift: 0.55, .paperDrop: 0.7, .hopLand: 0.5,
        .cardOpen: 0.8, .cardClose: 0.6, .filmCurl: 0.65, .filmFly: 0.85,
        .inkDrop: 0.32, .enterChat: 0.75,
    ]

    private var pools: [Effect: [AVAudioPlayer]] = [:]
    private var next: [Effect: Int] = [:]

    private init() {
        guard Self.enabled else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for effect in Effect.allCases {
            guard let url = Self.url(for: effect) else { continue }
            let pair = (0..<2).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
            pair.forEach { $0.prepareToPlay() }
            pools[effect] = pair
        }
    }

    private static func url(for effect: Effect) -> URL? {
        Bundle.main.url(forResource: effect.rawValue, withExtension: "wav", subdirectory: "Media/sounds")
            ?? Bundle.main.url(forResource: effect.rawValue, withExtension: "wav", subdirectory: "sounds")
            ?? Bundle.main.url(forResource: effect.rawValue, withExtension: "wav")
    }

    /// volume 是相对系数（0…1），叠在基础音量上
    func play(_ effect: Effect, volume: Float = 1) {
        guard Self.enabled, let pool = pools[effect], !pool.isEmpty else { return }
        let i = (next[effect] ?? 0) % pool.count
        next[effect] = i + 1
        let player = pool[i]
        player.volume = (Self.baseGain[effect] ?? 0.7) * volume
        player.currentTime = 0
        player.play()
    }
}

/// 轻触觉：与音效配对的原生手感（只在关键节点，不常驻嗡嗡）
enum Haptic {
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let light = UIImpactFeedbackGenerator(style: .light)

    static func softTap() { soft.impactOccurred() }
    static func lightTap() { light.impactOccurred() }
}
