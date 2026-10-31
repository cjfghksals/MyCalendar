import Foundation

/// Google Calendar API v3 응답 중 앱에서 쓰는 필드만 담은 모델
enum GoogleCalendarAPI {
    struct CalendarListResponse: Decodable {
        let items: [CalendarListEntry]?
        let nextPageToken: String?
    }

    struct CalendarListEntry: Decodable {
        let id: String
        let summary: String?
        /// 사용자가 Google Calendar에서 바꾼 이름
        let summaryOverride: String?
        /// "#RRGGBB" (소문자일 수 있음)
        let backgroundColor: String?
        let primary: Bool?
    }

    struct EventsResponse: Decodable {
        let items: [Event]?
        let nextPageToken: String?
    }

    struct Event: Decodable {
        let id: String
        /// "confirmed", "tentative", "cancelled"
        let status: String?
        let summary: String?
        /// 일정별 색상 번호 (colors API의 event 표에서 찾는다)
        let colorId: String?
        let start: EventTime?
        let end: EventTime?
    }

    /// 종일 일정은 date("2026-11-01"), 시간 일정은 dateTime(RFC 3339)만 있다.
    struct EventTime: Decodable {
        let date: String?
        let dateTime: String?
    }

    struct ColorsResponse: Decodable {
        let event: [String: ColorDefinition]?
    }

    struct ColorDefinition: Decodable {
        let background: String
    }

    struct ErrorResponse: Decodable {
        struct Body: Decodable {
            let errors: [Item]?
        }

        struct Item: Decodable {
            let reason: String?
        }

        let error: Body?
    }
}

/// 여러 페이지로 나뉘어 오는 목록 응답
protocol GooglePagedResponse: Decodable {
    associatedtype Item: Decodable
    var items: [Item]? { get }
    var nextPageToken: String? { get }
}

extension GoogleCalendarAPI.CalendarListResponse: GooglePagedResponse {}
extension GoogleCalendarAPI.EventsResponse: GooglePagedResponse {}

/// Google 응답을 앱 공통 모델(CalendarInfo, CalendarEvent)로 바꾼다.
enum GoogleCalendarMapper {
    static let fallbackColorHex = "#8E8E93"
    static let untitled = "(제목 없음)"

    static func calendarInfo(from entry: GoogleCalendarAPI.CalendarListEntry) -> CalendarInfo {
        CalendarInfo(
            id: entry.id,
            name: nonEmpty(entry.summaryOverride) ?? nonEmpty(entry.summary) ?? entry.id,
            colorHex: normalizedHex(entry.backgroundColor) ?? fallbackColorHex,
            isPrimary: entry.primary ?? false
        )
    }

    /// 취소된 일정이나 시작·종료 시각을 읽을 수 없는 일정은 nil
    static func event(
        from item: GoogleCalendarAPI.Event,
        in calendarInfo: CalendarInfo,
        eventColors: [String: String],
        using calendar: Calendar
    ) -> CalendarEvent? {
        guard item.status != "cancelled",
              let start = item.start,
              let end = item.end,
              let startDate = date(from: start, using: calendar),
              let endDate = date(from: end, using: calendar) else {
            return nil
        }

        return CalendarEvent(
            // 같은 일정이 여러 캘린더에 있을 수 있으므로 캘린더 ID를 붙여 앱 안에서 고유하게 만든다.
            id: "\(calendarInfo.id)|\(item.id)",
            calendarId: calendarInfo.id,
            title: nonEmpty(item.summary?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? untitled,
            startDate: startDate,
            endDate: max(endDate, startDate),
            isAllDay: start.dateTime == nil && start.date != nil,
            colorHex: item.colorId.flatMap { eventColors[$0] } ?? calendarInfo.colorHex
        )
    }

    /// 종일 날짜는 기기 시간대의 그날 0시로, 시간 일정은 RFC 3339의 시차를 반영해 해석한다.
    static func date(from time: GoogleCalendarAPI.EventTime, using calendar: Calendar) -> Date? {
        if let dateTime = time.dateTime {
            return parseRFC3339(dateTime)
        }
        if let day = time.date {
            return parseDay(day, using: calendar)
        }
        return nil
    }

    /// "2026-11-01" → calendar 시간대의 2026년 11월 1일 0시
    static func parseDay(_ string: String, using calendar: Calendar) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func parseRFC3339(_ string: String) -> Date? {
        rfc3339Formatter.date(from: string) ?? rfc3339FractionalFormatter.date(from: string)
    }

    /// API 요청용 UTC 시각 문자열. 예: 2026-10-31T15:00:00Z
    static func rfc3339String(_ date: Date) -> String {
        rfc3339Formatter.string(from: date)
    }

    /// "#9fe1e7" → "#9FE1E7". 형식이 잘못되면 nil
    static func normalizedHex(_ hex: String?) -> String? {
        guard let hex, let components = HexColor.components(from: hex) else { return nil }
        return HexColor.string(red: components.red, green: components.green, blue: components.blue, alpha: components.alpha)
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    private static let rfc3339Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let rfc3339FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
