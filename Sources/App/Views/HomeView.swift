import SwiftUI
import WidgetKit

/// 1단계 임시 메인 화면.
/// 저장소 상태를 보여주고, 샘플 일정으로 앱 → App Group → 위젯 데이터 흐름을 점검한다.
/// Google Calendar 연동과 실제 달력 화면은 3·4단계에서 구현한다.
struct HomeView: View {
    private let storage = AppGroupStorage.shared

    @State private var snapshot: CalendarSnapshot?
    @State private var errorMessage: String?

    private var events: [CalendarEvent] {
        snapshot?.events.sortedForDisplay() ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section("상태") {
                    LabeledContent("App Group", value: storage.isShared ? "연결됨" : "사용 불가 (서명 필요)")
                    LabeledContent("저장된 일정", value: "\(events.count)개")
                    if let updatedAt = snapshot?.updatedAt {
                        LabeledContent("마지막 갱신", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("일정") {
                    if events.isEmpty {
                        Text("저장된 일정이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            EventRow(event: event)
                        }
                    }
                }

                Section {
                    Button("샘플 일정 저장", action: saveSamples)
                    Button("저장된 일정 지우기", role: .destructive, action: clearEvents)
                } footer: {
                    Text("Google Calendar 연동 전에 앱과 위젯 사이의 데이터 공유를 확인하기 위한 임시 기능입니다.")
                }
            }
            .navigationTitle("MyCalendar")
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        snapshot = storage.loadSnapshot()
    }

    private func saveSamples() {
        do {
            try storage.saveSnapshot(CalendarSnapshot(events: CalendarEvent.samples(), updatedAt: .now))
            errorMessage = nil
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
        reload()
    }

    private func clearEvents() {
        do {
            try storage.clearSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = "삭제 실패: \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
        reload()
    }
}

private struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(Color(hex: event.colorHex, fallback: .accentColor))
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Text("\(event.startDate.formatted(.dateTime.month().day().weekday())) · \(event.timeRangeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
