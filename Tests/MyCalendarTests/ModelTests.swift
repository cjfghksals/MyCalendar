import XCTest
@testable import MyCalendar

final class ModelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: - CalendarEvent

    func testAllDayEventOccursOnlyOnItsDay() {
        // Google Calendar 종일 일정: 종료일은 다음 날 0시 (배타적)
        let event = CalendarEvent(id: "1", calendarId: "c", title: "종일", startDate: date(2), endDate: date(3),
                                  isAllDay: true, colorHex: nil)
        XCTAssertFalse(event.occurs(on: date(1, 12), calendar: calendar))
        XCTAssertTrue(event.occurs(on: date(2, 12), calendar: calendar))
        XCTAssertFalse(event.occurs(on: date(3, 12), calendar: calendar))
    }

    func testOvernightEventOccursOnBothDays() {
        let event = CalendarEvent(id: "2", calendarId: "c", title: "야간", startDate: date(2, 22), endDate: date(3, 2),
                                  isAllDay: false, colorHex: nil)
        XCTAssertTrue(event.occurs(on: date(2), calendar: calendar))
        XCTAssertTrue(event.occurs(on: date(3), calendar: calendar))
        XCTAssertFalse(event.occurs(on: date(4), calendar: calendar))
    }

    func testZeroLengthEventStillOccurs() {
        let event = CalendarEvent(id: "3", calendarId: "c", title: "알림", startDate: date(2, 9), endDate: date(2, 9),
                                  isAllDay: false, colorHex: nil)
        XCTAssertTrue(event.occurs(on: date(2), calendar: calendar))
    }

    func testSortedForDisplayPutsAllDayFirst() {
        let timed = CalendarEvent(id: "a", calendarId: "c", title: "회의", startDate: date(2, 9), endDate: date(2, 10),
                                  isAllDay: false, colorHex: nil)
        let allDay = CalendarEvent(id: "b", calendarId: "c", title: "휴가", startDate: date(2), endDate: date(3),
                                   isAllDay: true, colorHex: nil)
        XCTAssertEqual([timed, allDay].sortedForDisplay().map(\.id), ["b", "a"])
    }

    // MARK: - CalendarSettings

    func testSettingsDecodeMissingFieldsAsDefaults() throws {
        let decoded = try JSONDecoder().decode(CalendarSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, CalendarSettings.default)
    }

    func testSettingsDecodeInvalidValuesSafely() throws {
        let json = #"{"displayMode":"yearly","maxEventsPerDay":99,"showEventTitles":false}"#
        let decoded = try JSONDecoder().decode(CalendarSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.displayMode, .daily)
        XCTAssertEqual(decoded.maxEventsPerDay, CalendarSettings.maxEventsPerDayRange.upperBound)
        XCTAssertFalse(decoded.showEventTitles)
    }

    func testCalendarColorOverrideWins() {
        let event = CalendarEvent(id: "1", calendarId: "work", title: "t", startDate: date(2), endDate: date(3),
                                  isAllDay: true, colorHex: "#111111")
        let settings = CalendarSettings(calendarColorOverrides: ["work": "#222222"])
        XCTAssertEqual(settings.colorHex(for: event), "#222222")
        XCTAssertEqual(CalendarSettings.default.colorHex(for: event), "#111111")
    }

    // MARK: - AppGroupStorage

    func testStorageRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "MyCalendarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let storage = AppGroupStorage(directoryURL: directory, defaults: defaults)
        XCTAssertNil(storage.loadSnapshot())
        XCTAssertEqual(storage.loadSettings(), CalendarSettings.default)

        let snapshot = CalendarSnapshot(events: CalendarEvent.samples(relativeTo: date(2), calendar: calendar),
                                        updatedAt: date(2, 8))
        try storage.saveSnapshot(snapshot)
        XCTAssertEqual(storage.loadSnapshot(), snapshot)

        let settings = CalendarSettings(displayMode: .monthly, theme: .light, maxEventsPerDay: 4)
        try storage.saveSettings(settings)
        XCTAssertEqual(storage.loadSettings(), settings)

        try storage.clearSnapshot()
        XCTAssertNil(storage.loadSnapshot())
    }
}
