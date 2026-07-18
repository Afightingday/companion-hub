import Foundation

/// 一条完整的 SSE 事件。
public struct SSEEvent: Sendable, Equatable {
    public var event: String
    public var data: String
    public var id: String?

    public init(event: String = "message", data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// text/event-stream 增量解析器（WHATWG EventSource 语义的子集）。
/// 纯逻辑、无网络依赖：喂原始文本块、吐完整事件 —— Linux 上可单测。
/// 网络绑定（URLSession bytes → feed）放在 App 层，第 2 批接。
public struct SSEParser: Sendable {
    /// 还没凑成整行的残料（块边界可能把一行甚至 \r\n 劈开）
    private var pending = ""
    private var dataLines: [String] = []
    private var eventName = ""
    private var eventId: String?

    /// 最近一次收到的事件 id —— 断线重连时作 Last-Event-ID 续流
    public private(set) var lastEventId: String?

    public init() {}

    public mutating func feed(_ chunk: String) -> [SSEEvent] {
        pending += chunk
        var events: [SSEEvent] = []
        while let line = nextLine() {
            if let event = consume(line: line) {
                events.append(event)
            }
        }
        return events
    }

    /// 取出一整行并从缓冲移除；行终止符 \n、\r\n、\r 均可。
    /// 缓冲以孤立 \r 结尾时先不消费 —— 它可能是被块边界劈开的 \r\n 前半。
    private mutating func nextLine() -> String? {
        var i = pending.startIndex
        while i < pending.endIndex {
            let ch = pending[i]
            if ch == "\n" {
                let line = String(pending[..<i])
                pending.removeSubrange(...i)
                return line
            }
            if ch == "\r" {
                let next = pending.index(after: i)
                if next == pending.endIndex { return nil }
                let line = String(pending[..<i])
                let removeEnd = pending[next] == "\n" ? pending.index(after: next) : next
                pending.removeSubrange(pending.startIndex..<removeEnd)
                return line
            }
            i = pending.index(after: i)
        }
        return nil
    }

    private mutating func consume(line: String) -> SSEEvent? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil } // 注释 / 心跳

        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[..<colon])
            value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "data":
            dataLines.append(value)
        case "event":
            eventName = value
        case "id":
            if !value.contains("\0") {
                eventId = value
                lastEventId = value
            }
        default:
            break // retry 等字段暂不使用
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            dataLines = []
            eventName = ""
            eventId = nil
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(
            event: eventName.isEmpty ? "message" : eventName,
            data: dataLines.joined(separator: "\n"),
            id: eventId
        )
    }
}
