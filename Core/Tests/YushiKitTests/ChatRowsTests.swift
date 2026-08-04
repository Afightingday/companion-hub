import XCTest
@testable import YushiKit

/// 卷轴派生行：整点切分与时间戳解析。
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

    private func markerCount(_ rows: [ChatRow]) -> Int {
        rows.filter { if case .timeMarker = $0.kind { return true }; return false }.count
    }

    func testInsertsOneMarkerPerHour() {
        let rows = groupRows([
            msg("a", "2026-08-02T22:00:00Z"),
            msg("b", "2026-08-02T23:30:00Z"),
            msg("c", "2026-08-03T00:10:00Z"),
        ], calendar: utc)

        // 三条各占一个整点：锚 + a + 锚 + b + 锚 + c
        XCTAssertEqual(rows.count, 6)
        guard case .timeMarker = rows[0].kind else { return XCTFail("首条前必须有时间锚") }
        XCTAssertEqual(rows[1].message?.id, "a")
        guard case .timeMarker = rows[2].kind else { return XCTFail("跨整点要再插一条") }
        XCTAssertEqual(rows[3].message?.id, "b")
        guard case .timeMarker = rows[4].kind else { return XCTFail("跨日同样是跨整点") }
        XCTAssertEqual(rows[5].message?.id, "c")
    }

    func testSameHourGetsSingleMarker() {
        let rows = groupRows([
            msg("a", "2026-08-03T01:00:00Z"),
            msg("b", "2026-08-03T01:59:59Z"),
        ], calendar: utc)
        XCTAssertEqual(markerCount(rows), 1, "同一小时内只锚一次")
    }

    /// 同一天但跨了整点 —— 旧的按日切分会漏掉这条，胶囊就永远停在早上那个点
    func testSameDayDifferentHoursGetTwoMarkers() {
        let rows = groupRows([
            msg("a", "2026-08-03T01:00:00Z"),
            msg("b", "2026-08-03T20:00:00Z"),
        ], calendar: utc)
        XCTAssertEqual(markerCount(rows), 2)
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
