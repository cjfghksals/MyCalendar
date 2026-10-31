import SwiftUI

/// 설정 화면: Google 계정, 표시 방식, 테마 색상, 일정 표시, 캘린더별 표시·색상, 개발용 데이터
struct SettingsView: View {
    let settingsStore: SettingsStore
    let eventStore: EventStore
    let authService: GoogleAuthService

    private var settings: CalendarSettings { settingsStore.settings }

    var body: some View {
        Form {
            accountSection
            displaySection
            themeSection
            eventDisplaySection
            calendarSection
            developerSection
            aboutSection
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Google 계정

    private var accountSection: some View {
        Section {
            if !authService.isConfigured {
                Text(GoogleAuthError.notConfigured.errorDescription ?? "")
                    .foregroundStyle(.secondary)
            } else if authService.isSignedIn {
                // 기본 캘린더의 ID가 계정 이메일이다 (이메일 권한을 따로 요청하지 않음).
                LabeledContent("계정", value: eventStore.calendars.first(where: \.isPrimary)?.id ?? "연결됨")
                if let updatedAt = eventStore.snapshot?.updatedAt {
                    LabeledContent("마지막 동기화", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Button {
                    Task { await eventStore.syncIfSignedIn(auth: authService, force: true) }
                } label: {
                    HStack {
                        Text("지금 동기화")
                        if eventStore.isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(eventStore.isSyncing)
                Button("연결 해제", role: .destructive) {
                    Task { await eventStore.disconnectGoogle(auth: authService) }
                }
            } else {
                Button("Google 계정 연결") {
                    Task { await eventStore.connectGoogle(auth: authService) }
                }
            }

            if let message = eventStore.lastError {
                Text(message)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Google 계정")
        } footer: {
            Text("일정 읽기 권한(calendar.readonly)만 요청합니다. 로그인 정보는 이 iPhone의 Keychain에만 저장하고 위젯과 공유하지 않습니다. 연결을 해제하면 받아 둔 일정도 지웁니다.")
        }
    }

    // MARK: - 표시 방식

    private var displaySection: some View {
        Section {
            Picker("보기", selection: settingsStore.binding(\.displayMode)) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("표시 방식")
        } footer: {
            Text("메인 화면과 위젯에 기본으로 보여줄 기간입니다.")
        }
    }

    // MARK: - 테마

    private var themeSection: some View {
        Section {
            Picker("모드", selection: appearanceBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            ColorSettingRow(title: "배경색", hex: settingsStore.binding(\.theme.backgroundHex))
            ColorSettingRow(title: "글자색", hex: settingsStore.binding(\.theme.textHex))
            ColorSettingRow(title: "보조 글자색", hex: settingsStore.binding(\.theme.secondaryTextHex))
            ColorSettingRow(title: "강조색", hex: settingsStore.binding(\.theme.accentHex))

            Button("테마 기본값으로 되돌리기") {
                settingsStore.resetTheme()
            }
            .disabled(!settings.isThemeCustomized)
        } header: {
            Text("테마")
        } footer: {
            Text("다크·라이트를 바꾸면 그 모드의 기본 색상으로 바뀝니다. 색상은 HEX 코드(#RRGGBB)로 직접 입력할 수도 있습니다.")
        }
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { settingsStore.settings.appearance },
            set: { settingsStore.applyAppearance($0) }
        )
    }

    // MARK: - 일정 표시

    private var eventDisplaySection: some View {
        Section {
            Toggle("일정 제목 표시", isOn: settingsStore.binding(\.showEventTitles))
            Stepper(value: settingsStore.binding(\.maxEventsPerDay), in: CalendarSettings.maxEventsPerDayRange) {
                LabeledContent("날짜별 최대 일정 수", value: "\(settings.maxEventsPerDay)개")
            }
        } header: {
            Text("일정 표시")
        } footer: {
            Text("한 달 보기와 위젯에서 날짜마다 보여줄 일정 수입니다. 넘치는 일정은 \"+N\"으로 표시합니다.")
        }
    }

    // MARK: - 캘린더

    private var calendarSection: some View {
        Section {
            if eventStore.calendars.isEmpty {
                Text("Google 계정을 연결하면 캘린더 목록이 표시됩니다.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(eventStore.calendars) { calendar in
                    CalendarSettingRow(
                        calendar: calendar,
                        isVisible: visibilityBinding(for: calendar),
                        color: colorBinding(for: calendar),
                        isColorCustomized: settings.calendarColorOverrides[calendar.id] != nil,
                        onResetColor: { settingsStore.setColorOverride(nil, forCalendar: calendar.id) }
                    )
                }
            }
        } header: {
            Text("캘린더")
        } footer: {
            Text("끈 캘린더의 일정은 앱과 위젯에 표시하지 않습니다. 색상을 바꾸면 그 캘린더의 모든 일정에 적용됩니다.")
        }
    }

    private func visibilityBinding(for calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: { settingsStore.isCalendarVisible(calendar.id) },
            set: { settingsStore.setCalendar(calendar.id, visible: $0) }
        )
    }

    private func colorBinding(for calendar: CalendarInfo) -> Binding<Color> {
        Binding(
            get: {
                Color(hex: settingsStore.settings.calendarColorOverrides[calendar.id] ?? calendar.colorHex, fallback: .gray)
            },
            set: { newColor in
                if let hex = newColor.hexString() {
                    settingsStore.setColorOverride(hex, forCalendar: calendar.id)
                }
            }
        )
    }

    // MARK: - 개발용 데이터

    private var developerSection: some View {
        Section {
            LabeledContent("위젯과 데이터 공유", value: eventStore.isSharedWithWidget ? "연결됨" : "사용 불가 (서명 필요)")
            LabeledContent("저장된 일정", value: "\(eventStore.events.count)개")
            if let updatedAt = eventStore.snapshot?.updatedAt {
                LabeledContent("마지막 갱신", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Button("샘플 일정 저장") {
                eventStore.loadSampleData()
            }
            Button("저장된 일정 지우기", role: .destructive) {
                eventStore.clear()
            }
            .disabled(!eventStore.hasData)

            if let message = settingsStore.lastError {
                Text(message)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("개발용 데이터")
        } footer: {
            Text("Google Calendar 연동 전에 화면과 위젯을 확인하기 위한 임시 기능입니다.")
        }
    }

    // MARK: - 정보

    private var aboutSection: some View {
        Section("정보") {
            LabeledContent("버전", value: Self.appVersion)
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
}

// MARK: - 행 구성 요소

/// 색상 선택기와 HEX 입력칸이 함께 있는 행
private struct ColorSettingRow: View {
    let title: String
    @Binding var hex: String

    // 구조체 자체가 private이므로 아래 상태에는 private을 붙이지 않는다 (자동 생성 이니셜라이저 접근 수준 유지).
    @State var draft = ""
    @FocusState var isEditing: Bool

    var body: some View {
        HStack(spacing: 12) {
            ColorPicker(title, selection: colorBinding, supportsOpacity: false)
            TextField("#RRGGBB", text: $draft)
                .font(.body.monospaced())
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .frame(width: 100)
                .focused($isEditing)
                .onSubmit(commitDraft)
        }
        .onAppear { draft = hex }
        .onChange(of: hex) { _, newValue in
            if !isEditing { draft = newValue }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { commitDraft() }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: hex, fallback: .gray) },
            set: { newColor in
                if let newHex = newColor.hexString() { hex = newHex }
            }
        )
    }

    /// 올바른 HEX면 "#RRGGBB"로 정리해 저장하고, 아니면 이전 값으로 되돌린다.
    private func commitDraft() {
        if let components = HexColor.components(from: draft) {
            hex = HexColor.string(red: components.red, green: components.green, blue: components.blue, alpha: components.alpha)
        }
        draft = hex
    }
}

/// 캘린더 표시 여부와 색상을 정하는 행
private struct CalendarSettingRow: View {
    let calendar: CalendarInfo
    @Binding var isVisible: Bool
    @Binding var color: Color
    let isColorCustomized: Bool
    let onResetColor: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ColorPicker(calendar.name, selection: $color, supportsOpacity: false)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.name)
                if calendar.isPrimary {
                    Text("기본 캘린더")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isColorCustomized {
                Button("색상 초기화", systemImage: "arrow.uturn.backward", action: onResetColor)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Toggle(calendar.name, isOn: $isVisible)
                .labelsHidden()
        }
    }
}
