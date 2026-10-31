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

    func testSettingsWithoutThemeUseAppearanceDefault() throws {
        let decoded = try JSONDecoder().decode(CalendarSettings.self, from: Data(#"{"appearance":"light"}"#.utf8))
        XCTAssertEqual(decoded.appearance, .light)
        XCTAssertEqual(decoded.theme, .light)
    }

    func testApplyAppearanceResetsTheme() {
        var settings = CalendarSettings()
        settings.theme.accentHex = "#FF0000"
        XCTAssertTrue(settings.isThemeCustomized)

        settings.applyAppearance(.light)
        XCTAssertEqual(settings.appearance, .light)
        XCTAssertEqual(settings.theme, .light)
        XCTAssertFalse(settings.isThemeCustomized)
    }

    func testCalendarColorOverrideWins() {
        let event = CalendarEvent(id: "1", calendarId: "work", title: "t", startDate: date(2), endDate: date(3),
                                  isAllDay: true, colorHex: "#111111")
        let settings = CalendarSettings(calendarColorOverrides: ["work": "#222222"])
        XCTAssertEqual(settings.colorHex(for: event), "#222222")
        XCTAssertEqual(CalendarSettings.default.colorHex(for: event), "#111111")
    }

    // MARK: - CalendarSnapshot

    func testSnapshotFromStageOneLoadsWithoutCalendars() throws {
        // 1단계에서 저장한 형식: calendars 키가 없다
        let snapshot = CalendarSnapshot.sample(relativeTo: date(2), calendar: calendar)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        json.removeValue(forKey: "calendars")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(CalendarSnapshot.self, from: data)
        XCTAssertEqual(decoded.events, snapshot.events)
        XCTAssertEqual(decoded.calendars, [])
    }

    func testSampleSnapshotHasCalendarsForAllEvents() {
        let snapshot = CalendarSnapshot.sample(relativeTo: date(2), calendar: calendar)
        let calendarIds = Set(snapshot.calendars.map(\.id))
        XCTAssertFalse(snapshot.events.isEmpty)
        XCTAssertTrue(snapshot.events.allSatisfy { calendarIds.contains($0.calendarId) })
    }

    // MARK: - AppGroupStorage

    /// 테스트마다 새 임시 폴더와 UserDefaults를 쓰는 저장소
    private func makeTemporaryStorage() throws -> AppGroupStorage {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "MyCalendarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        return AppGroupStorage(directoryURL: directory, defaults: defaults)
    }

    func testStorageRoundTrip() throws {
        let storage = try makeTemporaryStorage()
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

    // MARK: - SettingsStore / EventStore

    func testSettingsStoreSavesChangesAndRequestsWidgetReload() throws {
        let storage = try makeTemporaryStorage()
        let reloaded = expectation(description: "widget reload requested")
        let store = SettingsStore(storage: storage, reloadWidgets: { reloaded.fulfill() })

        store.update { $0.displayMode = .weekly }
        store.setCalendar("work", visible: false)
        store.setColorOverride("#123456", forCalendar: "work")

        // 앱을 다시 켠 것처럼 같은 저장소에서 새로 읽어도 유지되어야 한다
        let reopened = SettingsStore(storage: storage, reloadWidgets: {})
        XCTAssertEqual(reopened.settings.displayMode, .weekly)
        XCTAssertFalse(reopened.isCalendarVisible("work"))
        XCTAssertEqual(reopened.settings.calendarColorOverrides["work"], "#123456")

        // 연속 변경은 한 번의 갱신 요청으로 합쳐진다 (두 번 호출되면 expectation이 실패)
        wait(for: [reloaded], timeout: 3)
    }

    func testSettingsStoreBindingUpdatesSettings() throws {
        let store = SettingsStore(storage: try makeTemporaryStorage(), reloadWidgets: {})
        let binding = store.binding(\.maxEventsPerDay)
        binding.wrappedValue = 5
        XCTAssertEqual(store.settings.maxEventsPerDay, 5)
    }

    @MainActor
    func testEventStoreSampleDataAndClear() throws {
        var reloadCount = 0
        let store = EventStore(storage: try makeTemporaryStorage(), reloadWidgets: { reloadCount += 1 })
        XCTAssertFalse(store.hasData)

        store.loadSampleData(now: date(2, 8))
        XCTAssertTrue(store.hasData)
        XCTAssertEqual(store.calendars.count, CalendarInfo.samples.count)
        XCTAssertEqual(reloadCount, 1)

        var settings = CalendarSettings()
        settings.hiddenCalendarIds = ["sample-work"]
        XCTAssertFalse(store.visibleEvents(settings: settings).contains { $0.calendarId == "sample-work" })
        XCTAssertLessThan(store.visibleEvents(settings: settings).count, store.events.count)

        store.clear()
        XCTAssertFalse(store.hasData)
        XCTAssertEqual(reloadCount, 2)
    }
}
