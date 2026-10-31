import XCTest
@testable import MyCalendar

final class GoogleCalendarModelsTests: XCTestCase {
    private var seoul: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func seoulDate(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
        seoul.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let work = CalendarInfo(id: "work@example.com", name: "업무", colorHex: "#0A84FF", isPrimary: false)

    private func decodeEvents(_ json: String) throws -> [GoogleCalendarAPI.Event] {
        try JSONDecoder().decode(GoogleCalendarAPI.EventsResponse.self, from: Data(json.utf8)).items ?? []
    }

    // MARK: - OAuth 설정

    func testOAuthConfigBuildsRedirectFromClientID() throws {
        let config = try XCTUnwrap(GoogleOAuthConfig(clientID: " 1234-abcd.apps.googleusercontent.com "))
        XCTAssertEqual(config.clientID, "1234-abcd.apps.googleusercontent.com")
        XCTAssertEqual(config.redirectURL.absoluteString, "com.googleusercontent.apps.1234-abcd:/oauth2redirect")
        XCTAssertEqual(config.redirectURL.scheme, "com.googleusercontent.apps.1234-abcd")
    }

    func testOAuthConfigRejectsMissingOrInvalidClientID() {
        XCTAssertNil(GoogleOAuthConfig(clientID: nil))
        XCTAssertNil(GoogleOAuthConfig(clientID: ""))
        XCTAssertNil(GoogleOAuthConfig(clientID: "not-a-client-id"))
        XCTAssertNil(GoogleOAuthConfig(clientID: ".apps.googleusercontent.com"))
    }

    // MARK: - 캘린더 목록

    func testCalendarListMapping() throws {
        let json = """
        {
          "items": [
            {"id": "me@example.com", "summary": "me@example.com", "backgroundColor": "#9fe1e7", "primary": true},
            {"id": "ko.south_korea#holiday@group.v.calendar.google.com", "summary": "대한민국의 휴일",
             "summaryOverride": "공휴일", "backgroundColor": "#16a765"},
            {"id": "plain@example.com"}
          ],
          "nextPageToken": "next"
        }
        """
        let response = try JSONDecoder().decode(GoogleCalendarAPI.CalendarListResponse.self, from: Data(json.utf8))
        let calendars = try XCTUnwrap(response.items).map(GoogleCalendarMapper.calendarInfo(from:))

        XCTAssertEqual(response.nextPageToken, "next")
        XCTAssertEqual(calendars[0], CalendarInfo(id: "me@example.com", name: "me@example.com", colorHex: "#9FE1E7", isPrimary: true))
        XCTAssertEqual(calendars[1].name, "공휴일")
        XCTAssertEqual(calendars[1].colorHex, "#16A765")
        XCTAssertEqual(calendars[2].name, "plain@example.com")
        XCTAssertEqual(calendars[2].colorHex, GoogleCalendarMapper.fallbackColorHex)
        XCTAssertFalse(calendars[2].isPrimary)
    }

    // MARK: - 일정

    func testTimedEventUsesOffsetAndEventColor() throws {
        let items = try decodeEvents("""
        {"items": [{"id": "e1", "status": "confirmed", "summary": "팀 회의", "colorId": "11",
                    "start": {"dateTime": "2026-11-02T10:00:00+09:00"},
                    "end": {"dateTime": "2026-11-02T11:30:00+09:00"}}]}
        """)
        let event = try XCTUnwrap(GoogleCalendarMapper.event(from: items[0], in: work, eventColors: ["11": "#DC2127"], using: seoul))

        XCTAssertEqual(event.id, "work@example.com|e1")
        XCTAssertEqual(event.calendarId, "work@example.com")
        XCTAssertEqual(event.title, "팀 회의")
        XCTAssertEqual(event.startDate, seoulDate(11, 2, 10))
        XCTAssertEqual(event.endDate, seoulDate(11, 2, 11, 30))
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(event.colorHex, "#DC2127")
    }

    func testUTCAndFractionalSecondsAreParsed() throws {
        let items = try decodeEvents("""
        {"items": [{"id": "e2", "summary": "UTC",
                    "start": {"dateTime": "2026-11-02T01:00:00Z"},
                    "end": {"dateTime": "2026-11-02T02:00:00.000Z"}}]}
        """)
        let event = try XCTUnwrap(GoogleCalendarMapper.event(from: items[0], in: work, eventColors: [:], using: seoul))
        XCTAssertEqual(event.startDate, seoulDate(11, 2, 10))
        XCTAssertEqual(event.endDate, seoulDate(11, 2, 11))
    }

    func testAllDayEventStartsAtLocalMidnightWithExclusiveEnd() throws {
        let items = try decodeEvents("""
        {"items": [{"id": "e3", "summary": "출장",
                    "start": {"date": "2026-11-09"}, "end": {"date": "2026-11-11"}}]}
        """)
        let event = try XCTUnwrap(GoogleCalendarMapper.event(from: items[0], in: work, eventColors: [:], using: seoul))

        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.startDate, seoulDate(11, 9))
        XCTAssertEqual(event.endDate, seoulDate(11, 11))
        XCTAssertEqual(event.colorHex, "#0A84FF", "일정 색상이 없으면 캘린더 색상을 쓴다")
        XCTAssertTrue(event.occurs(on: seoulDate(11, 10, 12), calendar: seoul))
        XCTAssertFalse(event.occurs(on: seoulDate(11, 11, 12), calendar: seoul))
    }

    func testCancelledAndIncompleteEventsAreSkipped() throws {
        let items = try decodeEvents("""
        {"items": [
          {"id": "c", "status": "cancelled", "start": {"date": "2026-11-01"}, "end": {"date": "2026-11-02"}},
          {"id": "no-end", "summary": "끝 없음", "start": {"dateTime": "2026-11-01T10:00:00+09:00"}},
          {"id": "bad", "summary": "잘못된 날짜", "start": {"dateTime": "어제"}, "end": {"dateTime": "오늘"}}
        ]}
        """)
        XCTAssertTrue(items.compactMap { GoogleCalendarMapper.event(from: $0, in: self.work, eventColors: [:], using: self.seoul) }.isEmpty)
    }

    func testMissingTitleUsesPlaceholder() throws {
        let items = try decodeEvents("""
        {"items": [{"id": "e4", "summary": "   ",
                    "start": {"dateTime": "2026-11-02T10:00:00+09:00"}, "end": {"dateTime": "2026-11-02T10:00:00+09:00"}}]}
        """)
        let event = try XCTUnwrap(GoogleCalendarMapper.event(from: items[0], in: work, eventColors: [:], using: seoul))
        XCTAssertEqual(event.title, GoogleCalendarMapper.untitled)
    }

    // MARK: - 동기화 기간

    func testSyncRangeCoversPreviousMonthThroughTwoMonthsAhead() {
        let range = GoogleCalendarService.syncRange(around: seoulDate(11, 18, 15), calendar: seoul)
        XCTAssertEqual(range.start, seoulDate(10, 1))
        XCTAssertEqual(range.end, seoulDate(2, 1, year: 2027))
    }

    func testRFC3339QueryStringIsUTC() {
        XCTAssertEqual(GoogleCalendarMapper.rfc3339String(seoulDate(10, 1)), "2026-09-30T15:00:00Z")
    }

    // MARK: - 오류 응답

    func testForbiddenReasonsAreDistinguished() {
        let rateLimit = Data(#"{"error":{"code":403,"errors":[{"reason":"rateLimitExceeded"}]}}"#.utf8)
        let disabled = Data(#"{"error":{"code":403,"errors":[{"reason":"accessNotConfigured"}]}}"#.utf8)
        let other = Data(#"{"error":{"code":403,"errors":[{"reason":"forbidden"}]}}"#.utf8)

        XCTAssertEqual(GoogleCalendarService.error(forStatus: 403, body: rateLimit), .rateLimited)
        XCTAssertEqual(GoogleCalendarService.error(forStatus: 403, body: disabled), .apiNotEnabled)
        XCTAssertEqual(GoogleCalendarService.error(forStatus: 403, body: other), .forbidden)
        XCTAssertEqual(GoogleCalendarService.error(forStatus: 429, body: Data()), .rateLimited)
    }
}
