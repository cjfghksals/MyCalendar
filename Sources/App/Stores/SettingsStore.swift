import Observation
import SwiftUI
import WidgetKit

/// 표시 설정을 관리한다.
/// 모든 변경은 update(_:)를 거치며, 값이 바뀌면 App Group 저장소에 저장하고 위젯 갱신을 요청한다.
@Observable
final class SettingsStore {
    private(set) var settings: CalendarSettings
    private(set) var lastError: String?

    @ObservationIgnored private let storage: AppGroupStorage
    @ObservationIgnored private let reloadWidgets: () -> Void
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(
        storage: AppGroupStorage = .shared,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.storage = storage
        self.reloadWidgets = reloadWidgets
        self.settings = storage.loadSettings()
    }

    // MARK: - 변경

    func update(_ change: (inout CalendarSettings) -> Void) {
        var newSettings = settings
        change(&newSettings)
        guard newSettings != settings else { return }
        settings = newSettings
        persist()
    }

    /// 화면의 Picker, Toggle 등에 연결할 Binding
    func binding<Value>(_ keyPath: WritableKeyPath<CalendarSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    func applyAppearance(_ mode: AppearanceMode) {
        update { $0.applyAppearance(mode) }
    }

    func resetTheme() {
        update { $0.theme = $0.appearance.defaultTheme }
    }

    func isCalendarVisible(_ calendarId: String) -> Bool {
        !settings.hiddenCalendarIds.contains(calendarId)
    }

    func setCalendar(_ calendarId: String, visible: Bool) {
        update { settings in
            if visible {
                settings.hiddenCalendarIds.remove(calendarId)
            } else {
                settings.hiddenCalendarIds.insert(calendarId)
            }
        }
    }

    /// 캘린더 색상을 지정한다. nil이면 Google 캘린더 색상으로 되돌린다.
    func setColorOverride(_ hex: String?, forCalendar calendarId: String) {
        update { $0.calendarColorOverrides[calendarId] = hex }
    }

    // MARK: - 저장

    private func persist() {
        do {
            try storage.saveSettings(settings)
            lastError = nil
        } catch {
            lastError = "설정 저장 실패: \(error.localizedDescription)"
        }
        scheduleWidgetReload()
    }

    /// 색상 선택기를 움직이는 동안 갱신 요청이 몰리지 않도록 마지막 변경 후 0.5초 뒤에 한 번만 요청한다.
    private func scheduleWidgetReload() {
        reloadTask?.cancel()
        let reloadWidgets = self.reloadWidgets
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            reloadWidgets()
        }
    }
}
