import XCTest
@testable import YushiKit

/// 卷轴派生行：日界切分与时间戳解析。
/// 时区固定注入，否则本机时区一换用例就飘。
final class ChatRowsTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func msg(_ id: String, _ sentAt: String, user: Bool = true) -> UiMessage {
        UiMessage(
            id: id,
            author: user ? "user" : "contact",
            status: .done,
            text: id,
            sentAt: sentAt
        )
    }

    func testParsesBothISOShapes() {
        XCTAssertNotNil(ChatTime.parse("2026-08-03T09:12:34.567Z"), "带小数秒的要能解析")
        XCTAssertNotNil(ChatTime.parse("2026-08-03T09:12:34Z"), "不带小数秒的也要能解析")
        XCTAssertNil(ChatTime.parse("昨天下午"))
    }

    func testInsertsOneMarkerPerCalendarDay() {
        let rows = groupRows([
            msg("a", "2026-08-02T22:00:00Z"),
            msg("b", "2026-08-02T23:30:00Z"),
            msg("c", "2026-08-03T00:10:00Z"),
        ], calendar: utc)

        // 日界 + a + b + 日界 + c
        XCTAssertEqual(rows.count, 5)
        guard case .dayMarker = rows[0].kind else { return XCTFail("首条前必须有日界") }
        XCTAssertEqual(rows[1].message?.id, "a")
        XCTAssertEqual(rows[2].message?.id, "b")
        guard case .dayMarker = rows[3].kind else { return XCTFail("跨日要再插一条日界") }
        XCTAssertEqual(rows[4].message?.id, "c")
    }

    func testSameDayGetsSingleMarker() {
        let rows = groupRows([
            msg("a", "2026-08-03T01:00:00Z"),
            msg("b", "2026-08-03T20:00:00Z"),
        ], calendar: utc)
        XCTAssertEqual(rows.filter { if case .dayMarker = $0.kind { return true }; return false }.count, 1)
    }

    func testUnparseableTimestampDoesNotDropTheMessage() {
        let rows = groupRows([msg("a", "不是时间"), msg("b", "2026-08-03T01:00:00Z")], calendar: utc)
        XCTAssertEqual(rows.compactMap { $0.message?.id }, ["a", "b"], "时间烂掉也不能吞消息")
    }

    func testRowIdsAreUnique() {
        let rows = groupRows([
            msg("a", "2026-08-02T22:00:00Z"),
            msg("b", "2026-08-03T00:10:00Z"),
            msg("c", "2026-08-04T00:10:00Z"),
        ], calendar: utc)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "ForEach 的 id 撞车会整段不渲染")
    }

    func testVersionCountFollowsPriorVersions() {
        var m = msg("x", "2026-08-03T01:00:00Z", user: false)
        XCTAssertEqual(m.versionCount, 1)
        m.priorVersions = ["旧的一版", "更旧的一版"]
        XCTAssertEqual(m.versionCount, 3)
    }

    func testReplyToSurvivesApiConversion() {
        let api = ApiMessage(
            id: "m1",
            conversationId: "c1",
            author: "user",
            status: .done,
            textContent: "引用了上一条",
            replyTo: "m0",
            isFavorited: false,
            sentAt: "2026-08-03T01:00:00Z",
            contactId: nil,
            parts: nil
        )
        XCTAssertEqual(UiMessage(from: api).replyTo, "m0")
    }
}
