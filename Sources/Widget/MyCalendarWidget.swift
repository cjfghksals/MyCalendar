import SwiftUI
import WidgetKit

@main
struct MyCalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        MyCalendarWidget()
    }
}

/// 1단계 기본 위젯: 다가오는 일정 목록.
/// 1일/7일/월간 레이아웃은 5단계에서 Views/ 폴더로 분리해 구현한다.
struct MyCalendarWidget: Widget {
    let kind = "MyCalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            MyCalendarWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(hex: entry.settings.theme.backgroundHex, fallback: .black)
                }
        }
        .configurationDisplayName("MyCalendar")
        .description("다가오는 일정을 보여줍니다.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

struct MyCalendarWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    private var theme: ThemeColors { entry.settings.theme }
    private var textColor: Color { Color(hex: theme.textHex, fallback: .white) }
    private var secondaryColor: Color { Color(hex: theme.secondaryTextHex, fallback: .gray) }
    private var accentColor: Color { Color(hex: theme.accentHex, fallback: .blue) }

    private var emptyMessage: String {
        entry.hasData ? "예정된 일정 없음" : "앱에서 일정을 불러오세요"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            systemView
        }
    }

    // MARK: - 잠금 화면

    @ViewBuilder
    private var inlineView: some View {
        if let next = entry.events.first {
            Text("\(next.compactStartText(relativeTo: entry.date)) \(next.title)")
        } else {
            Text(emptyMessage)
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("오늘")
                    .font(.caption2)
                Text("\(entry.todayRemainingCount)")
                    .font(.title2.weight(.semibold))
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder
    private var rectangularView: some View {
        if entry.events.isEmpty {
            Text(emptyMessage)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(entry.events.prefix(3)) { event in
                    HStack(spacing: 4) {
                        Text(event.compactStartText(relativeTo: entry.date))
                            .font(.caption2.monospacedDigit())
                            .widgetAccentable()
                        Text(event.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 홈 화면

    private var systemView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)

            if entry.events.isEmpty {
                Spacer(minLength: 0)
                Text(emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(secondaryColor)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.events.prefix(family == .systemLarge ? 8 : 3)) { event in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(textColor)
                            .lineLimit(1)
                        Text(event.compactStartText(relativeTo: entry.date))
                            .font(.caption2)
                            .foregroundStyle(secondaryColor)
                    }
                    .padding(.leading, 9)
                    .overlay(alignment: .leading) {
                        // 일정 색상 막대: 텍스트 높이에 맞춘다
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: entry.settings.colorHex(for: event), fallback: accentColor))
                            .frame(width: 3)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview(as: .systemMedium) {
    MyCalendarWidget()
} timeline: {
    WidgetProvider.makeEntry(
        at: .now,
        snapshot: CalendarSnapshot(events: CalendarEvent.samples(), updatedAt: .now),
        settings: .default
    )
}
