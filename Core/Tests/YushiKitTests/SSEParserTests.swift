import XCTest
@testable import YushiKit

final class SSEParserTests: XCTestCase {
    func testBasicEventWithDefaults() {
        var parser = SSEParser()
        let events = parser.feed("data: hello\n\n")
        XCTAssertEqual(events, [SSEEvent(event: "message", data: "hello", id: nil)])
        // 冒号后无空格也合法
        XCTAssertEqual(parser.feed("data:hi\n\n").first?.data, "hi")
    }

    func testChunkSplitAcrossBoundary() {
        var parser = SSEParser()
        XCTAssertTrue(parser.feed("da").isEmpty)
        XCTAssertTrue(parser.feed("ta: 你").isEmpty)
        let events = parser.feed("好\n\ndata: x")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "你好")
        // 上一块残料 "data: x" 在此闭合
        XCTAssertEqual(parser.feed("\n\n").first?.data, "x")
    }

    func testMultiLineDataAndEventName() {
        var parser = SSEParser()
        let events = parser.feed("event: delta\ndata: line1\ndata: line2\n\n")
        XCTAssertEqual(events, [SSEEvent(event: "delta", data: "line1\nline2", id: nil)])
        // 事件名不粘连到下一个事件
        XCTAssertEqual(parser.feed("data: z\n\n").first?.event, "message")
    }

    func testIdTrackingForResume() {
        var parser = SSEParser()
        _ = parser.feed("id: 41\ndata: a\n\n")
        XCTAssertEqual(parser.lastEventId, "41")
        let events = parser.feed("id: 42\ndata: b\n\n")
        XCTAssertEqual(events.first?.id, "42")
        XCTAssertEqual(parser.lastEventId, "42")
    }

    func testCommentHeartbeatAndEmptyDataSkipped() {
        var parser = SSEParser()
        XCTAssertTrue(parser.feed(": ping\n\n").isEmpty)
        // 只有 event 名、没有 data → 不派发
        XCTAssertTrue(parser.feed("event: noop\n\n").isEmpty)
        // 且 event 名已被重置
        XCTAssertEqual(parser.feed("data: next\n\n").first?.event, "message")
    }

    func testCRLFIncludingSplitCRLF() {
        var parser = SSEParser()
        let first = parser.feed("data: a\r\n\r\ndata: b\r")
        XCTAssertEqual(first.map(\.data), ["a"])
        // 孤立 \r 结尾不消费（可能是被劈开的 \r\n）——补上 \n 后正常闭合
        let second = parser.feed("\n\r\n")
        XCTAssertEqual(second.map(\.data), ["b"])
    }

    func testGatewayShapedStream() {
        // 模拟网关真实形状：id + JSON data
        var parser = SSEParser()
        let chunk = "id: 7\ndata: {\"type\":\"text_delta\",\"text\":\"晚\"}\n\nid: 8\ndata: {\"type\":\"completed\"}\n\n"
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(ProviderEvent.decode(sseData: events[0].data), .textDelta("晚"))
        XCTAssertEqual(ProviderEvent.decode(sseData: events[1].data), .completed)
        XCTAssertEqual(parser.lastEventId, "8")
    }
}
