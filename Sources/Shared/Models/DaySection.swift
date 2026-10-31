import Foundation

/// 화면에 표시할 날짜 범위: 첫날 0시부터 dayCount일
struct DayRange: Hashable, Sendable {
    let start: Date
    let dayCount: Int

    /// 범위의 마지막 날 0시
    func lastDay(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: max(dayCount - 1, 0), to: start) ?? start
    }
}

/// 하루 단위로 묶은 일정
struct DaySection: Identifiable, Hashable, Sendable {
    /// 그날 0시
    let day: Date
    /// 그날에 걸쳐 있는 일정 (표시 순서로 정렬)
    let events: [CalendarEvent]

    var id: Date { day }

    /// 범위의 날짜마다 일정을 묶는다. 일정이 없는 날도 빈 묶음으로 포함하고,
    /// 여러 날에 걸친 일정은 해당하는 날마다 들어간다.
    static func make(from events: [CalendarEvent], range: DayRange, calendar: Calendar = .current) -> [DaySection] {
        let sorted = events.sortedForDisplay()
        return (0..<max(range.dayCount, 0)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: range.start) else { return nil }
            return DaySection(day: day, events: sorted.filter { $0.occurs(on: day, calendar: calendar) })
        }
    }
}

extension DisplayMode {
    /// 기준일이 속한 표시 범위. offset만큼 이전(-)·다음(+) 범위로 이동한다.
    /// - 1일 보기: 하루씩 이동
    /// - 7일 보기: 기준일부터 7일, 7일씩 이동
    /// - 한 달 보기: 기준일이 속한 달 전체, 한 달씩 이동
    func dayRange(around reference: Date, offset: Int = 0, calendar: Calendar = .current) -> DayRange {
        let today = calendar.startOfDay(for: reference)
        switch self {
        case .daily:
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return DayRange(start: day, dayCount: 1)
        case .weekly:
            let start = calendar.date(byAdding: .day, value: offset * 7, to: today) ?? today
            return DayRange(start: start, dayCount: 7)
        case .monthly:
            let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
            let start = calendar.date(byAdding: .month, value: offset, to: monthStart) ?? monthStart
            let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
            return DayRange(start: start, dayCount: dayCount)
        }
    }

    /// 범위 제목. 예: "11월 1일 일요일", "11월 1일 – 11월 7일", "2026년 11월"
    func title(for range: DayRange, calendar: Calendar = .current) -> String {
        switch self {
        case .daily:
            return range.start.formatted(.dateTime.month().day().weekday(.wide))
        case .weekly:
            let first = range.start.formatted(.dateTime.month().day())
            let last = range.lastDay(calendar: calendar).formatted(.dateTime.month().day())
            return "\(first) – \(last)"
        case .monthly:
            return range.start.formatted(.dateTime.year().month(.wide))
        }
    }
}
