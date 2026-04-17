import AuthenticationServices
import Combine
import CoreData
import CryptoKit
import Foundation
import PDFKit
import Security
import SwiftUI
import UIKit

@MainActor
final class EmailSyncManager: NSObject, ObservableObject {
    static let clientIDInfoKey = "GmailClientID"
    static let redirectScheme = "com.saaain.keepsure"
    static let redirectURI = "\(redirectScheme):/oauth2redirect"
    private static let fallbackClientID = "212198581284-iorcj2quhua0mh5m4k4boejvdb5270s4.apps.googleusercontent.com"

    @Published private(set) var gmailClientID: String

    @Published private(set) var connectedEmail: String?
    @Published private(set) var connectedFirstName: String?
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isAuthorizing = false
    @Published private(set) var isSyncing = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let tokenStore = GmailTokenStore()
    private let container: NSPersistentContainer
    private var authenticationSession: ASWebAuthenticationSession?

    init(container: NSPersistentContainer) {
        self.container = container
        self.gmailClientID = Self.resolveClientID(defaults: defaults)
        self.connectedEmail = defaults.string(forKey: DefaultsKeys.connectedEmail)
        self.connectedFirstName = defaults.string(forKey: DefaultsKeys.connectedFirstName)
        self.lastSyncAt = defaults.object(forKey: DefaultsKeys.lastSyncAt) as? Date
        super.init()
    }

    var hasUsableConfiguration: Bool {
        Self.isUsableClientID(gmailClientID)
    }

    var isUsingBundledClientID: Bool {
        Self.isUsableClientID(Self.bundledClientID())
    }

    var requiresBundledClientIDSetup: Bool {
        !hasUsableConfiguration
    }

    var isConnected: Bool {
        tokenStore.load() != nil && connectedEmail != nil
    }

    var connectionStatusLine: String {
        if isSyncing {
            return "Syncing Gmail purchases..."
        }
        if isAuthorizing {
            return "Waiting for Google sign-in..."
        }
        if let connectedEmail {
            return "Connected as \(connectedEmail)"
        }
        return "Not connected"
    }

    var setupHint: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.SAAAin.KeepSure"
        return "Add a GmailClientID value to this app's build settings for bundle ID \(bundleID), enable Gmail API, and authorize redirect URI \(Self.redirectURI)."
    }

    var launchPermissionMessage: String {
        "Keep Sure can read purchase emails from Gmail, pull order details, and track return windows and warranties for you. Google will ask for permission in a secure sign-in sheet."
    }

    func restoreSession() {
        gmailClientID = Self.resolveClientID(defaults: defaults)
        connectedEmail = defaults.string(forKey: DefaultsKeys.connectedEmail)
        connectedFirstName = defaults.string(forKey: DefaultsKeys.connectedFirstName)
        lastSyncAt = defaults.object(forKey: DefaultsKeys.lastSyncAt) as? Date
        if tokenStore.load() == nil {
            connectedEmail = nil
            connectedFirstName = nil
        }
    }

    func connectOrSync() async {
        if isConnected {
            await syncInbox()
        } else {
            await connectGmail()
        }
    }

    func connectGmail() async {
        guard hasUsableConfiguration else {
            errorMessage = "Gmail syncing is not available in this build yet."
            return
        }

        isAuthorizing = true
        errorMessage = nil
        defer { isAuthorizing = false }

        do {
            let grant = try await requestAuthorizationCode()
            let tokens = try await GmailAPI.exchangeCodeForTokens(
                clientID: gmailClientID,
                redirectURI: Self.redirectURI,
                code: grant.authorizationCode,
                codeVerifier: grant.codeVerifier
            )

            guard let refreshToken = tokens.refreshToken else {
                throw GmailSyncError.missingRefreshToken
            }

            let envelope = GmailTokenEnvelope(
                accessToken: tokens.accessToken,
                refreshToken: refreshToken, 
                idToken: tokens.idToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
            )

            tokenStore.save(envelope)

            let profile = try await GmailAPI.fetchProfile(accessToken: envelope.accessToken)
            connectedEmail = profile.email
            connectedFirstName = profile.bestFirstName
            defaults.set(profile.email, forKey: DefaultsKeys.connectedEmail)
            defaults.set(profile.bestFirstName, forKey: DefaultsKeys.connectedFirstName)
            statusMessage = "Connected Gmail for \(profile.email)."

            await syncInbox()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func disconnect() {
        tokenStore.clear()
        connectedEmail = nil
        connectedFirstName = nil
        lastSyncAt = nil
        statusMessage = "Gmail disconnected."
        defaults.removeObject(forKey: DefaultsKeys.connectedEmail)
        defaults.removeObject(forKey: DefaultsKeys.connectedFirstName)
        defaults.removeObject(forKey: DefaultsKeys.lastSyncAt)
        Task {
            await SmartNotificationManager.shared.rescheduleAll(in: container)
        }
    }

    func syncOnLaunchIfNeeded() async {
        guard isConnected, !isSyncing, !isAuthorizing else { return }

        if let lastSyncAt, Date().timeIntervalSince(lastSyncAt) < 900 {
            return
        }

        await syncInbox()
    }

    func syncInbox() async {
        guard hasUsableConfiguration else {
            errorMessage = "Gmail syncing is not available in this build yet."
            return
        }

        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            let accessToken = try await validAccessToken()
            let messages = try await GmailAPI.fetchPurchaseMessages(accessToken: accessToken, maxResults: 24)
            let summary = try await importMessages(messages)
            container.viewContext.refreshAllObjects()

            let syncDate = Date()
            lastSyncAt = syncDate
            defaults.set(syncDate, forKey: DefaultsKeys.lastSyncAt)

            statusMessage = summary.statusLine
            await SmartNotificationManager.shared.rescheduleAll(in: container)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func validAccessToken() async throws -> String {
        guard var envelope = tokenStore.load() else {
            throw GmailSyncError.notConnected
        }

        if envelope.isExpired {
            let refreshed = try await GmailAPI.refreshAccessToken(
                clientID: gmailClientID,
                refreshToken: envelope.refreshToken
            )
            envelope.accessToken = refreshed.accessToken
            envelope.expiresAt = Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
            if let newRefreshToken = refreshed.refreshToken, !newRefreshToken.isEmpty {
                envelope.refreshToken = newRefreshToken
            }
            tokenStore.save(envelope)
        }

        return envelope.accessToken
    }

    private func importMessages(_ messages: [GmailMessage]) async throws -> GmailImportSummary {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                do {
                    let summary = try GmailPurchaseImporter.importMessages(messages, in: context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: summary)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func requestAuthorizationCode() async throws -> GmailAuthorizationGrant {
        let state = UUID().uuidString
        let verifier = PKCECodeVerifier()
        let authURL = try GmailAPI.makeAuthorizationURL(
            clientID: gmailClientID,
            redirectURI: Self.redirectURI,
            state: state,
            codeChallenge: verifier.challenge
        )

        let callbackURL: URL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: Self.redirectScheme) { [weak self] callbackURL, error in
                self?.authenticationSession = nil

                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: GmailSyncError.authorizationCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: GmailSyncError.invalidAuthorizationResponse)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session

            if !session.start() {
                authenticationSession = nil
                continuation.resume(throwing: GmailSyncError.unableToStartAuthorization)
            }
        }

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw GmailSyncError.invalidAuthorizationResponse
        }

        if let returnedState = items.first(where: { $0.name == "state" })?.value, returnedState != state {
            throw GmailSyncError.invalidState
        }

        if let errorValue = items.first(where: { $0.name == "error" })?.value {
            throw GmailSyncError.authorizationRejected(errorValue)
        }

        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GmailSyncError.invalidAuthorizationResponse
        }

        return GmailAuthorizationGrant(authorizationCode: code, codeVerifier: verifier.value)
    }

    private static func resolveClientID(defaults: UserDefaults) -> String {
        if let bundledClientID = bundledClientID(), isUsableClientID(bundledClientID) {
            return bundledClientID
        }

        let storedClientID = defaults.string(forKey: DefaultsKeys.gmailClientID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return storedClientID
    }

    private static func bundledClientID() -> String? {
        let infoValue = (Bundle.main.object(forInfoDictionaryKey: clientIDInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if isUsableClientID(infoValue) {
            return infoValue
        }

        return fallbackClientID
    }

    private static func isUsableClientID(_ value: String?) -> Bool {
        guard let value else { return false }
        if value.isEmpty {
            return false
        }

        let normalized = value.lowercased()
        return !normalized.contains("your_google")
            && !normalized.contains("your-client-id")
            && !normalized.contains("replace-me")
            && value.contains(".apps.googleusercontent.com")
    }
}

extension EmailSyncManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)

        if let keyWindow = windows.first(where: \.isKeyWindow) {
            return keyWindow
        }

        if let firstWindow = windows.first {
            return firstWindow
        }

        guard let scene = scenes.first else {
            preconditionFailure("Expected a window scene before starting Gmail authorization.")
        }

        return UIWindow(windowScene: scene)
    }
}

private enum DefaultsKeys {
    static let gmailClientID = "gmail_client_id"
    static let connectedEmail = "gmail_connected_email"
    static let connectedFirstName = "gmail_connected_first_name"
    static let lastSyncAt = "gmail_last_sync_at"
}

private struct GmailAuthorizationGrant {
    let authorizationCode: String
    let codeVerifier: String
}

private struct PKCECodeVerifier {
    let value: String
    let challenge: String

    init() {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        value = String((0..<64).compactMap { _ in charset.randomElement() })

        let hashed = SHA256.hash(data: Data(value.utf8))
        challenge = Data(hashed)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct GmailTokenEnvelope: Codable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var expiresAt: Date

    var isExpired: Bool {
        expiresAt <= Date().addingTimeInterval(60)
    }
}

private struct GmailTokenStore {
    private let service = "KeepSure.GmailTokenStore"
    private let account = "gmail"

    func save(_ envelope: GmailTokenEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func load() -> GmailTokenEnvelope? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let envelope = try? JSONDecoder().decode(GmailTokenEnvelope.self, from: data) else {
            return nil
        }

        return envelope
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}

private enum GmailAPI {
    private static let scopes = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/gmail.readonly"
    ]

    static func makeAuthorizationURL(
        clientID: String,
        redirectURI: String,
        state: String,
        codeChallenge: String
    ) throws -> URL {
        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            throw GmailSyncError.invalidAuthorizationResponse
        }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else {
            throw GmailSyncError.invalidAuthorizationResponse
        }

        return url
    }

    static func exchangeCodeForTokens(
        clientID: String,
        redirectURI: String,
        code: String,
        codeVerifier: String
    ) async throws -> GmailTokenResponse {
        try await tokenRequest(parameters: [
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code"
        ])
    }

    static func refreshAccessToken(
        clientID: String,
        refreshToken: String
    ) async throws -> GmailTokenResponse {
        try await tokenRequest(parameters: [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
    }

    static func fetchProfile(accessToken: String) async throws -> GmailUserProfile {
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await execute(request, as: GmailUserProfile.self)
    }

    static func fetchPurchaseMessages(accessToken: String, maxResults: Int) async throws -> [GmailMessage] {
        guard var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages") else {
            throw GmailSyncError.invalidAuthorizationResponse
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: "newer_than:180d (category:purchases OR subject:(order OR receipt OR shipped OR delivered OR invoice))"),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let listResponse = try await execute(request, as: GmailMessageListResponse.self)
        let references = listResponse.messages ?? []

        return try await withThrowingTaskGroup(of: GmailMessage?.self) { group in
            for reference in references {
                group.addTask {
                    try await fetchMessage(id: reference.id, accessToken: accessToken)
                }
            }

            var messages: [GmailMessage] = []
            for try await message in group {
                if let message {
                    messages.append(message)
                }
            }

            return messages.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
    }

    private static func fetchMessage(id: String, accessToken: String) async throws -> GmailMessage? {
        guard var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)") else {
            throw GmailSyncError.invalidAuthorizationResponse
        }

        components.queryItems = [
            URLQueryItem(name: "format", value: "full")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let response = try await execute(request, as: GmailMessageResponse.self)
        return response.asMessage
    }

    private static func tokenRequest(parameters: [String: String]) async throws -> GmailTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { key, value in
                "\(key.urlEscaped)=\(value.urlEscaped)"
            }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)

        return try await execute(request, as: GmailTokenResponse.self)
    }

    private static func execute<Response: Decodable>(_ request: URLRequest, as type: Response.Type) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailSyncError.serverError("Google did not return a valid HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(GmailAPIErrorResponse.self, from: data) {
                throw GmailSyncError.serverError(apiError.error.message)
            }
            throw GmailSyncError.serverError("Google returned status \(httpResponse.statusCode).")
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GmailSyncError.serverError("Keep Sure could not decode Gmail data.")
        }
    }
}

struct GmailMessage: Equatable {
    let id: String
    let subject: String
    let from: String
    let snippet: String
    let body: String
    let htmlBody: String?
    let date: Date?
}

private struct GmailParsedPurchase {
    let draft: ReceiptDraft
    let orderNumber: String?
    let stage: GmailOrderStage
    let merchantName: String
    let messageID: String
}

enum GmailOrderStage: String {
    case placed
    case shipped
    case delivered
    case unknown

    nonisolated var noteTitle: String {
        switch self {
        case .placed:
            return "Order placed"
        case .shipped:
            return "Shipped"
        case .delivered:
            return "Delivered"
        case .unknown:
            return "Purchase email"
        }
    }

    nonisolated var statusLineTitle: String {
        switch self {
        case .placed:
            return "Order placed"
        case .shipped:
            return "Shipped"
        case .delivered:
            return "Delivered"
        case .unknown:
            return "Email saved"
        }
    }
}

private struct GmailUserProfile: Decodable {
    let email: String
    let name: String?
    let givenName: String?

    var bestFirstName: String? {
        if let givenName = cleanedFirstName(from: givenName) {
            return givenName
        }

        if let name = cleanedFirstName(from: name) {
            return name
        }

        let localPart = email.split(separator: "@").first.map(String.init) ?? ""
        let fallback = localPart
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .first
            .map(String.init)

        return cleanedFirstName(from: fallback)
    }

    private func cleanedFirstName(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let firstToken = trimmed
            .split(separator: " ")
            .first
            .map(String.init) ?? trimmed

        guard !firstToken.isEmpty else { return nil }
        return firstToken.prefix(1).uppercased() + firstToken.dropFirst()
    }

    private enum CodingKeys: String, CodingKey {
        case email
        case name
        case givenName = "given_name"
    }
}

private struct GmailTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let idToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

private struct GmailAPIErrorResponse: Decodable {
    struct Details: Decodable {
        let message: String
    }

    let error: Details
}

private struct GmailMessageListResponse: Decodable {
    let messages: [GmailMessageReference]?
}

private struct GmailMessageReference: Decodable {
    let id: String
}

private struct GmailMessageResponse: Decodable {
    let id: String
    let snippet: String?
    let internalDate: String?
    let payload: GmailPayload?

    var asMessage: GmailMessage? {
        let subject = payload?.header(named: "Subject") ?? ""
        let from = payload?.header(named: "From") ?? ""
        let body = payload?.combinedText() ?? ""
        let htmlBody = payload?.combinedHTML()
        let snippet = snippet ?? ""

        guard !subject.isEmpty || !snippet.isEmpty || !body.isEmpty else {
            return nil
        }

        let parsedDate = payload?.header(named: "Date")
            .flatMap(GmailDateParser.parse)
            ?? internalDate.flatMap { milliseconds in
                guard let value = Double(milliseconds) else { return nil }
                return Date(timeIntervalSince1970: value / 1000)
            }

        return GmailMessage(
            id: id,
            subject: subject,
            from: from,
            snippet: snippet,
            body: body,
            htmlBody: htmlBody,
            date: parsedDate
        )
    }
}

private struct GmailPayload: Decodable {
    let mimeType: String?
    let headers: [GmailHeader]?
    let body: GmailBody?
    let parts: [GmailPayload]?

    func header(named name: String) -> String? {
        headers?.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    func combinedText() -> String {
        var chunks: [String] = []
        collectText(into: &chunks)
        return chunks
            .map { $0.replacingOccurrences(of: "\r", with: "\n") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func combinedHTML() -> String? {
        var chunks: [String] = []
        collectHTML(into: &chunks)
        let combined = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    private func collectText(into chunks: inout [String]) {
        let mime = mimeType?.lowercased() ?? ""

        if mime == "text/plain" || (parts == nil && body?.data != nil && mime != "text/html") {
            if let text = body?.decodedString, !text.isEmpty {
                chunks.append(text)
            }
        } else if mime == "text/html" {
            if let html = body?.decodedString {
                let plain = GmailHTMLFormatter.structuredText(from: html)
                chunks.append(plain)
            }
        }

        for part in parts ?? [] {
            part.collectText(into: &chunks)
        }
    }

    private func collectHTML(into chunks: inout [String]) {
        let mime = mimeType?.lowercased() ?? ""

        if mime == "text/html", let html = body?.decodedString, !html.isEmpty {
            chunks.append(html)
        }

        for part in parts ?? [] {
            part.collectHTML(into: &chunks)
        }
    }
}

private struct GmailHeader: Decodable {
    let name: String
    let value: String
}

private struct GmailBody: Decodable {
    let data: String?

    var decodedString: String? {
        guard let data else { return nil }
        var base64 = data
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let decodedData = Data(base64Encoded: base64),
              let decodedString = String(data: decodedData, encoding: .utf8) else {
            return nil
        }

        return decodedString
    }
}

private enum GmailDateParser {
    nonisolated static func parse(_ value: String) -> Date? {
        let normalized = value
            .components(separatedBy: ";")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? value

        for formatter in formatters {
            if let date = formatter.date(from: normalized) {
                return date
            }
        }

        return nil
    }

    nonisolated private static let formatters: [DateFormatter] = {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm Z"
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()
}

enum GmailPurchaseParser {
    fileprivate static func parse(_ message: GmailMessage) -> GmailParsedPurchase? {
        let combinedText = """
        Subject: \(message.subject)
        From: \(message.from)
        \(message.snippet)
        \(message.body)
        """

        guard isLikelyPurchase(subject: message.subject, body: combinedText) else {
            return nil
        }

        var draft = ReceiptTextParser.draft(from: combinedText, pageCount: 1)
        let profile = matchingProfile(sender: message.from, subject: message.subject, body: combinedText)
        let merchant = profile?.name ?? inferMerchant(from: message.from) ?? draft.merchantName
        let product = inferProduct(
            from: message.subject,
            body: combinedText,
            merchant: merchant,
            profile: profile
        )

        if !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.merchantName = merchant
        }
        if let product, !product.isEmpty {
            draft.productName = product
        }
        if let profile {
            draft.returnDays = profile.returnDays
            if draft.categoryName == "General" {
                draft.categoryName = profile.categoryHint
            }
        }
        if let total = inferOrderTotal(from: combinedText) {
            draft.price = total
        }
        if let messageDate = message.date {
            draft.purchaseDate = messageDate
        }

        let warrantyInference = ReceiptTextParser.inferWarrantyDetails(
            from: combinedText,
            category: draft.categoryName,
            merchant: draft.merchantName,
            productName: draft.productName
        )
        draft.warrantyStatus = warrantyInference.status
        draft.warrantyMonths = warrantyInference.months
        draft.warrantyConfidenceNote = warrantyInference.note
        draft.importBaseline = ReceiptImportBaseline(
            merchantName: draft.merchantName,
            productName: draft.productName,
            categoryName: draft.categoryName,
            warrantyStatus: warrantyInference.status,
            warrantyMonths: warrantyInference.months,
            warrantyConfidenceNote: warrantyInference.note
        )

        ImportLearningStore.shared.apply(to: &draft)

        let refinedWarrantyInference = ReceiptTextParser.inferWarrantyDetails(
            from: combinedText,
            category: draft.categoryName,
            merchant: draft.merchantName,
            productName: draft.productName
        )
        if draft.warrantyStatus != .confirmed {
            draft.warrantyStatus = refinedWarrantyInference.status
            draft.warrantyMonths = refinedWarrantyInference.months
            draft.warrantyConfidenceNote = refinedWarrantyInference.note
        }

        let orderNumber = inferOrderNumber(from: combinedText)
        let stage = inferStage(subject: message.subject, body: combinedText)

        draft.sourceType = "Email"
        draft.notes = buildNotes(subject: message.subject, body: combinedText, orderNumber: orderNumber, stage: stage)
        draft.recognizedText = combinedText
        draft.pageCount = 1
        let proof = GmailProofBuilder.makeProof(for: message, merchant: merchant, orderNumber: orderNumber, stage: stage)
        draft.proofPreviewData = proof.previewData
        draft.proofDocumentData = proof.documentData
        draft.proofDocumentType = proof.documentType
        draft.proofDocumentName = proof.documentName
        draft.proofHTMLData = message.htmlBody?.data(using: .utf8)

        return GmailParsedPurchase(
            draft: draft,
            orderNumber: orderNumber,
            stage: stage,
            merchantName: merchant,
            messageID: message.id
        )
    }

    private static func isLikelyPurchase(subject: String, body: String) -> Bool {
        let haystack = "\(subject) \(body)".lowercased()
        let keywords = [
            "order confirmed",
            "receipt",
            "order total",
            "purchase",
            "delivered",
            "shipped",
            "thanks for your order",
            "thanks for shopping",
            "invoice",
            "$"
        ]

        return keywords.contains(where: haystack.contains)
    }

    private static func inferMerchant(from sender: String) -> String? {
        if let profile = matchingProfile(sender: sender, subject: "", body: "") {
            return profile.name
        }

        let cleaned = sender
            .components(separatedBy: "<")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? sender

        if !cleaned.isEmpty, cleaned.rangeOfCharacter(from: .letters) != nil {
            return cleaned
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let emailPart = sender.components(separatedBy: "<").last?
            .replacingOccurrences(of: ">", with: "")
            .split(separator: "@")
            .last?
            .split(separator: ".")
            .first {
            return String(emailPart).capitalized
        }

        return nil
    }

    private static func inferProduct(from subject: String, body: String, merchant: String, profile: MerchantProfile?) -> String? {
        if let profile {
            for pattern in profile.productPatterns {
                if let match = firstMatch(in: body, pattern: pattern), isUsefulProductCandidate(match, merchant: merchant) {
                    return cleanupProduct(match, merchant: merchant)
                }
            }
        }

        for pattern in generalBodyProductPatterns {
            if let match = firstMatch(in: body, pattern: pattern), isUsefulProductCandidate(match, merchant: merchant) {
                return cleanupProduct(match, merchant: merchant)
            }
        }

        let candidates = [
            "order confirmed:",
            "your order:",
            "shipped:",
            "delivered:",
            "receipt for",
            "order from"
        ]

        let lower = subject.lowercased()
        for candidate in candidates {
            if let range = lower.range(of: candidate) {
                let suffix = subject[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-:"))
                if !suffix.isEmpty {
                    return suffix
                }
            }
        }

        let cleaned = subject
            .replacingOccurrences(of: merchant, with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Your order", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Order confirmed", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Receipt", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "has shipped", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "has been delivered", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "delivery update", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-"))

        let normalized = cleanupProduct(cleaned, merchant: merchant)
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated fileprivate static func inferOrderTotal(from body: String) -> Double? {
        let patterns = [
            #"(?i)(?:order total|grand total|total paid|amount paid|payment total|total)[^\d$]{0,12}\$?\s*([0-9]+(?:\.[0-9]{2})?)"#,
            #"(?i)\$([0-9]+(?:\.[0-9]{2})?)\s*(?:order total|grand total|total paid|amount paid)"#
        ]

        for pattern in patterns {
            if let match = firstMatch(in: body, pattern: pattern), let value = Double(match) {
                return value
            }
        }

        return nil
    }

    private static func buildNotes(subject: String, body: String, orderNumber: String?, stage: GmailOrderStage) -> String {
        var notes = ["Imported from Gmail: \(subject)", stage.noteTitle]

        if let orderNumber {
            notes.append("Order \(orderNumber)")
        }

        return notes.joined(separator: " • ")
    }

    private static func inferOrderNumber(from body: String) -> String? {
        let patterns = [
            #"(?i)(?:order number|order #|order no\.?|confirmation #|confirmation number)[^\w]{0,6}([A-Z0-9\-]{5,})"#,
            #"(?i)#([A-Z0-9]{6,})"#
        ]

        for pattern in patterns {
            if let match = firstMatch(in: body, pattern: pattern) {
                return match
            }
        }

        return nil
    }

    private static func inferStage(subject: String, body: String) -> GmailOrderStage {
        let haystack = "\(subject) \(body)".lowercased()

        let deliveredHints = [
            "delivered",
            "was delivered",
            "has been delivered",
            "delivery complete",
            "picked up"
        ]
        if deliveredHints.contains(where: haystack.contains) {
            return .delivered
        }

        let shippedHints = [
            "shipped",
            "has shipped",
            "on the way",
            "out for delivery",
            "shipping update",
            "track your package"
        ]
        if shippedHints.contains(where: haystack.contains) {
            return .shipped
        }

        let placedHints = [
            "order confirmed",
            "thanks for your order",
            "receipt",
            "invoice",
            "purchase confirmation",
            "order received"
        ]
        if placedHints.contains(where: haystack.contains) {
            return .placed
        }

        return .unknown
    }

    private static func matchingProfile(sender: String, subject: String, body: String) -> MerchantProfile? {
        let senderLower = sender.lowercased()
        let subjectLower = subject.lowercased()
        let bodyLower = body.lowercased()

        return merchantProfiles.first { profile in
            profile.senderHints.contains(where: senderLower.contains)
                || profile.subjectHints.contains(where: subjectLower.contains)
                || profile.bodyHints.contains(where: bodyLower.contains)
        }
    }

    private static func cleanupProduct(_ value: String, merchant: String) -> String {
        value
            .replacingOccurrences(of: merchant, with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "item:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "items:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "product:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "description:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-\n\t"))
    }

    private static func isUsefulProductCandidate(_ value: String, merchant: String) -> Bool {
        let cleaned = cleanupProduct(value, merchant: merchant)
        let lower = cleaned.lowercased()
        let blocked = [
            "order total",
            "subtotal",
            "tax",
            "shipping",
            "delivered",
            "shipped",
            "receipt",
            "order number",
            "confirmation",
            "track your package"
        ]

        return !cleaned.isEmpty
            && cleaned.count > 3
            && !blocked.contains(where: lower.contains)
    }

    nonisolated private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = expression.firstMatch(in: text, options: [], range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let generalBodyProductPatterns = [
        #"(?im)^\s*(?:item|items|product|description)\s*[:\-]\s*(.+)$"#,
        #"(?im)^\s*(?:order item|ordered item|item name)\s*[:\-]\s*(.+)$"#,
        #"(?im)^\s*1\s*x\s+(.+)$"#,
        #"(?im)^\s*qty\s*\d+\s+(.+)$"#,
        #"(?im)^\s*([A-Z0-9][A-Za-z0-9 .,'’\-/()]{6,})\s+\$[0-9]+(?:\.[0-9]{2})?\s*$"#
    ]

    private static let merchantProfiles: [MerchantProfile] = [
        MerchantProfile(
            name: "Amazon",
            senderHints: ["amazon.com", "amazon.in", "amazon.co.uk"],
            subjectHints: ["amazon", "your amazon.com order"],
            bodyHints: ["sold by amazon", "amazon order"],
            returnDays: 30,
            categoryHint: "General",
            productPatterns: [
                #"(?im)^\s*item(?:s)?\s*ordered\s*[:\-]?\s*(.+)$"#,
                #"(?im)^\s*order summary\s*[:\-]?\s*(.+)$"#,
                #"(?im)^\s*item(?:s)?\s*:\s*(.+)$"#
            ]
        ),
        MerchantProfile(
            name: "Costco",
            senderHints: ["costco.com"],
            subjectHints: ["costco", "order number"],
            bodyHints: ["costco.com order number"],
            returnDays: 90,
            categoryHint: "Home",
            productPatterns: [
                #"(?im)^\s*item description\s*[:\-]?\s*(.+)$"#,
                #"(?im)^\s*product details\s*[:\-]?\s*(.+)$"#,
                #"(?im)^\s*ordered item\s*[:\-]?\s*(.+)$"#
            ]
        ),
        MerchantProfile(
            name: "Target",
            senderHints: ["target.com"],
            subjectHints: ["target order", "your target order"],
            bodyHints: ["order pickup", "target order number"],
            returnDays: 30,
            categoryHint: "General",
            productPatterns: [
                #"(?im)^\s*item\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*items in your order\s*[:\-]?\s*(.+)$"#,
                #"(?im)^\s*product name\s*[:\-]\s*(.+)$"#
            ]
        ),
        MerchantProfile(
            name: "Walmart",
            senderHints: ["walmart.com"],
            subjectHints: ["walmart order", "your walmart order"],
            bodyHints: ["walmart order #"],
            returnDays: 30,
            categoryHint: "General",
            productPatterns: [
                #"(?im)^\s*item details\s*[:\-]?\s*(.+)$"#,
                #"(?im)^\s*item\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*items ordered\s*[:\-]?\s*(.+)$"#
            ]
        ),
        MerchantProfile(
            name: "Best Buy",
            senderHints: ["bestbuy.com", "best buy"],
            subjectHints: ["best buy", "your order has"],
            bodyHints: ["best buy order number"],
            returnDays: 15,
            categoryHint: "Electronics",
            productPatterns: [
                #"(?im)^\s*item\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*product name\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*item details\s*[:\-]?\s*(.+)$"#
            ]
        ),
        MerchantProfile(
            name: "Apple",
            senderHints: ["apple.com", "apple store"],
            subjectHints: ["apple store", "your apple order"],
            bodyHints: ["order details", "apple order number"],
            returnDays: 14,
            categoryHint: "Electronics",
            productPatterns: [
                #"(?im)^\s*product\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*item\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*item name\s*[:\-]\s*(.+)$"#
            ]
        ),
        MerchantProfile(
            name: "Sephora",
            senderHints: ["sephora.com"],
            subjectHints: ["sephora", "your order"],
            bodyHints: ["beauty insider", "order summary"],
            returnDays: 30,
            categoryHint: "Beauty",
            productPatterns: [
                #"(?im)^\s*item\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*product\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*items ordered\s*[:\-]?\s*(.+)$"#
            ]
        ),
        MerchantProfile(
            name: "Home Depot",
            senderHints: ["homedepot.com", "home depot"],
            subjectHints: ["home depot", "your order is"],
            bodyHints: ["home depot order", "order details"],
            returnDays: 90,
            categoryHint: "Home",
            productPatterns: [
                #"(?im)^\s*product\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*item details\s*[:\-]?\s*(.+)$"#
            ]
        ),
        MerchantProfile(
            name: "Nike",
            senderHints: ["nike.com"],
            subjectHints: ["nike order", "your nike order"],
            bodyHints: ["order number", "thanks for shopping nike"],
            returnDays: 60,
            categoryHint: "General",
            productPatterns: [
                #"(?im)^\s*item\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*product\s*[:\-]\s*(.+)$"#
            ]
        ),
        MerchantProfile(
            name: "Etsy",
            senderHints: ["etsy.com"],
            subjectHints: ["etsy order", "your etsy purchase"],
            bodyHints: ["order from", "etsy receipt"],
            returnDays: 30,
            categoryHint: "General",
            productPatterns: [
                #"(?im)^\s*item\s*[:\-]\s*(.+)$"#,
                #"(?im)^\s*order from\s+.+?\s*[:\-]?\s*(.+)$"#
            ]
        )
    ]
}

private struct MerchantProfile {
    let name: String
    let senderHints: [String]
    let subjectHints: [String]
    let bodyHints: [String]
    let returnDays: Int
    let categoryHint: String
    let productPatterns: [String]
}

private enum GmailHTMLFormatter {
    nonisolated static func structuredText(from html: String) -> String {
        html
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</p\\s*>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</li\\s*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<li[^>]*>", with: "• ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</h[1-6]\\s*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</tr\\s*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</t[dh]\\s*>", with: "   ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<t[dh][^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum GmailProofBuilder {
    static func makeProof(for message: GmailMessage, merchant: String, orderNumber: String?, stage: GmailOrderStage) -> (previewData: Data?, documentData: Data?, documentType: String, documentName: String) {
        let documentName = proofDocumentName(merchant: merchant, orderNumber: orderNumber, stage: stage)
        let rendererFormat = UIGraphicsPDFRendererFormat()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: rendererFormat)

        let pdfData = renderer.pdfData { context in
            context.beginPage()

            let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let labelFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let valueFont = UIFont.systemFont(ofSize: 13, weight: .regular)
            let bodyFont = UIFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            let highlightFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)

            let contentWidth = pageRect.width - 64
            var y: CGFloat = 36

            func drawLine(_ text: String, font: UIFont, color: UIColor = UIColor(AppTheme.ink), spacingAfter: CGFloat = 12) {
                guard !text.isEmpty else { return }
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributed = NSAttributedString(
                    string: text,
                    attributes: [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ]
                )
                let maxRect = CGRect(x: 32, y: y, width: contentWidth, height: 10_000)
                let measured = attributed.boundingRect(with: maxRect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

                if y + measured.height > pageRect.height - 40 {
                    context.beginPage()
                    y = 36
                }

                attributed.draw(with: CGRect(x: 32, y: y, width: contentWidth, height: ceil(measured.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += ceil(measured.height) + spacingAfter
            }

            drawLine("Keep Sure Gmail Proof", font: titleFont, spacingAfter: 18)
            drawLine("EMAIL SNAPSHOT", font: labelFont, color: UIColor(AppTheme.accent), spacingAfter: 8)
            drawLine("Merchant: \(merchant)", font: valueFont, spacingAfter: 6)
            drawLine("Stage: \(stage.statusLineTitle)", font: valueFont, spacingAfter: 6)
            if let orderNumber, !orderNumber.isEmpty {
                drawLine("Order: \(orderNumber)", font: valueFont, spacingAfter: 6)
            }
            if let date = message.date {
                drawLine("Date: \(date.formatted(date: .abbreviated, time: .shortened))", font: valueFont, spacingAfter: 6)
            }
            drawLine("From: \(message.from)", font: valueFont, spacingAfter: 6)
            drawLine("Subject: \(message.subject)", font: valueFont, spacingAfter: 16)

            let highlights = orderHighlights(for: message, orderNumber: orderNumber, stage: stage)
            if !highlights.isEmpty {
                drawLine("ORDER HIGHLIGHTS", font: labelFont, color: UIColor(AppTheme.accent), spacingAfter: 8)
                for line in highlights {
                    drawLine(line, font: highlightFont, color: UIColor(AppTheme.ink), spacingAfter: 6)
                }
                y += 8
            }

            let lineItems = likelyLineItems(for: message, merchant: merchant)
            if !lineItems.isEmpty {
                drawLine("LIKELY LINE ITEMS", font: labelFont, color: UIColor(AppTheme.accent), spacingAfter: 8)
                for item in lineItems.prefix(8) {
                    drawLine(item, font: bodyFont, color: UIColor(AppTheme.ink), spacingAfter: 6)
                }
                y += 10
            }

            drawLine("SNIPPET", font: labelFont, color: UIColor(AppTheme.accent), spacingAfter: 8)
            drawLine(message.snippet, font: bodyFont, color: UIColor(AppTheme.secondaryAccent), spacingAfter: 18)

            drawLine("MESSAGE BODY", font: labelFont, color: UIColor(AppTheme.accent), spacingAfter: 8)
            let preferredBody = message.htmlBody.map(GmailHTMLFormatter.structuredText(from:)) ?? message.body
            let cleanedBody = preferredBody
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            drawLine(cleanedBody.isEmpty ? "No body text available." : cleanedBody, font: bodyFont, color: UIColor(AppTheme.ink), spacingAfter: 12)
        }

        let previewData: Data?
        if let document = PDFDocument(data: pdfData), let firstPage = document.page(at: 0) {
            let image = ReceiptPDFOCR.render(page: firstPage)
            previewData = image.flatMap(ReceiptProofBuilder.makePreviewData(from:))
        } else {
            previewData = nil
        }

        return (previewData, pdfData, "pdf", documentName)
    }

    nonisolated private static func proofDocumentName(merchant: String, orderNumber: String?, stage: GmailOrderStage) -> String {
        let merchantPart = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Gmail" : merchant
        let orderPart = (orderNumber?.isEmpty == false ? orderNumber! : stage.rawValue.capitalized)
        return "\(merchantPart) \(orderPart) email proof.pdf"
    }

    nonisolated private static func orderHighlights(for message: GmailMessage, orderNumber: String?, stage: GmailOrderStage) -> [String] {
        var lines: [String] = []

        if let orderNumber, !orderNumber.isEmpty {
            lines.append("Order number: \(orderNumber)")
        }

        if let total = GmailPurchaseParser.inferOrderTotal(from: "\(message.subject)\n\(message.body)") {
            lines.append("Order total: \(total.formatted(.currency(code: "USD")))")
        }

        if let date = message.date {
            lines.append("Email date: \(date.formatted(date: .abbreviated, time: .shortened))")
        }

        lines.append("Lifecycle stage: \(stage.statusLineTitle)")
        return lines
    }

    nonisolated private static func likelyLineItems(for message: GmailMessage, merchant: String) -> [String] {
        let source = message.htmlBody.map(GmailHTMLFormatter.structuredText(from:)) ?? message.body
        let lines = source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let blocked = [
            "subtotal", "tax", "shipping", "delivery", "order number", "confirmation",
            "track your package", "billed to", "payment", "visa", "mastercard", "discover",
            "return policy", "need help", "customer service", "support"
        ]

        var results: [String] = []
        for line in lines {
            let lower = line.lowercased()
            guard lower.range(of: merchant.lowercased()) == nil || line.count > merchant.count + 8 else { continue }
            guard blocked.allSatisfy({ !lower.contains($0) }) else { continue }
            let hasLetters = line.rangeOfCharacter(from: .letters) != nil
            let hasPrice = lower.range(of: #"\$?\d+(?:\.\d{2})"#, options: .regularExpression) != nil
            let looksTableRow = line.contains("   ") || line.contains("•")
            guard hasLetters && (hasPrice || looksTableRow) else { continue }
            results.append(line)
        }

        var unique: [String] = []
        for result in results {
            if !unique.contains(where: { $0.caseInsensitiveCompare(result) == .orderedSame }) {
                unique.append(result)
            }
        }
        return unique
    }
}

private enum GmailPurchaseImporter {
    static func importMessages(_ messages: [GmailMessage], in context: NSManagedObjectContext) throws -> GmailImportSummary {
        var imported = 0
        var updated = 0
        var skipped = 0

        for message in messages {
            let parsed = GmailPurchaseParser.parse(message)

            if let existing = try existingRecord(for: message.id, in: context) {
                if let parsed {
                    merge(parsed: parsed, into: existing)
                }
                existing.lastSyncedAt = Date()
                updated += 1
                continue
            }

            guard let parsed else {
                skipped += 1
                continue
            }

            if let existing = try lifecycleRecord(for: parsed, in: context) {
                merge(parsed: parsed, into: existing)
                existing.lastSyncedAt = .now
                updated += 1
            } else {
                let record = PurchaseRecord(context: context)
                populate(record: record, from: parsed, messageID: message.id)
                imported += 1
            }
        }

        return GmailImportSummary(imported: imported, updated: updated, skipped: skipped)
    }

    private static func existingRecord(for messageID: String, in context: NSManagedObjectContext) throws -> PurchaseRecord? {
        let request = PurchaseRecord.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "externalProvider == %@ AND externalRecordID == %@", "gmail", messageID)
        return try context.fetch(request).first
    }

    private static func lifecycleRecord(for parsed: GmailParsedPurchase, in context: NSManagedObjectContext) throws -> PurchaseRecord? {
        let request = PurchaseRecord.fetchRequest()
        request.fetchLimit = 1

        if let orderNumber = parsed.orderNumber, !orderNumber.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "sourceType == %@", "Email"),
                NSPredicate(format: "merchantName == %@", parsed.merchantName),
                NSPredicate(format: "gmailOrderNumber == %@", orderNumber)
            ])

            if let match = try context.fetch(request).first {
                return match
            }
        }

        let fallbackRequest = PurchaseRecord.fetchRequest()
        fallbackRequest.fetchLimit = 1
        fallbackRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "sourceType == %@", "Email"),
            NSPredicate(format: "merchantName == %@", parsed.merchantName),
            NSPredicate(format: "productName == %@", parsed.draft.productName),
            NSPredicate(format: "purchaseDate >= %@ AND purchaseDate <= %@", parsed.draft.purchaseDate.addingTimeInterval(-60 * 60 * 24 * 7) as NSDate, parsed.draft.purchaseDate.addingTimeInterval(60 * 60 * 24 * 7) as NSDate)
        ])
        return try context.fetch(fallbackRequest).first
    }

    private static func merge(parsed: GmailParsedPurchase, into record: PurchaseRecord) {
        let draft = parsed.draft
        let windows = draft.windows

        record.productName = preferredValue(current: record.productName, incoming: draft.productName)
        record.merchantName = preferredValue(current: record.merchantName, incoming: draft.merchantName)
        record.categoryName = preferredValue(current: record.categoryName, incoming: draft.categoryName)
        record.familyOwner = preferredValue(current: record.familyOwner, incoming: draft.familyOwner)
        record.sourceType = "Email"
        record.notes = mergeNotes(existing: record.notes ?? "", incoming: draft.notes, stage: parsed.stage)
        record.currencyCode = preferredValue(current: record.currencyCode, incoming: draft.currencyCode)
        record.purchaseDate = min(record.purchaseDate ?? draft.purchaseDate, draft.purchaseDate)
        record.returnDeadline = chooseLaterLifecycleDate(existing: record.returnDeadline, incoming: windows.returnDeadline)
        record.warrantyExpiration = chooseLaterLifecycleDate(existing: record.warrantyExpiration, incoming: windows.warrantyExpiration)
        record.warrantyStatusRaw = preferredWarrantyStatus(existing: record.warrantyStatusRaw, incoming: draft.warrantyStatus.rawValue)
        record.returnExplanation = draft.returnExplanationText
        record.warrantyExplanation = draft.warrantyExplanationText
        record.createdAt = record.createdAt ?? .now
        record.price = max(record.price, draft.price)
        record.isArchived = false
        record.returnCompleted = false
        record.gmailOrderNumber = parsed.orderNumber ?? record.gmailOrderNumber
        record.gmailLifecycleStageRaw = preferredLifecycleStage(existing: record.gmailLifecycleStageRaw, incoming: parsed.stage.rawValue)
        mergeProof(from: parsed.draft, into: record)
    }

    private static func populate(record: PurchaseRecord, from parsed: GmailParsedPurchase, messageID: String) {
        let draft = parsed.draft
        let windows = draft.windows

        record.id = UUID()
        record.productName = draft.productName
        record.merchantName = draft.merchantName.isEmpty ? "Unknown merchant" : draft.merchantName
        record.categoryName = draft.categoryName
        record.familyOwner = draft.familyOwner
        record.sourceType = "Email"
        record.notes = draft.notes
        record.currencyCode = draft.currencyCode
        record.purchaseDate = draft.purchaseDate
        record.returnDeadline = windows.returnDeadline
        record.warrantyExpiration = windows.warrantyExpiration
        record.warrantyStatusRaw = draft.warrantyStatus.rawValue
        record.returnExplanation = draft.returnExplanationText
        record.warrantyExplanation = draft.warrantyExplanationText
        record.createdAt = .now
        record.price = draft.price
        record.isArchived = false
        record.returnCompleted = false
        record.externalProvider = "gmail"
        record.externalRecordID = messageID
        record.lastSyncedAt = .now
        record.gmailOrderNumber = parsed.orderNumber
        record.gmailLifecycleStageRaw = parsed.stage.rawValue
        record.proofPreviewData = draft.proofPreviewData
        record.proofDocumentData = draft.proofDocumentData
        record.proofDocumentType = draft.proofDocumentType.isEmpty ? nil : draft.proofDocumentType
        record.proofDocumentName = draft.proofDocumentName.isEmpty ? nil : draft.proofDocumentName
        record.proofHTMLData = draft.proofHTMLData
    }

    private static func preferredValue(current: String?, incoming: String) -> String {
        let currentValue = (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingValue = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentValue.isEmpty || currentValue == "Unknown merchant" || currentValue == "Untitled purchase" || currentValue == "Scanned purchase" {
            return incomingValue.isEmpty ? currentValue : incomingValue
        }
        return currentValue
    }

    private static func chooseLaterLifecycleDate(existing: Date?, incoming: Date?) -> Date? {
        switch (existing, incoming) {
        case (nil, let incoming):
            return incoming
        case (let existing, nil):
            return existing
        case let (existing?, incoming?):
            return max(existing, incoming)
        }
    }

    private static func preferredWarrantyStatus(existing: String?, incoming: String) -> String {
        let existingStatus = WarrantyStatus(rawValue: existing ?? "") ?? .none
        let incomingStatus = WarrantyStatus(rawValue: incoming) ?? .none

        if incomingStatus == .confirmed || existingStatus == .none {
            return incoming
        }

        return existing ?? incoming
    }

    private static func preferredLifecycleStage(existing: String?, incoming: String) -> String {
        let existingStage = GmailOrderStage(rawValue: existing ?? "") ?? .unknown
        let incomingStage = GmailOrderStage(rawValue: incoming) ?? .unknown
        let ordered: [GmailOrderStage] = [.unknown, .placed, .shipped, .delivered]

        let existingIndex = ordered.firstIndex(of: existingStage) ?? 0
        let incomingIndex = ordered.firstIndex(of: incomingStage) ?? 0
        return incomingIndex >= existingIndex ? incoming : (existing ?? incoming)
    }

    private static func mergeNotes(existing: String, incoming: String, stage: GmailOrderStage) -> String {
        var parts = existing
            .split(separator: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let incomingParts = incoming
            .split(separator: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for part in incomingParts {
            if !parts.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
                parts.append(part)
            }
        }

        let stageNote = stage.noteTitle
        if !parts.contains(where: { $0.caseInsensitiveCompare(stageNote) == .orderedSame }) {
            parts.append(stageNote)
        }

        return parts.joined(separator: " • ")
    }

    private static func mergeProof(from draft: ReceiptDraft, into record: PurchaseRecord) {
        if record.proofPreviewData == nil, let previewData = draft.proofPreviewData {
            record.proofPreviewData = previewData
        }

        if record.proofDocumentData == nil, let documentData = draft.proofDocumentData {
            record.proofDocumentData = documentData
        }

        if (record.proofDocumentType ?? "").isEmpty, !draft.proofDocumentType.isEmpty {
            record.proofDocumentType = draft.proofDocumentType
        }

        if (record.proofDocumentName ?? "").isEmpty, !draft.proofDocumentName.isEmpty {
            record.proofDocumentName = draft.proofDocumentName
        }

        if record.proofHTMLData == nil, let proofHTMLData = draft.proofHTMLData {
            record.proofHTMLData = proofHTMLData
        }
    }
}

struct GmailImportSummary {
    let imported: Int
    let updated: Int
    let skipped: Int

    var statusLine: String {
        "Imported \(imported), updated \(updated), skipped \(skipped) Gmail purchases."
    }
}

enum GmailSyncError: LocalizedError {
    case notConnected
    case missingRefreshToken
    case authorizationCancelled
    case authorizationRejected(String)
    case invalidAuthorizationResponse
    case invalidState
    case unableToStartAuthorization
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect Gmail before trying to sync purchases."
        case .missingRefreshToken:
            return "Google did not return offline access. Try connecting Gmail again."
        case .authorizationCancelled:
            return "Gmail sign-in was cancelled."
        case .authorizationRejected(let reason):
            return "Google rejected the sign-in request: \(reason)."
        case .invalidAuthorizationResponse:
            return "Keep Sure could not finish the Google sign-in flow."
        case .invalidState:
            return "Google sign-in returned mismatched state. Please try again."
        case .unableToStartAuthorization:
            return "Keep Sure could not open the Google sign-in flow."
        case .serverError(let message):
            return message
        }
    }
}

private extension String {
    var urlEscaped: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
