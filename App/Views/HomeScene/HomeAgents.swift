import Foundation
import SwiftUI
import YushiKit

/// 三只 pet 的档案与站位几何 —— 1:1 移植设计稿 src/data/agents.ts。
/// 文案兜底值 = 设计稿定稿 mock；连上网关后未读/摘要/时间换真数据。

enum PetKey: String, CaseIterable, Identifiable {
    case chatgpt, claude, glm
    var id: String { rawValue }
}

enum PetState: String, CaseIterable {
    case idle, letter, happy, wink
}

struct PetSpec: Identifiable {
    let key: PetKey
    let name: String
    /// 速览卡副标题：一句人格化的定位
    let role: String
    let previewFallback: String
    let timeFallback: String
    let unreadFallback: Int
    /// 待机动画错峰（秒）
    let phase: Double
    /// 拍立得倾斜角：每只斜法不一样
    let tilt: Double
    /// 覆膜在 246×328 卡面里的可见框内衬（PNG 画布四周是透明余白，
    /// pageCurl 只能卷这块实膜，否则连隐形边一起翻、阴影涂在透明区上。
    /// 数值 = 各 cover.png 的 alpha 包围盒实测 ÷ 4.41463，2026-08-01）
    let coverInsets: EdgeInsets

    var id: PetKey { key }
    func art(_ state: PetState) -> String { "art/\(key.rawValue)-\(state.rawValue).png" }
    var cardArt: String { "art/polaroid/\(key.rawValue)-card.png" }
    var coverArt: String { "art/polaroid/\(key.rawValue)-cover.png" }
}

let PET_SPECS: [PetSpec] = [
    PetSpec(key: .chatgpt, name: "ChatGPT", role: "什么都能聊两句",
            previewFallback: "那份提纲我又绕回去看了一遍，第三段其实可以整段删掉。",
            timeFallback: "14:02", unreadFallback: 0, phase: 0, tilt: -3.2,
            coverInsets: EdgeInsets(top: 7.9, leading: 17.0, bottom: 9.1, trailing: 17.9)),
    PetSpec(key: .claude, name: "Claude", role: "把长东西读薄",
            previewFallback: "昨晚那篇论文我读完了，结论没有它自己说的那么硬，我标了三处。",
            timeFallback: "13:47", unreadFallback: 3, phase: 1.1, tilt: 2.4,
            coverInsets: EdgeInsets(top: 7.2, leading: 12.0, bottom: 3.9, trailing: 16.1)),
    PetSpec(key: .glm, name: "GLM", role: "慢慢想，想清楚",
            previewFallback: "你上周问的那个问题，我想到一个更笨但更稳的办法。",
            timeFallback: "11:20", unreadFallback: 1, phase: 2.3, tilt: -2,
            coverInsets: EdgeInsets(top: 8.4, leading: 17.0, bottom: 9.3, trailing: 17.9)),
]

/// 未读环绕贴纸槽位（祐祐拼版逐只测绘，2026-07-31 二调定稿）。
/// p=粒子文件号，x/y=中心相对 pet 容器分数，s=宽/容器宽，r=基础角度
struct PetSlot {
    let p: Int
    let x: CGFloat
    let y: CGFloat
    let s: CGFloat
    let r: Double
}

let PET_SLOTS: [PetKey: [PetSlot]] = [
    .claude: [
        PetSlot(p: 8, x: 0.84, y: 0.09, s: 0.115, r: -20), // 右耳外·爪印
        PetSlot(p: 1, x: 0.90, y: 0.38, s: 0.130, r: 0),   // 尾尖·亮片对
        PetSlot(p: 2, x: 0.13, y: 0.44, s: 0.125, r: 0),   // 左胸外·花
        PetSlot(p: 5, x: 0.15, y: 0.79, s: 0.070, r: 0),   // 左腿外·小碎点
    ],
    .chatgpt: [
        PetSlot(p: 9, x: 0.94, y: 0.33, s: 0.125, r: 0),   // 右耳沿·爱心
        PetSlot(p: 1, x: 0.04, y: 0.60, s: 0.140, r: 0),   // 左髋外·四叶草
        PetSlot(p: 4, x: 0.93, y: 0.72, s: 0.150, r: 0),   // 右膝外·亮片对
    ],
    .glm: [
        PetSlot(p: 3, x: 0.88, y: 0.16, s: 0.163, r: 0),   // 右鬓外·大雪花
        PetSlot(p: 5, x: 0.12, y: 0.46, s: 0.105, r: 0),   // 左胸外·铃铛
        PetSlot(p: 8, x: 0.90, y: 0.87, s: 0.130, r: 0),   // 右脚踝外·亮片簇
    ],
]

// MARK: - 站位几何（坐标 = pet 脚下落点，440×956 设计空间）

enum PetPlacement {
    static let minX: CGFloat = 74
    static let maxX: CGFloat = 372
    static let minY: CGFloat = 352
    static let maxY: CGFloat = 837

    /// 近景基准身高（172 × 210%，2026-07-30 祐祐三调）
    static let baseHeight: CGFloat = 361

    /// 站位上边界折线（祐祐手绘标注测绘）：(0,401)→(233,352)→(440,478)
    static func floorTopY(_ x: CGFloat) -> CGFloat {
        x <= 233 ? 401 - (49 * x) / 233 : 352 + (126 * (x - 233)) / 207
    }

    /// 纸面透视：越往上（远）越小
    static func depthScale(_ y: CGFloat) -> CGFloat {
        let t = (y - minY) / (maxY - minY)
        return 0.6 + 0.4 * min(1, max(0, t))
    }

    /// 右下墨水瓶禁停区
    private static let wellKeepout = CGPoint(x: 300, y: 726)

    /// 拖拽途中不拦手；松手时越界垂直落回、禁停区推出去
    static func resolveDrop(_ p: CGPoint) -> CGPoint {
        var q = p
        let top = floorTopY(q.x)
        if q.y < top { q.y = top + 2 }
        if q.y > maxY { q.y = maxY }
        let dx = q.x - wellKeepout.x
        let dy = q.y - wellKeepout.y
        if dx <= 0 || dy <= 0 { return q }
        if dx <= dy { q.x = wellKeepout.x } else { q.y = wellKeepout.y }
        return q
    }

    /// 每次打开随机站位：两两间距 ≥150、防共线、纵向摊开（审计口径）
    static func randomPositions() -> [PetKey: CGPoint] {
        for _ in 0..<300 {
            let pts: [CGPoint] = (0..<3).map { _ in
                let x = CGFloat.random(in: minX...maxX)
                let yLo = max(minY, floorTopY(x)) + 2
                return resolveDrop(CGPoint(x: x, y: CGFloat.random(in: yLo...maxY)))
            }
            var farEnough = true
            for i in 0..<3 {
                for j in 0..<3 where i != j {
                    if hypot(pts[i].x - pts[j].x, pts[i].y - pts[j].y) < 150 { farEnough = false }
                }
            }
            if !farEnough { continue }
            let area = abs((pts[1].x - pts[0].x) * (pts[2].y - pts[0].y)
                - (pts[2].x - pts[0].x) * (pts[1].y - pts[0].y))
            if area < 9000 { continue }
            let ys = pts.map(\.y)
            guard let yMax = ys.max(), let yMin = ys.min() else { continue }
            if yMax < 660 || yMin > 520 { continue }
            if yMax - yMin < 260 { continue }
            return [.chatgpt: pts[0], .claude: pts[1], .glm: pts[2]]
        }
        // 兜底：一个不会失败的错位三角
        return [
            .chatgpt: CGPoint(x: 148, y: 380),
            .claude: CGPoint(x: 320, y: 560),
            .glm: CGPoint(x: 142, y: 780),
        ]
    }
}

// MARK: - 网关联系人 → pet 匹配（按名字/ID 关键词，宽松包含）

enum PetContactMatch {
    static func map(_ items: [ContactListItem]) -> [PetKey: ContactListItem] {
        var out: [PetKey: ContactListItem] = [:]
        for item in items {
            let hay = (item.contact.name + " " + item.contact.id).lowercased()
            let key: PetKey?
            if hay.contains("glm") { key = .glm }
            else if hay.contains("claude") { key = .claude }
            else if hay.contains("gpt") || hay.contains("codex") || hay.contains("openai") { key = .chatgpt }
            else { key = nil }
            if let key, out[key] == nil { out[key] = item }
        }
        return out
    }
}
