import SwiftUI

@main
struct MyCalendarApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var settingsStore: SettingsStore
    @State private var eventStore: EventStore
    @State private var authService: GoogleAuthService
    private let showSettingsOnLaunch: Bool

    init() {
        #if DEBUG
        if let config = ScreenshotConfig.current {
            let stores = config.makeStores()
            _settingsStore = State(initialValue: stores.settings)
            _eventStore = State(initialValue: stores.events)
            // 스크린샷에서는 Google 연결을 쓰지 않는다.
            _authService = State(initialValue: GoogleAuthService(config: nil))
            showSettingsOnLaunch = config.screen == .settings
            return
        }
        #endif
        _settingsStore = State(initialValue: SettingsStore())
        _eventStore = State(initialValue: EventStore())
        _authService = State(initialValue: GoogleAuthService())
        showSettingsOnLaunch = false
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                settingsStore: settingsStore,
                eventStore: eventStore,
                authService: authService,
                showSettingsOnLaunch: showSettingsOnLaunch
            )
            .preferredColorScheme(settingsStore.settings.appearance.colorScheme)
            .tint(Color(hex: settingsStore.settings.theme.accentHex, fallback: .accentColor))
            .onChange(of: scenePhase, initial: true) { _, phase in
                // 앱이 앞으로 나올 때 마지막 동기화가 오래됐으면 자동으로 갱신한다.
                guard phase == .active else { return }
                Task { await eventStore.syncIfSignedIn(auth: authService, force: false) }
            }
        }
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

#if DEBUG
/// CI에서 시뮬레이터 스크린샷을 찍기 위한 실행 옵션 (Debug 빌드 전용).
/// 실제 저장소를 건드리지 않도록 임시 저장소와 샘플 데이터를 쓴다.
/// 예: xcrun simctl launch booted com.cjfghksals.mycalendar -screenshotScreen calendar -screenshotMode weekly
struct ScreenshotConfig {
    enum Screen: String {
        case calendar
        case settings
    }

    let screen: Screen
    let displayMode: DisplayMode

    /// 실행 인자(-screenshotScreen, -screenshotMode)를 읽는다. 없으면 nil
    static var current: ScreenshotConfig? {
        let arguments = UserDefaults.standard
        guard let screen = arguments.string(forKey: "screenshotScreen").flatMap(Screen.init(rawValue:)) else {
            return nil
        }
        let mode = arguments.string(forKey: "screenshotMode").flatMap(DisplayMode.init(rawValue:)) ?? .daily
        return ScreenshotConfig(screen: screen, displayMode: mode)
    }

    @MainActor
    func makeStores() -> (settings: SettingsStore, events: EventStore) {
        let suiteName = "MyCalendar.screenshot"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        try? FileManager.default.removeItem(at: directory)
        let storage = AppGroupStorage(directoryURL: directory, defaults: defaults)

        let settingsStore = SettingsStore(storage: storage, reloadWidgets: {})
        settingsStore.update { $0.displayMode = displayMode }
        let eventStore = EventStore(storage: storage, reloadWidgets: {})
        eventStore.loadSampleData()
        return (settingsStore, eventStore)
    }
}
#endif
