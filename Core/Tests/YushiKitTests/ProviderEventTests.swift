import XCTest
@testable import YushiKit

final class ProviderEventTests: XCTestCase {
    private func decode(_ json: String) throws -> ProviderEvent {
        try JSONDecoder().decode(ProviderEvent.self, from: Data(json.utf8))
    }

    func testKnownEvents() throws {
        XCTAssertEqual(try decode(#"{"type":"text_delta","text":"你好"}"#), .textDelta("你好"))
        XCTAssertEqual(try decode(#"{"type":"completed"}"#), .completed)
        XCTAssertEqual(try decode(#"{"type":"turn_started","turnId":"t-1"}"#), .turnStarted(turnId: "t-1"))

        let toolJson = #"{"type":"tool_call_started","toolCall":{"id":"t1","name":"calculator","status":"starting","inputPreview":"1+1"}}"#
        if case .toolCallStarted(let call) = try decode(toolJson) {
            XCTAssertEqual(call.name, "calculator")
            XCTAssertEqual(call.status, "starting")
        } else {
            XCTFail("tool_call_started 解码失败")
        }

        let errJson = #"{"type":"error","error":{"code":"rate_limit","message":"429","retryable":true}}"#
        if case .error(let e) = try decode(errJson) {
            XCTAssertEqual(e.code, "rate_limit")
            XCTAssertEqual(e.retryable, true)
        } else {
            XCTFail("error 解码失败")
        }
    }

    func testUnknownTypeFallsBackToRaw() throws {
        let event = try decode(#"{"type":"martian_signal","x":1}"#)
        if case .raw(_, let payload) = event {
            XCTAssertEqual(payload?["x"], .number(1))
        } else {
            XCTFail("未知事件应包成 raw 而不是丢弃")
        }
    }

    func testGroupSpeakerRawMarkerStaysReachable() throws {
        // 群聊多路复用标记（TurnManager 的 raw 事件）—— 第 3 批群聊要用
        let json = #"{"type":"raw","provider":"gateway","payload":{"groupSpeaker":{"contactId":"c1","messageId":"m1","name":"纸鹤"}}}"#
        if case .raw(let provider, let payload) = try decode(json) {
            XCTAssertEqual(provider, "gateway")
            XCTAssertEqual(payload?["groupSpeaker"]?["name"], .string("纸鹤"))
        } else {
            XCTFail("raw 事件解码失败")
        }
    }

    func testEncodeDecodeRoundTrip() throws {
        let events: [ProviderEvent] = [
            .textDelta("abc"),
            .reasoningSummaryDelta("思考…"),
            .turnStarted(turnId: "t-1"),
            .usage(TokenUsage(inputTokens: 10, outputTokens: 20, costEstimate: nil)),
            .approvalRequest(ApprovalRequest(
                id: "a1", provider: "glm", kind: "tool_use",
                title: "想写日历", detail: nil, payload: nil, expiresAt: nil
            )),
            .completed,
        ]
        let data = try JSONEncoder().encode(events)
        let back = try JSONDecoder().decode([ProviderEvent].self, from: data)
        XCTAssertEqual(back, events)
    }

    func testMessageModelTolerance() throws {
        let json = #"""
        {"id":"m1","conversationId":"c1","author":"contact","status":"done",
         "textContent":"晚上好","isFavorited":false,"sentAt":"2026-07-17T12:00:00.000Z",
         "parts":[
           {"id":"p1","seq":0,"kind":"reasoning_summary","payload":{"text":"…"}},
           {"id":"p2","seq":1,"kind":"weird_future_kind","payload":{}},
           {"id":"p3","seq":2,"kind":"text","payload":{"text":"晚上好"}}
         ],
         "someFutureField":{"a":1}}
        """#
        let message = try JSONDecoder().decode(ApiMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.parts?.count, 3)
        XCTAssertEqual(message.parts?[0].kind, .reasoningSummary)
        XCTAssertEqual(message.parts?[1].kind, .raw) // 未知 part 种类兜底
        XCTAssertFalse(message.isUser)
    }

    func testHealthResponseShape() throws {
        let json = #"""
        {"gateway":"ok","version":"0.2.0","uptimeSec":12,"store":"local",
         "providers":{"glm":{"state":"online"},"codex":{"state":"not_configured","detail":"CODEX_ENABLED=0"},
                      "claude":{"state":"not_configured","detail":"M1b 接入 ForwarderLink"}},
         "memoryd":{"state":"offline"}}
        """#
        let health = try JSONDecoder().decode(HealthResponse.self, from: Data(json.utf8))
        XCTAssertEqual(health.gateway, "ok")
        XCTAssertEqual(health.providers?["glm"]?.state, "online")
        XCTAssertEqual(health.memoryd?.state, "offline")
    }
}
