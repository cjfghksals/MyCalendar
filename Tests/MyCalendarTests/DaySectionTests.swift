import XCTest
@testable import MyCalendar

final class DaySectionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, calendarId: "c", title: id, startDate: start, endDate: end, isAllDay: allDay, colorHex: nil)
    }

    // MARK: - 범위 계산

    func testDailyRangeMovesByOneDay() {
        let range = DisplayMode.daily.dayRange(around: date(11, 1, 15), offset: 1, calendar: calendar)
        XCTAssertEqual(range.start, date(11, 2))
        XCTAssertEqual(range.dayCount, 1)
    }

    func testWeeklyRangeStartsTodayAndMovesBySevenDays() {
        let current = DisplayMode.weekly.dayRange(around: date(11, 1, 15), calendar: calendar)
        XCTAssertEqual(current.start, date(11, 1))
        XCTAssertEqual(current.dayCount, 7)
        XCTAssertEqual(current.lastDay(calendar: calendar), date(11, 7))

        let previous = DisplayMode.weekly.dayRange(around: date(11, 1, 15), offset: -1, calendar: calendar)
        XCTAssertEqual(previous.start, date(10, 25))
    }

    func testMonthlyRangeCoversWholeMonth() {
        let november = DisplayMode.monthly.dayRange(around: date(11, 18), calendar: calendar)
        XCTAssertEqual(november.start, date(11, 1))
        XCTAssertEqual(november.dayCount, 30)

        let october = DisplayMode.monthly.dayRange(around: date(11, 18), offset: -1, calendar: calendar)
        XCTAssertEqual(october.start, date(10, 1))
        XCTAssertEqual(october.dayCount, 31)

        let january = DisplayMode.monthly.dayRange(around: date(11, 18), offset: 2, calendar: calendar)
        XCTAssertEqual(january.start, date(1, 1, year: 2027))
        XCTAssertEqual(january.dayCount, 31)
    }

    // MARK: - 날짜별 묶기

    func testWeekIncludesEmptyDays() {
        let events = [
            event("회의", date(11, 2, 10), date(11, 2, 11)),
            event("약속", date(11, 4, 19), date(11, 4, 21)),
        ]
        let range = DayRange(start: date(11, 1), dayCount: 7)
        let sections = DaySection.make(from: events, range: range, calendar: calendar)

        XCTAssertEqual(sections.count, 7)
        XCTAssertEqual(sections.map(\.events.count), [0, 1, 0, 1, 0, 0, 0])
        XCTAssertEqual(sections.first?.day, date(11, 1))
    }

    func testMultiDayEventAppearsOnEachDay() {
        let trip = event("출장", date(11, 3), date(11, 6), allDay: true)
        let range = DayRange(start: date(11, 1), dayCount: 7)
        let sections = DaySection.make(from: [trip], range: range, calendar: calendar)

        XCTAssertEqual(sections.map(\.events.count), [0, 0, 1, 1, 1, 0, 0])
    }

    func testEventsInSectionAreSortedForDisplay() {
        let late = event("저녁", date(11, 1, 19), date(11, 1, 20))
        let early = event("아침", date(11, 1, 8), date(11, 1, 9))
        let allDay = event("휴일", date(11, 1), date(11, 2), allDay: true)
        let sections = DaySection.make(from: [late, early, allDay], range: DayRange(start: date(11, 1), dayCount: 1),
                                       calendar: calendar)

        XCTAssertEqual(sections.first?.events.map(\.id), ["휴일", "아침", "저녁"])
    }
}
