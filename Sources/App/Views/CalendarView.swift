import SwiftUI

/// 날짜별 일정 목록.
/// - 1일·7일 보기: 범위의 모든 날짜를 보여주고, 일정이 없는 날은 "일정 없음"으로 표시
/// - 한 달 보기: 일정이 있는 날짜만 목록으로 표시 (7열 달력은 4단계에서 구현)
struct CalendarView: View {
    let sections: [DaySection]
    let displayMode: DisplayMode
    let settings: CalendarSettings
    let calendars: [CalendarInfo]
    var now: Date = .now

    private var textColor: Color { Color(hex: settings.theme.textHex, fallback: .primary) }
    private var secondaryColor: Color { Color(hex: settings.theme.secondaryTextHex, fallback: .secondary) }
    private var accentColor: Color { Color(hex: settings.theme.accentHex, fallback: .accentColor) }

    private var calendarNames: [String: String] {
        Dictionary(calendars.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private var displayedSections: [DaySection] {
        displayMode == .monthly ? sections.filter { !$0.events.isEmpty } : sections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if displayedSections.isEmpty {
                Text("이번 달에는 일정이 없습니다.")
                    .font(.subheadline)
                    .foregroundStyle(secondaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            ForEach(displayedSections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    if displayMode != .daily {
                        dayHeader(section.day)
                    }

                    if section.events.isEmpty {
                        Text(displayMode == .daily ? "오늘은 일정이 없습니다." : "일정 없음")
                            .font(.subheadline)
                            .foregroundStyle(secondaryColor)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(section.events) { event in
                            EventCard(
                                event: event,
                                colorHex: settings.colorHex(for: event),
                                calendarName: calendarNames[event.calendarId],
                                textColor: textColor,
                                secondaryColor: secondaryColor,
                                accentColor: accentColor
                            )
                        }
                    }
                }
            }
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        HStack(spacing: 8) {
            Text(day.formatted(.dateTime.month().day().weekday(.abbreviated)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(textColor)
            if Calendar.current.isDate(day, inSameDayAs: now) {
                Text("오늘")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accentColor))
            }
        }
    }
}

private struct EventCard: View {
    let event: CalendarEvent
    let colorHex: String?
    let calendarName: String?
    let textColor: Color
    let secondaryColor: Color
    let accentColor: Color

    private var subtitle: String {
        [event.timeRangeText, calendarName].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.title)
                .font(.body.weight(.medium))
                .foregroundStyle(textColor)
                .lineLimit(2)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            // 일정 색상 막대: 카드 높이에 맞춘다
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: colorHex, fallback: accentColor))
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.leading, 6)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(textColor.opacity(0.07)))
    }
}
