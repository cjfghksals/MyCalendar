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
| 2 | 기본 앱 (메인 화면, 설정 화면, 데이터 모델) | 완료 |
| 3 | Google Calendar 연동 (OAuth, API, 파싱, 오류 처리) | 진행 중 (실제 로그인 확인은 6단계 설치 후) |
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
│   ├── App/                          # 메인 앱
│   │   ├── Services/                 # GoogleAuthService(로그인), GoogleCalendarService(API), KeychainStore
│   │   ├── Stores/                   # SettingsStore(설정), EventStore(일정·동기화) - 저장 + 위젯 갱신 요청
│   │   └── Views/                    # HomeView(메인), CalendarView(날짜별 목록), SettingsView(설정)
│   ├── Widget/                       # 위젯 확장 (App Group 데이터만 읽음)
│   └── Shared/                       # 앱과 위젯이 함께 컴파일하는 코드
│       ├── Models/                   # CalendarEvent, CalendarInfo, CalendarSettings, DaySection
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
- Google 로그인은 [AppAuth](https://github.com/openid/AppAuth-iOS)(PKCE, 시스템 인증 창)로 하고, 요청 권한은 `calendar.readonly` 하나다.
- 로그에는 상태 코드와 개수만 남기고 토큰·일정 내용은 남기지 않는다.

## Google Cloud 설정 (처음 한 번, 웹 브라우저에서)

비용은 없고 Mac도 필요 없다. 메뉴 이름은 한국어 화면 기준이며 괄호 안은 영어 화면 이름이다.

1. **프로젝트 만들기**: [Google Cloud Console](https://console.cloud.google.com/) 위쪽 프로젝트 선택 → **새 프로젝트** → 이름 `MyCalendar` → 만들기
2. **Calendar API 켜기**: 메뉴 → **API 및 서비스 > 라이브러리** (APIs & Services > Library) → `Google Calendar API` 검색 → **사용** (Enable)
3. **앱 정보 등록**: 메뉴 → **Google 인증 플랫폼 > 브랜딩** (Google Auth platform > Branding) → **시작하기** (Get started)
   - 앱 이름 `MyCalendar`, 사용자 지원 이메일: 본인 Gmail → 다음
   - 대상: **외부** (External) → 다음
   - 연락처 이메일: 본인 Gmail → 다음 → 정책 동의 → 계속 → **만들기**
4. **권한 추가**: **데이터 액세스** (Data Access) → **범위 추가 또는 삭제** → `.../auth/calendar.readonly` 선택 → 업데이트 → **저장**
5. **게시 상태**: **대상** (Audience) → **앱 게시** (Publish app) → 확인
   - "테스트" 상태로 두면 로그인이 7일마다 만료된다. 게시하면 만료가 없고, 대신 첫 로그인 때
     "Google에서 확인하지 않은 앱" 경고가 나온다 → **고급** → **MyCalendar(으)로 이동**.
   - 사용자 100명 미만의 개인용 앱은 Google 검증 없이 사용할 수 있다.
6. **iOS 클라이언트 만들기**: **클라이언트** (Clients) → **클라이언트 만들기** (Create client)
   - 애플리케이션 유형: **iOS**, 이름: `MyCalendar iOS`, 번들 ID: `com.cjfghksals.mycalendar` → 만들기
   - 표시되는 **클라이언트 ID** (`숫자-문자.apps.googleusercontent.com`)를 복사한다.
7. **GitHub Secret 등록**: 저장소 **Settings > Secrets and variables > Actions > New repository secret**
   - Name: `GOOGLE_IOS_CLIENT_ID`, Secret: 복사한 클라이언트 ID

Secret을 등록한 뒤의 빌드부터 Google 로그인이 켜진다. 빌드 요약(Actions 실행 화면)의
`Google OAuth client` 항목이 `configured`면 정상이다. iOS 클라이언트 ID는 앱 안에 들어가는 값이라
비밀번호 같은 비밀 값은 아니지만, 소스 코드에는 넣지 않고 Secret으로만 전달한다.

## 빌드 방법 (Windows)

Windows에서는 Xcode를 실행할 수 없으므로, 코드를 push하면 GitHub Actions가 macOS에서 빌드한다.

```bash
git add .
git commit -m "변경 내용"
git push
```

빌드 결과는 GitHub 저장소의 **Actions** 탭 → 최근 실행에서 확인한다.

- `MyCalendar-unsigned.ipa`: 서명되지 않은 앱 (그대로는 iPhone에 설치할 수 없음)
- `screenshots`: iPhone 17 시뮬레이터에서 찍은 1일·7일·한 달·설정 화면 (샘플 일정, 한국어)
- `build-logs`: xcodebuild 전체 로그 (빌드 오류 분석용)

> `.github/workflows/` 파일을 바꾼 push가 `workflow scope` 오류로 거부되면,
> Windows에 저장된 GitHub 인증에 workflow 권한이 없는 것이다. 코드·문서 push는 영향이 없다.

## Windows에서 할 수 없는 작업

| 작업 | 대안 |
|---|---|
| Xcode로 빌드/실행 | GitHub Actions macOS 러너 |
| iOS 시뮬레이터 실행 | CI에서 단위 테스트만 실행, 화면 확인은 실기기 |
| Xcode의 자동 서명 | 6단계에서 결정 (무료 Apple ID + 사이드로딩 도구, 또는 유료 개발자 계정 + TestFlight) |
| SwiftUI 미리보기 | 실기기 설치 후 확인 |
