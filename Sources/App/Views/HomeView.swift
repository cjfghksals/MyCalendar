import SwiftUI

/// 메인 화면: 표시 방식(1일·7일·한 달)에 따라 일정을 날짜별로 보여준다.
struct HomeView: View {
    enum Route: Hashable {
        case settings
    }

    let settingsStore: SettingsStore
    let eventStore: EventStore
    let authService: GoogleAuthService

    @State private var path: [Route]
    /// 오늘 기준 범위에서 이전(-)·다음(+)으로 이동한 정도
    @State private var offset = 0

    init(
        settingsStore: SettingsStore,
        eventStore: EventStore,
        authService: GoogleAuthService,
        showSettingsOnLaunch: Bool = false
    ) {
        self.settingsStore = settingsStore
        self.eventStore = eventStore
        self.authService = authService
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

                    if let message = eventStore.lastError {
                        errorBanner(message)
                    }

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
                if authService.isSignedIn {
                    await eventStore.syncIfSignedIn(auth: authService, force: true)
                } else {
                    eventStore.reload()
                }
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("MyCalendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(backgroundColor, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if eventStore.isSyncing {
                        ProgressView()
                            .accessibilityLabel("동기화 중")
                    }
                }
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
                    SettingsView(settingsStore: settingsStore, eventStore: eventStore, authService: authService)
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

    // MARK: - 오류 안내

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                eventStore.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryColor)
            }
            .accessibilityLabel("안내 닫기")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.15)))
    }

    // MARK: - 데이터가 없을 때

    private var emptyMessage: String {
        if authService.isSignedIn {
            return "Google Calendar에서 일정을 불러오지 못했습니다.\n아래로 당기거나 다시 시도해 주세요."
        }
        if authService.isConfigured {
            return "Google 계정을 연결하면 일정을 불러옵니다.\n샘플 일정으로 화면과 위젯을 먼저 확인할 수도 있습니다."
        }
        return "이 빌드에는 Google 클라이언트 ID가 없습니다 (README 참고).\n샘플 일정으로 화면과 위젯을 확인할 수 있습니다."
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(accentColor)
            Text("아직 불러온 일정이 없습니다")
                .font(.headline)
                .foregroundStyle(textColor)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(secondaryColor)
                .multilineTextAlignment(.center)

            if authService.isSignedIn {
                Button("다시 불러오기") {
                    Task { await eventStore.syncIfSignedIn(auth: authService, force: true) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(eventStore.isSyncing)
            } else if authService.isConfigured {
                Button("Google 계정 연결") {
                    Task { await eventStore.connectGoogle(auth: authService) }
                }
                .buttonStyle(.borderedProminent)
            }

            Button("샘플 일정 넣기") {
                eventStore.loadSampleData()
            }
            .buttonStyle(.bordered)
        }
        .tint(accentColor)
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
    return HomeView(
        settingsStore: SettingsStore(storage: storage, reloadWidgets: {}),
        eventStore: eventStore,
        authService: GoogleAuthService(config: nil)
    )
    .preferredColorScheme(.dark)
}
