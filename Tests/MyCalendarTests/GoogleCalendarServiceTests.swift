import XCTest
@testable import MyCalendar

/// 네트워크 대신 미리 정한 응답을 돌려주는 URLProtocol
private final class StubURLProtocol: URLProtocol {
    /// 요청을 받아 (상태 코드, 본문)을 돌려준다.
    static var handler: ((URLRequest) -> (Int, String))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 강제 갱신 횟수를 세는 가짜 토큰 제공자
private final class MockTokenProvider: AccessTokenProvider {
    private(set) var forcedRefreshCount = 0

    func freshAccessToken(forceRefresh: Bool) async throws -> String {
        if forceRefresh { forcedRefreshCount += 1 }
        return "token-\(forcedRefreshCount)"
    }
}

final class GoogleCalendarServiceTests: XCTestCase {
    private var tokenProvider: MockTokenProvider!
    private var service: GoogleCalendarService!

    private var seoul: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        tokenProvider = MockTokenProvider()
        service = GoogleCalendarService(tokenProvider: tokenProvider, session: URLSession(configuration: configuration), calendar: seoul)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.requests = []
        super.tearDown()
    }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        guard let url = request.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    func testCalendarListFollowsPagesAndPutsPrimaryFirst() async throws {
        StubURLProtocol.handler = { request in
            if self.query(request, "pageToken") == "page2" {
                return (200, #"{"items":[{"id":"me@example.com","summary":"나","primary":true}]}"#)
            }
            return (200, #"{"items":[{"id":"b@example.com","summary":"B"},{"id":"a@example.com","summary":"A"}],"nextPageToken":"page2"}"#)
        }

        let calendars = try await service.fetchCalendars()

        XCTAssertEqual(calendars.map(\.id), ["me@example.com", "a@example.com", "b@example.com"])
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer token-0")
    }

    func testEventsRequestEncodesCalendarIDAndQuery() async throws {
        StubURLProtocol.handler = { _ in (200, #"{"items":[]}"#) }
        let range = GoogleCalendarService.syncRange(around: Date(timeIntervalSince1970: 1_793_000_000), calendar: seoul)

        _ = try await service.fetchEvents(calendarId: "ko.south_korea#holiday@group.v.calendar.google.com", range: range)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.absoluteString.contains("/calendar/v3/calendars/ko.south_korea%23holiday@group.v.calendar.google.com/events"),
                      url.absoluteString)
        XCTAssertEqual(query(request, "singleEvents"), "true")
        XCTAssertEqual(query(request, "orderBy"), "startTime")
        XCTAssertEqual(query(request, "timeMin"), GoogleCalendarMapper.rfc3339String(range.start))
        XCTAssertTrue(query(request, "timeMin")?.hasSuffix("Z") ?? false)
    }

    func testUnauthorizedResponseRefreshesTokenOnceAndRetries() async throws {
        StubURLProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer token-0" {
                return (401, #"{"error":{"code":401}}"#)
            }
            return (200, #"{"items":[{"id":"me@example.com","primary":true}]}"#)
        }

        let calendars = try await service.fetchCalendars()

        XCTAssertEqual(calendars.count, 1)
        XCTAssertEqual(tokenProvider.forcedRefreshCount, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testRepeatedUnauthorizedThrows() async {
        StubURLProtocol.handler = { _ in (401, #"{"error":{"code":401}}"#) }

        do {
            _ = try await service.fetchCalendars()
            XCTFail("401이 계속되면 오류가 나야 한다")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .unauthorized)
            XCTAssertEqual(tokenProvider.forcedRefreshCount, 1)
        }
    }

    func testRateLimitIsReported() async {
        StubURLProtocol.handler = { _ in (403, #"{"error":{"code":403,"errors":[{"reason":"userRateLimitExceeded"}]}}"#) }

        do {
            _ = try await service.fetchCalendars()
            XCTFail("사용량 제한 오류가 나야 한다")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .rateLimited)
        }
    }

    func testFetchSnapshotCombinesCalendarsColorsAndEvents() async throws {
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/users/me/calendarList") {
                // 본문에 "#가 들어 있으므로 ##"..."## 로 감싼다.
                return (200, ##"{"items":[{"id":"me@example.com","summary":"나","backgroundColor":"#16a765","primary":true},{"id":"secret@example.com","summary":"비공개"}]}"##)
            }
            if path.hasSuffix("/colors") {
                return (200, ##"{"event":{"5":{"background":"#fbd75b","foreground":"#1d1d1d"}}}"##)
            }
            if path.contains("secret@example.com") {
                // 일정 목록 권한이 없는 캘린더는 건너뛴다.
                return (403, #"{"error":{"code":403,"errors":[{"reason":"forbidden"}]}}"#)
            }
            return (200, """
            {"items":[
              {"id":"a","summary":"점심","colorId":"5","start":{"dateTime":"2026-11-02T12:00:00+09:00"},"end":{"dateTime":"2026-11-02T13:00:00+09:00"}},
              {"id":"b","status":"cancelled","start":{"date":"2026-11-03"},"end":{"date":"2026-11-04"}},
              {"id":"c","summary":"휴가","start":{"date":"2026-11-05"},"end":{"date":"2026-11-06"}}
            ]}
            """)
        }
        let now = Date(timeIntervalSince1970: 1_793_000_000)

        let snapshot = try await service.fetchSnapshot(now: now)

        XCTAssertEqual(snapshot.updatedAt, now)
        XCTAssertEqual(snapshot.calendars.map(\.id), ["me@example.com", "secret@example.com"])
        XCTAssertEqual(snapshot.events.map(\.title), ["점심", "휴가"])
        XCTAssertEqual(snapshot.events.first?.colorHex, "#FBD75B")
        XCTAssertEqual(snapshot.events.last?.colorHex, "#16A765")
        XCTAssertEqual(snapshot.events.last?.isAllDay, true)
    }

    func testOfflineErrorIsMapped() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineURLProtocol.self]
        let offlineService = GoogleCalendarService(tokenProvider: tokenProvider, session: URLSession(configuration: configuration))

        do {
            _ = try await offlineService.fetchCalendars()
            XCTFail("오프라인 오류가 나야 한다")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .offline)
        }
    }
}

/// 항상 인터넷 연결 없음 오류를 내는 URLProtocol
private final class OfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
