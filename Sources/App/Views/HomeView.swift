import SwiftUI

/// 메인 화면: 표시 방식(1일·7일·한 달)에 따라 일정을 날짜별로 보여준다.
struct HomeView: View {
    enum Route: Hashable {
        case settings
    }

    let settingsStore: SettingsStore
    let eventStore: EventStore

    @State private var path: [Route]
    /// 오늘 기준 범위에서 이전(-)·다음(+)으로 이동한 정도
    @State private var offset = 0

    init(settingsStore: SettingsStore, eventStore: EventStore, showSettingsOnLaunch: Bool = false) {
        self.settingsStore = settingsStore
        self.eventStore = eventStore
        _path = State(initialValue: showSettingsOnLaunch ? [.settings] : [])
    }

    private var settings: CalendarSettings { settingsStore.settings }
    private var backgroundColor: Color { Color(hex: settings.theme.backgroundHex, fallback: .black) }
    private var textColor: Color { Color(hex: settings.theme.textHex, fallback: .primary) }
    private var secondaryColor: Color { Color(hex: settings.theme.secondaryTextHex, fallback: .secondary) }
    private var accentColor: Color { Color(hex: settings.theme.accentHex, fallback: .accentColor) }

    private var range: DayRange {
        settings.displayMode.dayRange(around: .now, offset: offset)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("보기", selection: settingsStore.binding(\.displayMode)) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    periodHeader

                    if eventStore.hasData {
                        CalendarView(
                            sections: DaySection.make(from: eventStore.visibleEvents(settings: settings), range: range),
                            displayMode: settings.displayMode,
                            settings: settings,
                            calendars: eventStore.calendars
                        )
                    } else {
                        emptyState
                    }
                }
                .padding(16)
            }
            .refreshable {
                // 3단계에서 Google Calendar 동기화로 바뀐다. 지금은 저장된 데이터를 다시 읽는다.
                eventStore.reload()
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("MyCalendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(backgroundColor, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("설정")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .settings:
                    SettingsView(settingsStore: settingsStore, eventStore: eventStore)
                }
            }
            .onChange(of: settings.displayMode) {
                offset = 0
            }
        }
    }

    // MARK: - 기간 제목과 이동

    private var periodHeader: some View {
        HStack {
            Button {
                offset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("이전")

            Spacer()

            VStack(spacing: 4) {
                Text(settings.displayMode.title(for: range))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(textColor)
                if offset != 0 {
                    Button("오늘로 이동") {
                        offset = 0
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Button {
                offset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("다음")
        }
        .tint(accentColor)
    }

    // MARK: - 데이터가 없을 때

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(accentColor)
            Text("아직 불러온 일정이 없습니다")
                .font(.headline)
                .foregroundStyle(textColor)
            Text("Google 계정 연결은 3단계에서 추가됩니다.\n지금은 샘플 일정으로 화면과 위젯을 확인할 수 있습니다.")
                .font(.subheadline)
                .foregroundStyle(secondaryColor)
                .multilineTextAlignment(.center)
            Button("샘플 일정 넣기") {
                eventStore.loadSampleData()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16).fill(textColor.opacity(0.07)))
    }
}

#Preview {
    let storage = AppGroupStorage(
        directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview"),
        defaults: UserDefaults(suiteName: "MyCalendar.preview") ?? .standard
    )
    let eventStore = EventStore(storage: storage, reloadWidgets: {})
    eventStore.loadSampleData()
    return HomeView(settingsStore: SettingsStore(storage: storage, reloadWidgets: {}), eventStore: eventStore)
        .preferredColorScheme(.dark)
}
