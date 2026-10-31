import Foundation

/// 일정 표시 방식
enum DisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "1일 보기"
        case .weekly: return "7일 보기"
        case .monthly: return "한 달 보기"
        }
    }
}

/// HEX 문자열("#RRGGBB")로 관리하는 색상 테마
struct ThemeColors: Codable, Hashable, Sendable {
    var backgroundHex: String
    var textHex: String
    var secondaryTextHex: String
    var accentHex: String

    static let dark = ThemeColors(
        backgroundHex: "#1C1C1E",
        textHex: "#FFFFFF",
        secondaryTextHex: "#8E8E93",
        accentHex: "#0A84FF"
    )

    static let light = ThemeColors(
        backgroundHex: "#FFFFFF",
        textHex: "#1C1C1E",
        secondaryTextHex: "#6E6E73",
        accentHex: "#007AFF"
    )
}

/// 사용자 표시 설정. 앱에서 수정하고 위젯은 읽기만 한다.
struct CalendarSettings: Codable, Hashable, Sendable {
    var displayMode: DisplayMode
    var theme: ThemeColors
    var showEventTitles: Bool
    /// 월간 달력에서 날짜별로 보여줄 최대 일정 수
    var maxEventsPerDay: Int
    /// 표시하지 않을 캘린더 ID (새로 추가된 캘린더는 기본으로 표시)
    var hiddenCalendarIds: Set<String>
    /// 캘린더 ID → 사용자가 지정한 색상 HEX
    var calendarColorOverrides: [String: String]

    static let maxEventsPerDayRange = 1...6
    static let `default` = CalendarSettings()

    init(
        displayMode: DisplayMode = .daily,
        theme: ThemeColors = .dark,
        showEventTitles: Bool = true,
        maxEventsPerDay: Int = 3,
        hiddenCalendarIds: Set<String> = [],
        calendarColorOverrides: [String: String] = [:]
    ) {
        self.displayMode = displayMode
        self.theme = theme
        self.showEventTitles = showEventTitles
        self.maxEventsPerDay = Self.clampedMaxEvents(maxEventsPerDay)
        self.hiddenCalendarIds = hiddenCalendarIds
        self.calendarColorOverrides = calendarColorOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case displayMode
        case theme
        case showEventTitles
        case maxEventsPerDay
        case hiddenCalendarIds
        case calendarColorOverrides
    }

    /// 저장된 값이 없거나 읽을 수 없는 항목은 기본값으로 채운다.
    /// 앱 업데이트로 설정 항목이 늘어나도 기존 설정을 잃지 않기 위함이다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CalendarSettings()
        displayMode = (try? container.decodeIfPresent(DisplayMode.self, forKey: .displayMode)) ?? fallback.displayMode
        theme = (try? container.decodeIfPresent(ThemeColors.self, forKey: .theme)) ?? fallback.theme
        showEventTitles = (try? container.decodeIfPresent(Bool.self, forKey: .showEventTitles)) ?? fallback.showEventTitles
        let storedMax = (try? container.decodeIfPresent(Int.self, forKey: .maxEventsPerDay)) ?? fallback.maxEventsPerDay
        maxEventsPerDay = Self.clampedMaxEvents(storedMax)
        hiddenCalendarIds = (try? container.decodeIfPresent(Set<String>.self, forKey: .hiddenCalendarIds)) ?? fallback.hiddenCalendarIds
        calendarColorOverrides = (try? container.decodeIfPresent([String: String].self, forKey: .calendarColorOverrides)) ?? fallback.calendarColorOverrides
    }

    /// 일정에 적용할 색상: 사용자 지정 캘린더 색상 → 일정 자체 색상 순
    func colorHex(for event: CalendarEvent) -> String? {
        calendarColorOverrides[event.calendarId] ?? event.colorHex
    }

    private static func clampedMaxEvents(_ value: Int) -> Int {
        min(max(value, maxEventsPerDayRange.lowerBound), maxEventsPerDayRange.upperBound)
    }
}
