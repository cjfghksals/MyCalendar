import Foundation
import WidgetKit

struct CalendarEntry: TimelineEntry {
    let date: Date
    /// 지금 이후에 끝나는 일정 (표시 순서로 정렬, 숨긴 캘린더 제외)
    let events: [CalendarEvent]
    let settings: CalendarSettings
    /// 앱이 일정을 한 번이라도 저장했는지 여부
    let hasData: Bool

    /// 오늘 남은 일정 수
    var todayRemainingCount: Int {
        events.filter { $0.occurs(on: date) }.count
    }
}

/// App Group 저장소의 일정 스냅샷을 읽어 위젯 타임라인을 만든다.
/// 위젯은 네트워크나 인증 정보에 접근하지 않고, 앱이 저장해 둔 데이터만 표시한다.
struct WidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        let sample = CalendarSnapshot(events: CalendarEvent.samples(), updatedAt: .now)
        return Self.makeEntry(at: .now, snapshot: sample, settings: .default)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        // 위젯 갤러리 미리보기에서 저장된 일정이 없으면 샘플을 보여준다.
        if context.isPreview && AppGroupStorage.shared.loadSnapshot() == nil {
            completion(placeholder(in: context))
        } else {
            completion(currentEntry(at: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400))

        // WidgetKit은 실시간 갱신을 보장하지 않는다. 지정한 시각 이후 시스템이 적절한 때에 다시 요청한다.
        // 일정 데이터가 바뀌면 앱이 WidgetCenter로 즉시 갱신을 요청한다.
        let refreshDate = min(tomorrow, now.addingTimeInterval(60 * 60))
        completion(Timeline(entries: [currentEntry(at: now)], policy: .after(refreshDate)))
    }

    private func currentEntry(at date: Date) -> CalendarEntry {
        let storage = AppGroupStorage.shared
        return Self.makeEntry(at: date, snapshot: storage.loadSnapshot(), settings: storage.loadSettings())
    }

    static func makeEntry(at date: Date, snapshot: CalendarSnapshot?, settings: CalendarSettings) -> CalendarEntry {
        let events = (snapshot?.events ?? [])
            .filter { $0.endDate > date && !settings.hiddenCalendarIds.contains($0.calendarId) }
            .sortedForDisplay()
        return CalendarEntry(date: date, events: Array(events.prefix(20)), settings: settings, hasData: snapshot != nil)
    }
}
