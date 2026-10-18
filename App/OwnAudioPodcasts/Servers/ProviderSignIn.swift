import AuthenticationServices
import CryptoKit
import SwiftUI

// Sign in with Apple and Google to an own.audio server, copied from own-audio/book-ios
// (AppleSignInButton.swift, GoogleSignInButton.swift) and adapted to this app's model: a second
// factor leaves `pendingTwoFactor` set and the add-server sheet asks for the code.

/// Sign in with Apple to the own.audio server whose address is typed above it. Apple's own
/// button: black on a light background, white on a dark one, as Apple asks.
struct AppleSignInButton: View {
    let address: String
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    var onSignedIn: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    // Held for the whole Apple sheet: SignInWithAppleButton's own completion was lost when
    // SwiftUI rebuilt the button while the sheet was up, and the sign-in silently went nowhere.
    @State private var apple = AppleSignIn()

    var body: some View {
        SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .id(colorScheme)
            .frame(height: 50)
            .clipShape(Capsule())
            .allowsHitTesting(false)
            .overlay {
                // The real tap target: Apple's button only draws.
                Button { start() } label: { Color.clear.contentShape(Capsule()) }
                    .accessibilityLabel(Text("Sign in with Apple"))
                    .accessibilityIdentifier("addServer.apple")
            }
            .disabled(isWorking)
    }

    private func start() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let credential = try await apple.signIn()
                guard let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                    errorMessage = String(localized: "Apple didn't return a sign-in. Try again.")
                    return
                }
                // Apple gives the name only the first time someone signs in to this app.
                let fullName = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                    .flatMap { $0.isEmpty ? nil : $0 }
                try await model.addOwnAudioServer(address: address, signIn: .apple(identityToken: token, fullName: fullName))
                Haptics.impact(.medium)
                onSignedIn()
            } catch let error as ASAuthorizationError where error.code == .canceled {
                return
            } catch {
                errorMessage = AppModel.message(for: error)
            }
        }
    }
}

/// One Sign in with Apple request at a time, as async/await, kept alive by its owner.
@MainActor
final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?

    func signIn() async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                finish(.success(credential))
            } else {
                finish(.failure(ASAuthorizationError(.unknown)))
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { keyWindow() }
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

/// Google sign-in to the own.audio server whose address is typed above it, without Google's
/// SDK: Google's page in the system's web sign-in sheet, PKCE, and the code exchanged for an
/// ID token, which the server verifies. Drawn as Google's own button asks.
struct GoogleSignInButton: View {
    let address: String
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    var onSignedIn: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var google = GoogleSignIn()

    var body: some View {
        Button { start() } label: {
            HStack(spacing: 10) {
                Image("GoogleLogo").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                Text("Continue with Google").font(.system(size: 17, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(colorScheme == .dark ? Color(red: 0.89, green: 0.89, blue: 0.89) : Color(red: 0.12, green: 0.12, blue: 0.12))
            .background(colorScheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.08) : .white, in: Capsule())
            .overlay(Capsule().strokeBorder(colorScheme == .dark ? Color(red: 0.56, green: 0.57, blue: 0.56) : Color(red: 0.45, green: 0.47, blue: 0.46), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityIdentifier("addServer.google")
    }

    private func start() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let idToken = try await google.signIn()
                try await model.addOwnAudioServer(address: address, signIn: .google(idToken: idToken))
                Haptics.impact(.medium)
                onSignedIn()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = (error as? GoogleSignIn.Failure)?.errorDescription ?? AppModel.message(for: error)
            }
        }
    }
}

/// Google's OAuth for an iOS client: no secret, a PKCE verifier instead, and the reversed
/// client id as the redirect scheme, which Google accepts for iOS clients.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// own.audio Podcasts' iOS OAuth client (Google Cloud). Public by design: it identifies the
    /// app and grants nothing. A server accepts sign-ins from it only if it lists it in
    /// `AUTH__GOOGLE__CLIENT_IDS`. A fork uses its own.
    static let clientID = "456111077348-5ji0qmggrej07d76pdrnd0ir45g8aca3.apps.googleusercontent.com"

    enum Failure: LocalizedError {
        case noCode, noToken(String?)
        var errorDescription: String? {
            switch self {
            case .noCode: String(localized: "Google didn't return a sign-in. Try again.")
            case .noToken(let reason): reason ?? String(localized: "Google didn't return a sign-in. Try again.")
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    /// The scheme Google redirects to: the client id, reversed.
    private static var redirectScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    private static var redirectURI: String { redirectScheme + ":/oauthredirect" }

    /// Runs Google's sign-in and returns the ID token.
    func signIn() async throws -> String {
        let verifier = Self.randomURLSafe(bytes: 48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomURLSafe(bytes: 16)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        let callback = try await authenticate(url: components.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else { throw Failure.noCode }
        return try await exchange(code: code, verifier: verifier)
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(Self.redirectScheme)) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? Failure.noCode)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
    }

    private func exchange(code: String, verifier: String) async throws -> String {
        struct Answer: Decodable {
            let id_token: String?
            let error_description: String?
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let answer = try? JSONDecoder().decode(Answer.self, from: data)
        guard let token = answer?.id_token else { throw Failure.noToken(answer?.error_description) }
        return token
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { keyWindow() }
    }

    private static func randomURLSafe(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URL
    }
}

@MainActor
private func keyWindow() -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
