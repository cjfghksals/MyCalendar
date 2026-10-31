import Foundation

/// 앱과 위젯이 함께 쓰는 App Group 공유 저장소.
///
/// 위젯 표시에 필요한 데이터(일정 스냅샷, 표시 설정)만 저장한다.
/// OAuth 토큰 같은 인증 정보는 여기에 저장하지 않고 메인 앱의 Keychain에만 둔다.
struct AppGroupStorage {
    static let shared = AppGroupStorage()

    /// Info.plist의 AppGroupIdentifier 값 (project.yml의 APP_GROUP_ID에서 주입)
    static var groupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    }

    /// App Group 컨테이너를 사용 중인지 여부.
    /// false면 앱 전용 저장소를 쓰는 중이라 위젯과 데이터가 공유되지 않는다 (서명되지 않은 빌드 등).
    let isShared: Bool

    private let directoryURL: URL
    private let defaults: UserDefaults

    private static let snapshotFileName = "calendar-snapshot.json"
    private static let settingsKey = "calendarSettings"

    init(groupIdentifier: String? = AppGroupStorage.groupIdentifier, fileManager: FileManager = .default) {
        if let groupIdentifier,
           let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier),
           let groupDefaults = UserDefaults(suiteName: groupIdentifier) {
            self.init(directoryURL: containerURL, defaults: groupDefaults, isShared: true)
        } else {
            let fallbackURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.init(directoryURL: fallbackURL, defaults: .standard, isShared: false)
        }
    }

    /// 저장 위치를 직접 지정한다 (테스트용).
    init(directoryURL: URL, defaults: UserDefaults, isShared: Bool = false) {
        self.directoryURL = directoryURL
        self.defaults = defaults
        self.isShared = isShared
    }

    private var snapshotURL: URL {
        directoryURL.appendingPathComponent(Self.snapshotFileName)
    }

    // MARK: - 일정 스냅샷

    func loadSnapshot() -> CalendarSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(CalendarSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: CalendarSnapshot) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        // 잠금 화면 위젯이 기기가 잠긴 상태에서도 읽을 수 있도록 "첫 잠금 해제 이후" 보호 등급을 쓴다.
        try data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clearSnapshot() throws {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return }
        try FileManager.default.removeItem(at: snapshotURL)
    }

    // MARK: - 표시 설정

    func loadSettings() -> CalendarSettings {
        guard let data = defaults.data(forKey: Self.settingsKey),
              let settings = try? JSONDecoder().decode(CalendarSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func saveSettings(_ settings: CalendarSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: Self.settingsKey)
    }
}
