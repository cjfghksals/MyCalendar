import Foundation
import os

/// 일정 스냅샷을 가져오는 동기화 소스 (테스트에서 대체할 수 있도록 분리)
protocol CalendarSnapshotFetching {
    func fetchSnapshot(now: Date) async throws -> CalendarSnapshot
}

enum GoogleCalendarError: LocalizedError, Equatable {
    case offline
    case unauthorized
    case apiNotEnabled
    case rateLimited
    case forbidden
    case notFound
    case server(Int)
    case unexpectedStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .offline:
            return "인터넷에 연결되어 있지 않습니다. 저장된 일정을 표시합니다."
        case .unauthorized:
            return "Google 인증이 거부되었습니다. 설정에서 계정을 다시 연결해 주세요."
        case .apiNotEnabled:
            return "Google Cloud 프로젝트에서 Google Calendar API가 사용 설정되어 있지 않습니다."
        case .rateLimited:
            return "Google 사용량 한도에 걸렸습니다. 잠시 후 다시 시도해 주세요."
        case .forbidden:
            return "Google Calendar 접근 권한이 없습니다."
        case .notFound:
            return "캘린더를 찾을 수 없습니다."
        case .server(let status):
            return "Google 서버 오류입니다 (\(status)). 잠시 후 다시 시도해 주세요."
        case .unexpectedStatus(let status):
            return "예상하지 못한 응답입니다 (\(status))."
        case .invalidResponse:
            return "Google 응답을 해석하지 못했습니다."
        }
    }
}

/// Google Calendar API v3 호출.
/// 캘린더 목록, 일정별 색상표, 각 캘린더의 일정을 가져와 CalendarSnapshot으로 만든다.
/// 로그에는 개수와 상태 코드만 남기고 토큰·일정 내용은 남기지 않는다.
final class GoogleCalendarService: CalendarSnapshotFetching {
    private let tokenProvider: AccessTokenProvider
    private let session: URLSession
    private let calendar: Calendar

    private static let host = "https://www.googleapis.com"
    /// 잘못된 응답으로 무한히 페이지를 넘기지 않도록 하는 상한
    private static let maxPages = 20
    private static let logger = Logger(subsystem: "com.cjfghksals.mycalendar", category: "GoogleCalendar")
    private static let rateLimitReasons: Set<String> = [
        "rateLimitExceeded", "userRateLimitExceeded", "quotaExceeded", "dailyLimitExceeded",
    ]
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff,
    ]
    /// 경로 한 조각에 쓸 수 있는 문자 (캘린더 ID의 "#", "/" 등은 인코딩)
    private static let pathSegmentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    init(tokenProvider: AccessTokenProvider, session: URLSession = .shared, calendar: Calendar = .current) {
        self.tokenProvider = tokenProvider
        self.session = session
        self.calendar = calendar
    }

    /// 동기화 기간: 지난달 1일 0시부터 2개월 뒤 달의 마지막 날까지 (끝은 3개월 뒤 1일 0시, 미포함)
    static func syncRange(around now: Date, calendar: Calendar) -> DateInterval {
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let end = calendar.date(byAdding: .month, value: 3, to: monthStart) ?? monthStart
        return DateInterval(start: start, end: max(end, start))
    }

    // MARK: - CalendarSnapshotFetching

    func fetchSnapshot(now: Date) async throws -> CalendarSnapshot {
        let range = Self.syncRange(around: now, calendar: calendar)
        let calendars = try await fetchCalendars()
        // 색상표를 못 받아도 캘린더 색상으로 표시할 수 있으므로 동기화는 계속한다.
        let eventColors = (try? await fetchEventColors()) ?? [:]

        var events: [CalendarEvent] = []
        for calendarInfo in calendars {
            do {
                let items = try await fetchEvents(calendarId: calendarInfo.id, range: range)
                events += items.compactMap {
                    GoogleCalendarMapper.event(from: $0, in: calendarInfo, eventColors: eventColors, using: calendar)
                }
            } catch let error as GoogleCalendarError where error == .forbidden || error == .notFound {
                // 일부 구독 캘린더는 일정 목록을 볼 권한이 없을 수 있다 → 그 캘린더만 건너뛴다.
                Self.logger.notice("Skipped a calendar: \(String(describing: error), privacy: .public)")
            }
        }

        Self.logger.info("Fetched \(calendars.count, privacy: .public) calendars, \(events.count, privacy: .public) events")
        return CalendarSnapshot(events: events, calendars: calendars, updatedAt: now)
    }

    // MARK: - API

    /// 기본 캘린더를 맨 앞에 두고 나머지는 이름순
    func fetchCalendars() async throws -> [CalendarInfo] {
        let entries = try await fetchAllPages(
            GoogleCalendarAPI.CalendarListResponse.self,
            path: "/calendar/v3/users/me/calendarList",
            query: [
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "fields", value: "items(id,summary,summaryOverride,backgroundColor,primary),nextPageToken"),
            ]
        )
        return entries.map(GoogleCalendarMapper.calendarInfo(from:)).sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// colorId → "#RRGGBB"
    func fetchEventColors() async throws -> [String: String] {
        let response: GoogleCalendarAPI.ColorsResponse = try await get(
            path: "/calendar/v3/colors",
            query: [URLQueryItem(name: "fields", value: "event")]
        )
        return (response.event ?? [:]).compactMapValues { GoogleCalendarMapper.normalizedHex($0.background) }
    }

    /// 반복 일정은 각 회차로 펼쳐서(singleEvents) 받는다.
    func fetchEvents(calendarId: String, range: DateInterval) async throws -> [GoogleCalendarAPI.Event] {
        let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed) ?? calendarId
        return try await fetchAllPages(
            GoogleCalendarAPI.EventsResponse.self,
            path: "/calendar/v3/calendars/\(encodedId)/events",
            query: [
                URLQueryItem(name: "timeMin", value: GoogleCalendarMapper.rfc3339String(range.start)),
                URLQueryItem(name: "timeMax", value: GoogleCalendarMapper.rfc3339String(range.end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "2500"),
                URLQueryItem(name: "fields", value: "items(id,status,summary,colorId,start(date,dateTime),end(date,dateTime)),nextPageToken"),
            ]
        )
    }

    // MARK: - 요청 처리

    private func fetchAllPages<Response: GooglePagedResponse>(
        _ type: Response.Type,
        path: String,
        query: [URLQueryItem]
    ) async throws -> [Response.Item] {
        var results: [Response.Item] = []
        var pageToken: String?
        for _ in 0..<Self.maxPages {
            var pageQuery = query
            if let pageToken {
                pageQuery.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let page: Response = try await get(path: path, query: pageQuery)
            results += page.items ?? []
            guard let next = page.nextPageToken, !next.isEmpty else { break }
            pageToken = next
        }
        return results
    }

    /// 401이면 토큰을 한 번 강제로 갱신해 다시 시도한다.
    private func get<Response: Decodable>(
        path: String,
        query: [URLQueryItem],
        forceTokenRefresh: Bool = false
    ) async throws -> Response {
        guard var components = URLComponents(string: Self.host) else { throw GoogleCalendarError.invalidResponse }
        components.percentEncodedPath = path
        components.queryItems = query
        // URLComponents는 "+"를 인코딩하지 않아 서버가 공백으로 읽을 수 있으므로 직접 바꾼다.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw GoogleCalendarError.invalidResponse }

        let token = try await tokenProvider.freshAccessToken(forceRefresh: forceTokenRefresh)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw GoogleCalendarError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw GoogleCalendarError.invalidResponse }
        let status = http.statusCode

        switch status {
        case 200..<300:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw GoogleCalendarError.invalidResponse
            }
        case 401 where !forceTokenRefresh:
            return try await get(path: path, query: query, forceTokenRefresh: true)
        case 401:
            throw GoogleCalendarError.unauthorized
        case 403, 429:
            let error = Self.error(forStatus: status, body: data)
            Self.logger.error("Calendar API \(status, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        case 404:
            throw GoogleCalendarError.notFound
        case 500...599:
            Self.logger.error("Calendar API server error \(status, privacy: .public)")
            throw GoogleCalendarError.server(status)
        default:
            Self.logger.error("Calendar API unexpected status \(status, privacy: .public)")
            throw GoogleCalendarError.unexpectedStatus(status)
        }
    }

    /// 403·429 응답 본문의 reason으로 원인을 구분한다.
    static func error(forStatus status: Int, body: Data) -> GoogleCalendarError {
        let reasons = (try? JSONDecoder().decode(GoogleCalendarAPI.ErrorResponse.self, from: body))?
            .error?.errors?.compactMap(\.reason) ?? []
        if status == 429 || reasons.contains(where: rateLimitReasons.contains) {
            return .rateLimited
        }
        let text = String(decoding: body, as: UTF8.self)
        if reasons.contains("accessNotConfigured") || text.contains("SERVICE_DISABLED") {
            return .apiNotEnabled
        }
        return .forbidden
    }
}
