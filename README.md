# MyCalendar

Google Calendar 일정을 iPhone 잠금 화면과 홈 화면 위젯에 표시하는 개인용 iOS 앱.

- **개발 환경**: Windows 11 + VS Code (Mac 없음)
- **빌드**: GitHub Actions macOS 러너 + XcodeGen
- **기술**: Swift, SwiftUI, WidgetKit, App Groups, Keychain, Google Calendar API (`calendar.readonly`)
- **대상**: iOS 17.0 이상, iPhone 전용

## 진행 상태

| 단계 | 내용 | 상태 |
|---|---|---|
| 1 | 프로젝트 환경 구축 (XcodeGen, 앱/위젯 타깃, App Groups, GitHub Actions) | 완료 |
| 2 | 기본 앱 (메인 화면, 설정 화면, 데이터 모델) | 대기 |
| 3 | Google Calendar 연동 (OAuth, API, 파싱, 오류 처리) | 대기 |
| 4 | 캘린더 UI (1일, 7일, 월간, 사용자 색상) | 대기 |
| 5 | WidgetKit (잠금 화면, 홈 화면, 데이터 공유, 갱신) | 대기 |
| 6 | 코드 서명 및 iPhone 설치 | 대기 |
| 7 | 안정화 및 문서 정리 | 대기 |

## 프로젝트 구조

```
MyCalendar/
├── .github/workflows/ios-build.yml   # macOS 러너 빌드
├── Config/
│   ├── MyCalendar.entitlements       # 앱: App Groups
│   └── Widget.entitlements           # 위젯: App Groups
├── Sources/
│   ├── App/                          # 메인 앱 (Google 로그인, API 호출, 설정)
│   ├── Widget/                       # 위젯 확장 (App Group 데이터만 읽음)
│   └── Shared/                       # 앱과 위젯이 함께 컴파일하는 코드
│       ├── Models/                   # CalendarEvent, CalendarSettings
│       ├── Storage/                  # AppGroupStorage
│       └── Extensions/               # Color+Hex
├── Tests/MyCalendarTests/            # 단위 테스트
└── project.yml                       # XcodeGen 설정 (.xcodeproj는 CI에서 생성)
```

## 데이터 흐름과 보안

1. 메인 앱이 Google OAuth로 로그인하고 토큰을 **Keychain**에 저장한다.
2. 메인 앱이 Google Calendar API에서 일정을 가져와 `CalendarEvent`로 변환한다.
3. 변환한 일정과 표시 설정만 **App Group** 공유 저장소에 저장한다.
4. 위젯은 App Group 데이터만 읽어 표시한다. 위젯은 토큰이나 네트워크에 접근하지 않는다.
5. 일정이 갱신되면 앱이 `WidgetCenter`로 위젯 갱신을 요청한다.

- 토큰, 인증서, 비밀 키는 저장소에 커밋하지 않는다 (`.gitignore` 참고).
- 서명용 인증서와 프로비저닝 프로파일은 GitHub Actions Secrets로만 전달한다.

## 빌드 방법 (Windows)

Windows에서는 Xcode를 실행할 수 없으므로, 코드를 push하면 GitHub Actions가 macOS에서 빌드한다.

```bash
git add .
git commit -m "변경 내용"
git push
```

빌드 결과는 GitHub 저장소의 **Actions** 탭 → 최근 실행에서 확인한다.

- `MyCalendar-unsigned.ipa`: 서명되지 않은 앱 (그대로는 iPhone에 설치할 수 없음)
- `build-logs`: xcodebuild 전체 로그 (빌드 오류 분석용)

## Windows에서 할 수 없는 작업

| 작업 | 대안 |
|---|---|
| Xcode로 빌드/실행 | GitHub Actions macOS 러너 |
| iOS 시뮬레이터 실행 | CI에서 단위 테스트만 실행, 화면 확인은 실기기 |
| Xcode의 자동 서명 | 6단계에서 결정 (무료 Apple ID + 사이드로딩 도구, 또는 유료 개발자 계정 + TestFlight) |
| SwiftUI 미리보기 | 실기기 설치 후 확인 |
