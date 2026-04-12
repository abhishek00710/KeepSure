import AuthenticationServices
import Combine
import CoreData
import CryptoKit
import Foundation
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
        lastSyncAt = defaults.object(forKey: DefaultsKeys.lastSyncAt) as? Date
        if tokenStore.load() == nil {
            connectedEmail = nil
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
            defaults.set(profile.email, forKey: DefaultsKeys.connectedEmail)
            statusMessage = "Connected Gmail for \(profile.email)."

            await syncInbox()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func disconnect() {
        tokenStore.clear()
        connectedEmail = nil
        lastSyncAt = nil
        statusMessage = "Gmail disconnected."
        defaults.removeObject(forKey: DefaultsKeys.connectedEmail)
        defaults.removeObject(forKey: DefaultsKeys.lastSyncAt)
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

            let syncDate = Date()
            lastSyncAt = syncDate
            defaults.set(syncDate, forKey: DefaultsKeys.lastSyncAt)

            statusMessage = summary.statusLine
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
    let date: Date?
}

private struct GmailUserProfile: Decodable {
    let email: String
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

    private func collectText(into chunks: inout [String]) {
        let mime = mimeType?.lowercased() ?? ""

        if mime == "text/plain" || (parts == nil && body?.data != nil && mime != "text/html") {
            if let text = body?.decodedString, !text.isEmpty {
                chunks.append(text)
            }
        } else if mime == "text/html" {
            if let html = body?.decodedString {
                let plain = html
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                chunks.append(plain)
            }
        }

        for part in parts ?? [] {
            part.collectText(into: &chunks)
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
    static func draft(from message: GmailMessage) -> ReceiptDraft? {
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
        let merchant = inferMerchant(from: message.from) ?? draft.merchantName
        let product = inferProduct(from: message.subject, merchant: merchant)

        if !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.merchantName = merchant
        }
        if let product, !product.isEmpty {
            draft.productName = product
        }
        if let messageDate = message.date {
            draft.purchaseDate = messageDate
        }

        draft.sourceType = "Email"
        draft.notes = "Imported from Gmail: \(message.subject)"
        draft.recognizedText = combinedText
        draft.pageCount = 1

        return draft
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

    private static func inferProduct(from subject: String, merchant: String) -> String? {
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
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-"))

        return cleaned.isEmpty ? nil : cleaned
    }
}

private enum GmailPurchaseImporter {
    static func importMessages(_ messages: [GmailMessage], in context: NSManagedObjectContext) throws -> GmailImportSummary {
        var imported = 0
        var updated = 0
        var skipped = 0

        for message in messages {
            if let existing = try existingRecord(for: message.id, in: context) {
                existing.lastSyncedAt = .now
                updated += 1
                continue
            }

            guard let draft = GmailPurchaseParser.draft(from: message) else {
                skipped += 1
                continue
            }

            let record = PurchaseRecord(context: context)
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
            record.createdAt = .now
            record.price = draft.price
            record.isArchived = false
            record.externalProvider = "gmail"
            record.externalRecordID = message.id
            record.lastSyncedAt = .now

            imported += 1
        }

        return GmailImportSummary(imported: imported, updated: updated, skipped: skipped)
    }

    private static func existingRecord(for messageID: String, in context: NSManagedObjectContext) throws -> PurchaseRecord? {
        let request = PurchaseRecord.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "externalProvider == %@ AND externalRecordID == %@", "gmail", messageID)
        return try context.fetch(request).first
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
