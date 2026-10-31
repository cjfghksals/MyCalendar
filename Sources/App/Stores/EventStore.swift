import Foundation
import Observation
import WidgetKit

/// 일정 스냅샷(일정 + 캘린더 목록)을 관리한다.
/// 저장하면 App Group에 기록하고 위젯 갱신을 요청한다.
/// 3단계에서 Google Calendar 동기화 결과가 이곳으로 저장된다.
@Observable
final class EventStore {
    private(set) var snapshot: CalendarSnapshot?
    private(set) var lastError: String?

    @ObservationIgnored private let storage: AppGroupStorage
    @ObservationIgnored private let reloadWidgets: () -> Void

    init(
        storage: AppGroupStorage = .shared,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.storage = storage
        self.reloadWidgets = reloadWidgets
        self.snapshot = storage.loadSnapshot()
    }

    var events: [CalendarEvent] { snapshot?.events ?? [] }
    var calendars: [CalendarInfo] { snapshot?.calendars ?? [] }
    var hasData: Bool { snapshot != nil }

    /// App Group으로 위젯과 데이터를 공유하고 있는지 여부 (서명되지 않은 빌드에서는 false)
    var isSharedWithWidget: Bool { storage.isShared }

    /// 숨기지 않은 캘린더의 일정
    func visibleEvents(settings: CalendarSettings) -> [CalendarEvent] {
        events.filter { !settings.hiddenCalendarIds.contains($0.calendarId) }
    }

    func reload() {
        snapshot = storage.loadSnapshot()
    }

    func save(_ newSnapshot: CalendarSnapshot) {
        do {
            try storage.saveSnapshot(newSnapshot)
            snapshot = newSnapshot
            lastError = nil
        } catch {
            lastError = "일정 저장 실패: \(error.localizedDescription)"
        }
        reloadWidgets()
    }

    func loadSampleData(now: Date = .now) {
        save(.sample(relativeTo: now))
    }

    func clear() {
        do {
            try storage.clearSnapshot()
            snapshot = nil
            lastError = nil
        } catch {
            lastError = "일정 삭제 실패: \(error.localizedDescription)"
        }
        reloadWidgets()
    }
}
