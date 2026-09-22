import AuthenticationServices
import Foundation
import Observation
import SwiftUI
import ZmashKit

/// Where a finished ride can be sent (roadmap Phase 9). Both services use your own credentials,
/// entered in Settings: Zmash has no server and no account of its own.
enum UploadService: String, CaseIterable, Identifiable {
    case strava, intervals

    var id: String { rawValue }

    var name: String {
        switch self {
        case .strava: "Strava"
        case .intervals: "intervals.icu"
        }
    }

    var help: String {
        switch self {
        case .strava: "Create an API application at strava.com/settings/api, set the callback domain to \"localhost\", then paste its client ID and secret here."
        case .intervals: "In intervals.icu → Settings → Developer, copy your athlete ID and API key."
        }
    }
}

// MARK: - Credentials

/// Tokens and keys live in the keychain, never in UserDefaults.
enum Secrets {
    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "zmash.upload",
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "zmash.upload",
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
enum UploadSettings {
    // Strava
    static var stravaClientID: String {
        get { UserDefaults.standard.string(forKey: "strava.clientID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "strava.clientID") }
    }
    static var stravaSecret: String {
        get { Secrets.get("strava.secret") ?? "" }
        set { Secrets.set(newValue, for: "strava.secret") }
    }
    static var stravaRefreshToken: String? {
        get { Secrets.get("strava.refresh") }
        set { Secrets.set(newValue, for: "strava.refresh") }
    }
    static var stravaAccessToken: String? {
        get { Secrets.get("strava.access") }
        set { Secrets.set(newValue, for: "strava.access") }
    }
    static var stravaExpiry: Date {
        get { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "strava.expiry")) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "strava.expiry") }
    }
    static var stravaConnected: Bool { stravaRefreshToken != nil }

    // intervals.icu
    static var intervalsAthleteID: String {
        get { UserDefaults.standard.string(forKey: "intervals.athlete") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "intervals.athlete") }
    }
    static var intervalsKey: String {
        get { Secrets.get("intervals.key") ?? "" }
        set { Secrets.set(newValue, for: "intervals.key") }
    }
    static var intervalsConnected: Bool { !intervalsAthleteID.isEmpty && !intervalsKey.isEmpty }

    /// Send every saved ride automatically.
    static var autoUpload: Bool {
        get { UserDefaults.standard.bool(forKey: "upload.auto") }
        set { UserDefaults.standard.set(newValue, forKey: "upload.auto") }
    }

    static func connected(_ service: UploadService) -> Bool {
        switch service {
        case .strava: stravaConnected
        case .intervals: intervalsConnected
        }
    }

    static func disconnect(_ service: UploadService) {
        switch service {
        case .strava:
            stravaRefreshToken = nil
            stravaAccessToken = nil
        case .intervals:
            intervalsKey = ""
            intervalsAthleteID = ""
        }
    }
}

// MARK: - Uploading

enum UploadError: LocalizedError {
    case notConfigured(UploadService)
    case http(Int, String)
    case cancelled
    case noSamples

    var errorDescription: String? {
        switch self {
        case .notConfigured(let s): "\(s.name) isn't set up in Settings yet."
        case .http(let code, let body): "\(code): \(body.prefix(140))"
        case .cancelled: "Cancelled."
        case .noSamples: "This ride has nothing to upload."
        }
    }
}

/// Uploads a ride's FIT file to Strava and intervals.icu, and tracks what happened.
@MainActor @Observable
final class UploadCenter: NSObject {
    static let shared = UploadCenter()

    enum State: Equatable {
        case idle, working, done(String), failed(String)
    }

    private(set) var state: [UploadService: State] = [:]

    func state(_ service: UploadService) -> State { state[service] ?? .idle }

    /// Sends a ride to every configured service (used by auto-upload after saving).
    func uploadToConfigured(_ ride: FinishedRide) async {
        for service in UploadService.allCases where UploadSettings.connected(service) {
            await upload(ride, to: service)
        }
    }

    func upload(_ ride: FinishedRide, to service: UploadService) async {
        guard !ride.samples.isEmpty else {
            state[service] = .failed(UploadError.noSamples.localizedDescription)
            return
        }
        state[service] = .working
        do {
            let fit = FITWriter.encode(startedAt: ride.startedAt, samples: ride.samples, summary: ride.summary)
            let name = rideName(ride)
            let message: String
            switch service {
            case .strava: message = try await uploadToStrava(fit: fit, name: name)
            case .intervals: message = try await uploadToIntervals(fit: fit, name: name, startedAt: ride.startedAt)
            }
            Diagnostics.log("upload", "\(service.name): \(message)")
            state[service] = .done(message)
        } catch {
            Diagnostics.log("upload", "\(service.name) failed: \(error.localizedDescription)")
            state[service] = .failed(error.localizedDescription)
        }
    }

    private func rideName(_ ride: FinishedRide) -> String {
        if let route = ride.plan.route { return route.name }
        if let workout = ride.plan.workout { return workout.name }
        let hour = Calendar.current.component(.hour, from: ride.startedAt)
        let part = hour < 12 ? "Morning" : hour < 18 ? "Afternoon" : "Evening"
        return "\(part) indoor ride"
    }

    // MARK: Strava

    /// Exchanges the authorisation code for tokens; called from the connect button in Settings.
    func connectStrava() async throws {
        let id = UploadSettings.stravaClientID
        let secret = UploadSettings.stravaSecret
        guard !id.isEmpty, !secret.isEmpty else { throw UploadError.notConfigured(.strava) }
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: id),
            .init(name: "redirect_uri", value: "zmash://strava"),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: "activity:write,activity:read"),
        ]
        let callback = try await authenticate(url: components.url!, scheme: "zmash")
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { throw UploadError.cancelled }

        let body = ["client_id": id, "client_secret": secret, "code": code, "grant_type": "authorization_code"]
        let token = try await postForm(URL(string: "https://www.strava.com/oauth/token")!, fields: body)
        try storeStravaToken(token)
    }

    private func storeStravaToken(_ json: [String: Any]) throws {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String else {
            throw UploadError.http(0, "No token in the reply")
        }
        UploadSettings.stravaAccessToken = access
        UploadSettings.stravaRefreshToken = refresh
        UploadSettings.stravaExpiry = Date(timeIntervalSince1970: json["expires_at"] as? Double ?? 0)
    }

    private func stravaAccessToken() async throws -> String {
        if let token = UploadSettings.stravaAccessToken, UploadSettings.stravaExpiry > Date.now.addingTimeInterval(60) {
            return token
        }
        guard let refresh = UploadSettings.stravaRefreshToken else { throw UploadError.notConfigured(.strava) }
        let json = try await postForm(URL(string: "https://www.strava.com/oauth/token")!, fields: [
            "client_id": UploadSettings.stravaClientID,
            "client_secret": UploadSettings.stravaSecret,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ])
        try storeStravaToken(json)
        return UploadSettings.stravaAccessToken ?? ""
    }

    private func uploadToStrava(fit: Data, name: String) async throws -> String {
        let token = try await stravaAccessToken()
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let boundary = "zmash.\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart(boundary: boundary,
                                     fields: ["data_type": "fit", "name": name, "trainer": "1", "sport_type": "VirtualRide"],
                                     file: (name: "file", filename: "zmash.fit", data: fit))
        let json = try await send(request)
        if let error = json["error"] as? String, !error.isEmpty { throw UploadError.http(200, error) }
        return "Sent to Strava. It appears once Strava finishes processing."
    }

    // MARK: intervals.icu

    private func uploadToIntervals(fit: Data, name: String, startedAt: Date) async throws -> String {
        let athlete = UploadSettings.intervalsAthleteID
        let key = UploadSettings.intervalsKey
        guard !athlete.isEmpty, !key.isEmpty else { throw UploadError.notConfigured(.intervals) }
        let id = athlete.hasPrefix("i") ? athlete : "i\(athlete)"
        var request = URLRequest(url: URL(string: "https://intervals.icu/api/v1/athlete/\(id)/activities")!)
        request.httpMethod = "POST"
        let auth = Data("API_KEY:\(key)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        let boundary = "zmash.\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart(boundary: boundary, fields: ["name": name],
                                     file: (name: "file", filename: "zmash.fit", data: fit))
        _ = try await send(request)
        return "Sent to intervals.icu."
    }

    // MARK: Plumbing

    private func multipart(boundary: String, fields: [String: String], file: (name: String, filename: String, data: Data)) -> Data {
        var body = Data()
        for (key, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(file.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private func postForm(_ url: URL, fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").utf8)
        return try await send(request)
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw UploadError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? UploadError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() { continuation.resume(throwing: UploadError.cancelled) }
        }
    }
}

extension UploadCenter: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
