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
        // 网关真实形状（chat.ts:159，2026-08-02 真机 SSE 抓包核对）：
        // data 行是 TurnEventEnvelope 信封 {"id":N,"turnId":"…","event":{…}}，不是裸事件
        var parser = SSEParser()
        let chunk = "retry: 2000\n\n"
            + "id: 7\ndata: {\"id\":7,\"turnId\":\"t-1\",\"event\":{\"type\":\"text_delta\",\"text\":\"晚\"}}\n\n"
            + "id: 8\ndata: {\"id\":8,\"turnId\":\"t-1\",\"event\":{\"type\":\"completed\"}}\n\n"
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 2)
        let first = TurnEventEnvelope.decode(sseData: events[0].data)
        XCTAssertEqual(first?.id, 7)
        XCTAssertEqual(first?.turnId, "t-1")
        XCTAssertEqual(first?.event, .textDelta("晚"))
        XCTAssertEqual(TurnEventEnvelope.decode(sseData: events[1].data)?.event, .completed)
        XCTAssertEqual(parser.lastEventId, "8")
    }

    func testEnvelopeKeepsUnknownInnerEventAsRaw() {
        // 信封外层合法 + 内层未知事件 → 兜成 .raw，整流不断（R2）
        let env = TurnEventEnvelope.decode(
            sseData: "{\"id\":3,\"turnId\":\"t-1\",\"event\":{\"type\":\"holo_projection\",\"x\":1}}"
        )
        if case .raw = env?.event {} else {
            XCTFail("未知内层事件应兜成 raw，实际：\(String(describing: env?.event))")
        }
    }

    func testGoneFrameSurfacesEventName() {
        // turn 已被网关清理：event: gone 帧要能按事件名识别（回落拉历史的信号）
        var parser = SSEParser()
        let events = parser.feed("event: gone\ndata: {\"turnId\":\"t-9\"}\n\n")
        XCTAssertEqual(events.first?.event, "gone")
    }
}
