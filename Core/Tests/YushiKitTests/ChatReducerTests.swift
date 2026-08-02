import XCTest
@testable import YushiKit

/// 归约器用例——规则以 apps/web/src/lib/applyEvent.ts 为准绳，两端改动必须同步。
final class ChatReducerTests: XCTestCase {
    private func makeMessage() -> UiMessage {
        UiMessage(id: "m1", author: "contact", status: .streaming, sentAt: "2026-08-02T00:00:00Z")
    }

    func testTextDeltaAccumulates() {
        var m = makeMessage()
        m.apply(.textDelta("你"))
        m.apply(.textDelta("好"))
        XCTAssertEqual(m.text, "你好")
        XCTAssertEqual(m.status, .streaming)
    }

    func testReasoningTopSingletonAppends() {
        var m = makeMessage()
        m.apply(.textDelta("正文"))
        m.apply(.reasoningSummaryDelta("想"))
        m.apply(.reasoningSummaryDelta("想…"))
        XCTAssertEqual(m.parts.count, 1)
        guard case .reasoningSummary(let text) = m.parts[0].payload else {
            return XCTFail("思考纸条应在 parts 顶部")
        }
        XCTAssertEqual(text, "想想…")
    }

    func testToolUpsertAndResultMerge() {
        var m = makeMessage()
        let call = ToolCall(id: "c1", name: "查日历", status: "starting", inputPreview: "明天", input: nil)
        m.apply(.toolCallStarted(call))
        var running = call
        running.status = "running"
        m.apply(.toolCallUpdated(running))
        XCTAssertEqual(m.parts.count, 1, "同 id 的工具事件应 upsert 到同一张卡")

        m.apply(.toolResult(ToolResultPayload(toolCallId: "c1", ok: true, preview: "3 件事", payload: nil)))
        XCTAssertEqual(m.parts.count, 1)
        guard case .toolCall(let card) = m.parts[0].payload else { return XCTFail() }
        XCTAssertEqual(card.call?.status, "running")
        XCTAssertEqual(card.result?.ok, true)
    }

    func testOrphanToolResultMakesCard() {
        var m = makeMessage()
        m.apply(.toolResult(ToolResultPayload(toolCallId: "cx", ok: false, preview: nil, payload: nil)))
        guard case .toolCall(let card) = m.parts[0].payload else { return XCTFail() }
        XCTAssertNil(card.call)
        XCTAssertEqual(card.result?.toolCallId, "cx")
    }

    func testApprovalFlowAndBroadcast() {
        var m = makeMessage()
        let approval = ApprovalRequest(
            id: "ap1", provider: "codex", kind: "command_exec",
            title: "执行命令", detail: nil, payload: nil, expiresAt: nil
        )
        m.apply(.approvalRequest(approval))
        guard case .approval(_, .pending) = m.parts[0].payload else {
            return XCTFail("新信封应为 pending")
        }

        var list = [m]
        applyApprovalResolved(messages: &list, approvalId: "ap1", decision: "approve")
        guard case .approval(_, .approved) = list[0].parts[0].payload else {
            return XCTFail("广播后应置 approved")
        }
    }

    func testErrorAbortedAndCompleted() {
        var m = makeMessage()
        m.apply(.error(ProviderErrorInfo(code: "aborted", message: "已停止生成", retryable: nil)))
        XCTAssertEqual(m.status, .aborted)
        XCTAssertEqual(m.errorText, "已停止生成")

        var m2 = makeMessage()
        m2.apply(.error(ProviderErrorInfo(code: "auth", message: "未登录", retryable: nil)))
        XCTAssertEqual(m2.status, .error)

        var m3 = makeMessage()
        m3.apply(.completed)
        XCTAssertEqual(m3.status, .done)
    }

    func testNoopEventsDontTouchState() {
        var m = makeMessage()
        m.apply(.turnStarted(turnId: "t"))
        m.apply(.usage(TokenUsage(inputTokens: 1, outputTokens: 2, costEstimate: nil)))
        m.apply(.raw(provider: "gateway", payload: nil))
        XCTAssertEqual(m, makeMessage())
    }

    func testApprovalResolvedExtraction() {
        // 网关自造控制信号：raw{payload.approvalResolved} 要在归约前分流
        let event = ProviderEvent.raw(
            provider: "gateway",
            payload: .object([
                "approvalResolved": .object(["id": .string("ap1"), "decision": .string("deny")]),
            ])
        )
        let resolved = event.approvalResolved
        XCTAssertEqual(resolved?.id, "ap1")
        XCTAssertEqual(resolved?.decision, "deny")
        XCTAssertNil(ProviderEvent.completed.approvalResolved)
        XCTAssertNil(ProviderEvent.raw(provider: "codex", payload: .object(["x": .number(1)])).approvalResolved)
    }

    func testHistoryConversionFiltersTextAndRawParts() throws {
        // kind==text/raw 不进 UI parts（正文已在 textContent，防双份渲染）
        let json = """
        {
          "id": "m9", "author": "contact", "status": "done",
          "textContent": "正文在此", "sentAt": "2026-08-02T00:00:00Z",
          "parts": [
            {"id": "p0", "seq": 0, "kind": "reasoning_summary", "payload": {"text": "先想了想"}},
            {"id": "p1", "seq": 1, "kind": "text", "payload": {"text": "正文在此"}},
            {"id": "p2", "seq": 2, "kind": "tool_call", "payload": {"call": {"id": "c1", "name": "查日历", "status": "done"}, "result": {"toolCallId": "c1", "ok": true}}},
            {"id": "p3", "seq": 3, "kind": "raw", "payload": {"note": "model_degraded"}},
            {"id": "p4", "seq": 4, "kind": "approval", "payload": {"approval": {"id": "ap2", "provider": "glm", "kind": "tool_use", "title": "写入日历"}, "status": "approved"}}
          ]
        }
        """
        let api = try JSONDecoder().decode(ApiMessage.self, from: Data(json.utf8))
        let ui = UiMessage(from: api)
        XCTAssertEqual(ui.text, "正文在此")
        XCTAssertEqual(ui.parts.count, 3, "text 与 raw part 不应进 UI")
        guard case .reasoningSummary(let r) = ui.parts[0].payload else { return XCTFail() }
        XCTAssertEqual(r, "先想了想")
        guard case .toolCall(let card) = ui.parts[1].payload else { return XCTFail() }
        XCTAssertEqual(card.call?.name, "查日历")
        XCTAssertEqual(card.result?.ok, true)
        guard case .approval(let ap, .approved) = ui.parts[2].payload else { return XCTFail() }
        XCTAssertEqual(ap.id, "ap2")
    }
}
