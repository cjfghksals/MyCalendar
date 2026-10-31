import Foundation
import Observation
import WidgetKit

/// 일정 스냅샷(일정 + 캘린더 목록)을 관리한다.
/// 저장하면 App Group에 기록하고 위젯 갱신을 요청한다.
/// Google Calendar 동기화 결과도 이곳을 거쳐 저장된다.
@MainActor
@Observable
final class EventStore {
    /// 앱을 다시 열었을 때 이 시간보다 오래됐으면 자동으로 동기화한다.
    static let autoSyncInterval: TimeInterval = 15 * 60

    private(set) var snapshot: CalendarSnapshot?
    private(set) var lastError: String?
    private(set) var isSyncing = false

    @ObservationIgnored private let storage: AppGroupStorage
    @ObservationIgnored private let reloadWidgets: () -> Void

    init(
        storage: AppGroupStorage = .shared,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.storage = storage
        self.reloadWidgets = reloadWidgets
        self.snapshot = storage.loadSnapshot()
    }

    var events: [CalendarEvent] { snapshot?.events ?? [] }
    var calendars: [CalendarInfo] { snapshot?.calendars ?? [] }
    var hasData: Bool { snapshot != nil }

    /// App Group으로 위젯과 데이터를 공유하고 있는지 여부 (서명되지 않은 빌드에서는 false)
    var isSharedWithWidget: Bool { storage.isShared }

    /// 숨기지 않은 캘린더의 일정
    func visibleEvents(settings: CalendarSettings) -> [CalendarEvent] {
        events.filter { !settings.hiddenCalendarIds.contains($0.calendarId) }
    }

    func reload() {
        snapshot = storage.loadSnapshot()
    }

    func save(_ newSnapshot: CalendarSnapshot) {
        do {
            try storage.saveSnapshot(newSnapshot)
            snapshot = newSnapshot
            lastError = nil
        } catch {
            lastError = "일정 저장 실패: \(error.localizedDescription)"
        }
        reloadWidgets()
    }

    func loadSampleData(now: Date = .now) {
        save(.sample(relativeTo: now))
    }

    func clear() {
        do {
            try storage.clearSnapshot()
            snapshot = nil
            lastError = nil
        } catch {
            lastError = "일정 삭제 실패: \(error.localizedDescription)"
        }
        reloadWidgets()
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: - 동기화

    func needsSync(now: Date = .now) -> Bool {
        guard let updatedAt = snapshot?.updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) >= Self.autoSyncInterval
    }

    /// 새 일정을 받아 저장한다. 실패하면 기존 일정을 유지하고 lastError에 이유를 남긴다.
    func sync(with fetcher: CalendarSnapshotFetching, now: Date = .now) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await fetcher.fetchSnapshot(now: now)
            save(newSnapshot)
        } catch {
            lastError = Self.message(for: error)
        }
    }

    /// Google 계정이 연결돼 있을 때만 동기화한다. force가 false면 최근에 갱신했을 때 건너뛴다.
    func syncIfSignedIn(auth: GoogleAuthService, force: Bool, now: Date = .now) async {
        guard auth.isSignedIn, force || needsSync(now: now) else { return }
        await sync(with: GoogleCalendarService(tokenProvider: auth), now: now)
    }

    /// Google 로그인 후 바로 일정을 불러온다. 사용자가 로그인 창을 닫으면 아무것도 하지 않는다.
    func connectGoogle(auth: GoogleAuthService) async {
        do {
            try await auth.signIn()
        } catch GoogleAuthError.cancelled {
            return
        } catch {
            lastError = Self.message(for: error)
            return
        }
        await syncIfSignedIn(auth: auth, force: true)
    }

    /// 연결을 해제하고 그 계정에서 받은 일정도 지운다.
    func disconnectGoogle(auth: GoogleAuthService) async {
        await auth.signOut()
        clear()
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "일정을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요."
    }
}
