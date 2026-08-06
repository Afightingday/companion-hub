import SwiftUI

/// 设计令牌的唯一真源（原 packages/paper-ui/src/tokens.ts 已随网页端于 2026-08-03 删除）。
enum PaperTheme {
    static let paperBg = Color(hex: 0xF5F2E8)
    static let paperCard = Color(hex: 0xFBF9F1)
    static let paperCardDim = Color(hex: 0xF0ECDD)
    static let ink = Color(hex: 0x2C382E)
    static let inkMuted = Color(hex: 0x7C8477)
    static let matcha = Color(hex: 0x8A9A6B)
    static let matchaDeep = Color(hex: 0x5F6F49)
    static let matchaSoft = Color(hex: 0xE7EBDA)
    static let blush = Color(hex: 0xE2B3B7)
    static let danger = Color(hex: 0xC2705C)

    static let cardRadius: CGFloat = 18
    static let smallRadius: CGFloat = 10
    /// 0 8px 20px rgba(40,20,24,.05) —— 卡片浮在纸面上的浅阴影
    static let shadowColor = Color(hex: 0x281418).opacity(0.05)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    /// 纸面卡片：浅底 + 18pt 圆角 + 极浅阴影
    func paperCard() -> some View {
        background(
            PaperTheme.paperCard,
            in: RoundedRectangle(cornerRadius: PaperTheme.cardRadius, style: .continuous)
        )
        .shadow(color: PaperTheme.shadowColor, radius: 10, x: 0, y: 8)
    }
}

/// ISO 时间戳 → 展示文本（gateway/Supabase 两种 ISO 变体都接）
enum PaperFormat {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(fromISO string: String) -> Date? {
        isoWithFraction.date(from: string) ?? iso.date(from: string)
    }

    /// 聊天列表右上角：今天显示 HH:mm，往日显示「M月d日」
    static func shortTime(_ isoString: String) -> String {
        guard let date = date(fromISO: isoString) else { return "" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.defaultDigits).day())
    }
}
