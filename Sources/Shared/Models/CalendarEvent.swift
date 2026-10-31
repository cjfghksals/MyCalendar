import Foundation

/// 앱과 위젯이 공유하는 일정 모델.
/// Google Calendar API 응답을 이 모델로 변환한 뒤 App Group 저장소에 저장한다.
struct CalendarEvent: Codable, Identifiable, Hashable, Sendable {
    /// Google Calendar 이벤트 ID (반복 일정은 인스턴스별 ID)
    let id: String
    /// 일정이 속한 캘린더 ID
    let calendarId: String
    let title: String
    let startDate: Date
    /// 종일 일정은 Google Calendar와 같이 "다음 날 0시"를 종료 시각으로 둔다 (배타적 종료).
    let endDate: Date
    let isAllDay: Bool
    /// "#RRGGBB" 형식. nil이면 캘린더 기본 색상 또는 강조색을 사용한다.
    let colorHex: String?

    /// 주어진 날짜(로컬 기준 하루)에 일정이 걸쳐 있는지 여부
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        // 시작과 종료가 같은 일정도 해당 날짜에 표시되도록 최소 1초 길이로 본다.
        let effectiveEnd = endDate > startDate ? endDate : startDate.addingTimeInterval(1)
        return startDate < dayEnd && effectiveEnd > dayStart
    }

    /// "종일" 또는 "오후 3:00 – 오후 4:00" 형태의 시간 문자열
    var timeRangeText: String {
        if isAllDay { return "종일" }
        let start = startDate.formatted(date: .omitted, time: .shortened)
        let end = endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    /// 좁은 공간용 시작 표시: 오늘(또는 진행 중) 일정은 시각, 다른 날 일정은 날짜
    func compactStartText(relativeTo now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(startDate, inSameDayAs: now) || startDate < now {
            return isAllDay ? "종일" : startDate.formatted(date: .omitted, time: .shortened)
        }
        return startDate.formatted(.dateTime.month(.defaultDigits).day())
    }
}

/// App Group에 저장하는 일정 묶음. 위젯은 이 값만 읽는다.
struct CalendarSnapshot: Codable, Hashable, Sendable {
    var events: [CalendarEvent]
    var updatedAt: Date
}

extension Sequence where Element == CalendarEvent {
    /// 시작 시각순, 같은 시각이면 종일 일정 먼저, 그다음 제목순
    func sortedForDisplay() -> [CalendarEvent] {
        sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.title < rhs.title
        }
    }
}

extension CalendarEvent {
    /// Google Calendar 연동 전, 화면과 위젯 확인용 샘플 일정
    static func samples(relativeTo now: Date = .now, calendar: Calendar = .current) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: now)

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }

        func time(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset)) ?? day(offset)
        }

        return [
            CalendarEvent(id: "sample-1", calendarId: "sample-work", title: "프로젝트 마감",
                          startDate: day(0), endDate: day(1), isAllDay: true, colorHex: "#FF453A"),
            CalendarEvent(id: "sample-2", calendarId: "sample-personal", title: "아침 운동",
                          startDate: time(0, 7), endDate: time(0, 8), isAllDay: false, colorHex: "#30D158"),
            CalendarEvent(id: "sample-3", calendarId: "sample-work", title: "팀 회의",
                          startDate: time(0, 10), endDate: time(0, 11), isAllDay: false, colorHex: "#0A84FF"),
            CalendarEvent(id: "sample-4", calendarId: "sample-personal", title: "점심 약속",
                          startDate: time(0, 12, 30), endDate: time(0, 13, 30), isAllDay: false, colorHex: "#FF9F0A"),
            CalendarEvent(id: "sample-5", calendarId: "sample-work", title: "주간 보고서 작성",
                          startDate: time(0, 16), endDate: time(0, 17), isAllDay: false, colorHex: "#0A84FF"),
            CalendarEvent(id: "sample-6", calendarId: "sample-personal", title: "병원 예약",
                          startDate: time(1, 15), endDate: time(1, 16), isAllDay: false, colorHex: "#BF5AF2"),
            CalendarEvent(id: "sample-7", calendarId: "sample-family", title: "가족 모임",
                          startDate: day(3), endDate: day(4), isAllDay: true, colorHex: "#FF375F"),
        ]
    }
}
