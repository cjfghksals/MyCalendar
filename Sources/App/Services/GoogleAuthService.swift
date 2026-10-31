import AppAuth
import Foundation
import Observation
import UIKit
import os

/// Google Calendar API를 호출할 때 필요한 액세스 토큰을 제공한다.
protocol AccessTokenProvider: AnyObject {
    /// 유효한 액세스 토큰. 만료됐으면 갱신한다. forceRefresh가 true면 만료 전이라도 갱신한다.
    func freshAccessToken(forceRefresh: Bool) async throws -> String
}

/// Info.plist의 GoogleClientID(project.yml의 GOOGLE_IOS_CLIENT_ID)로 만든 OAuth 설정
struct GoogleOAuthConfig: Equatable {
    static let clientIDSuffix = ".apps.googleusercontent.com"

    /// 예: 1234-abcd.apps.googleusercontent.com
    let clientID: String
    /// 예: com.googleusercontent.apps.1234-abcd:/oauth2redirect
    let redirectURL: URL

    /// iOS용 OAuth 클라이언트 ID 형식이 아니면 nil
    init?(clientID: String?) {
        guard let clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines),
              clientID.hasSuffix(Self.clientIDSuffix) else {
            return nil
        }
        let prefix = clientID.dropLast(Self.clientIDSuffix.count)
        guard !prefix.isEmpty,
              let redirectURL = URL(string: "com.googleusercontent.apps.\(prefix):/oauth2redirect") else {
            return nil
        }
        self.clientID = clientID
        self.redirectURL = redirectURL
    }

    static var fromInfoPlist: GoogleOAuthConfig? {
        GoogleOAuthConfig(clientID: Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)
    }
}

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case noPresenter
    case cancelled
    case signedOut
    case sessionExpired
    case failed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google 클라이언트 ID가 설정되지 않은 빌드입니다. README의 Google Cloud 설정을 확인하세요."
        case .noPresenter:
            return "로그인 화면을 띄울 수 없습니다. 앱을 다시 열어 주세요."
        case .cancelled:
            return "로그인을 취소했습니다."
        case .signedOut:
            return "Google 계정이 연결되어 있지 않습니다."
        case .sessionExpired:
            return "Google 로그인이 만료되었습니다. 설정에서 다시 연결해 주세요."
        case .failed:
            return "Google 로그인에 실패했습니다. 잠시 후 다시 시도해 주세요."
        }
    }
}

/// Google OAuth 2.0 로그인 (AppAuth, PKCE, 시스템 인증 세션 사용).
/// 요청 권한은 calendar.readonly 하나이며, 토큰(OIDAuthState)은 Keychain에만 저장한다.
/// 위젯은 토큰에 접근하지 않는다.
@MainActor
@Observable
final class GoogleAuthService: AccessTokenProvider {
    static let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"

    let config: GoogleOAuthConfig?
    private(set) var isSignedIn: Bool

    var isConfigured: Bool { config != nil }

    @ObservationIgnored private var authState: OIDAuthState?
    @ObservationIgnored private var currentFlow: OIDExternalUserAgentSession?
    @ObservationIgnored private let secureStore: SecureStore
    @ObservationIgnored private let session: URLSession

    private static let authStateKey = "googleAuthState"
    private static let logger = Logger(subsystem: "com.cjfghksals.mycalendar", category: "GoogleAuth")
    private static let serviceConfiguration = OIDServiceConfiguration(
        authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
    )

    init(config: GoogleOAuthConfig? = .fromInfoPlist, secureStore: SecureStore = KeychainStore(), session: URLSession = .shared) {
        self.config = config
        self.secureStore = secureStore
        self.session = session
        let restored = config == nil ? nil : Self.loadAuthState(from: secureStore)
        self.authState = restored
        self.isSignedIn = restored?.isAuthorized ?? false
    }

    // MARK: - 로그인 / 로그아웃

    /// 시스템 인증 창으로 Google 로그인을 진행한다. 사용자가 닫으면 GoogleAuthError.cancelled
    func signIn() async throws {
        guard let config else { throw GoogleAuthError.notConfigured }
        guard let presenter = UIApplication.shared.topViewController else { throw GoogleAuthError.noPresenter }

        // 이 생성자는 state와 PKCE(S256)를 자동으로 만든다. iOS 클라이언트에는 client secret이 없다.
        let request = OIDAuthorizationRequest(
            configuration: Self.serviceConfiguration,
            clientId: config.clientID,
            scopes: [Self.calendarScope],
            redirectURL: config.redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        let newState: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            currentFlow = OIDAuthState.authState(byPresenting: request, presenting: presenter) { authState, error in
                if let authState {
                    continuation.resume(returning: authState)
                } else {
                    continuation.resume(throwing: Self.mapError(error))
                }
            }
        }
        currentFlow = nil

        authState = newState
        try save(newState)
        isSignedIn = true
        Self.logger.info("Google sign-in completed")
    }

    /// 로컬 토큰을 지우고 Google에 권한 해제를 요청한다.
    func signOut() async {
        let refreshToken = authState?.refreshToken
        clearLocalState()
        if let refreshToken {
            await revoke(refreshToken)
        }
        Self.logger.info("Google sign-out completed")
    }

    // MARK: - 토큰

    func freshAccessToken(forceRefresh: Bool) async throws -> String {
        guard let authState else { throw GoogleAuthError.signedOut }
        if forceRefresh {
            authState.setNeedsTokenRefresh()
        }

        do {
            let token: String = try await withCheckedThrowingContinuation { continuation in
                authState.performAction(freshTokens: { accessToken, _, error in
                    if let accessToken {
                        continuation.resume(returning: accessToken)
                    } else {
                        continuation.resume(throwing: error ?? GoogleAuthError.failed)
                    }
                })
            }
            // 토큰이 갱신됐을 수 있으므로 다시 저장한다.
            try? save(authState)
            return token
        } catch {
            if Self.isInvalidGrant(error) {
                // 사용자가 권한을 해제했거나 토큰이 만료됨 → 다시 로그인해야 한다.
                Self.logger.notice("Refresh token rejected; signing out locally")
                clearLocalState()
                throw GoogleAuthError.sessionExpired
            }
            throw Self.mapError(error)
        }
    }

    // MARK: - 내부 처리

    private func save(_ state: OIDAuthState) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
        try secureStore.set(data, forKey: Self.authStateKey)
    }

    private static func loadAuthState(from store: SecureStore) -> OIDAuthState? {
        guard let data = try? store.data(forKey: authStateKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
    }

    private func clearLocalState() {
        authState = nil
        isSignedIn = false
        try? secureStore.removeValue(forKey: Self.authStateKey)
    }

    private func revoke(_ token: String) async {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        _ = try? await session.data(for: request)
    }

    private static func isInvalidGrant(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == OIDOAuthTokenErrorDomain
            && nsError.code == OIDErrorCodeOAuthToken.invalidGrant.rawValue
    }

    /// AppAuth 오류를 사용자에게 보여줄 오류로 바꾼다 (원문에는 토큰이 없지만 로그에는 코드만 남긴다).
    private static func mapError(_ error: Error?) -> GoogleAuthError {
        guard let nsError = error as NSError? else { return .failed }
        if nsError.domain == OIDGeneralErrorDomain,
           nsError.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue {
            return .cancelled
        }
        logger.error("Google auth error: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
        return .failed
    }
}

private extension UIApplication {
    /// 로그인 창을 띄울 현재 맨 위 화면
    var topViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow ?? scenes.first?.keyWindow
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
