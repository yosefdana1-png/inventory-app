//
//  FirebaseAuthClient.swift
//  Inventory Watch Watch App
//

import Foundation
import Security

enum FirebaseConfig {
    static let apiKey = "AIzaSyB01z8Qw-wxnVuHnOEiHdhrtCo_SEUKn5U"
    static let databaseURL = URL(string: "https://inventory-app-d539d-default-rtdb.europe-west1.firebasedatabase.app")!
}

enum AppError: LocalizedError {
    case invalidCredentials
    case tooManyAttempts
    case network
    /// The saved session is no longer valid (password changed, device disconnected, …).
    case sessionExpired
    case permissionDenied
    case itemMissing
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "שם משתמש או סיסמה שגויים"
        case .tooManyAttempts: "יותר מדי ניסיונות, נסה שוב מאוחר יותר"
        case .network: "אין חיבור לאינטרנט"
        case .sessionExpired: "החיבור פג, התחבר מחדש"
        case .permissionDenied: "אין הרשאה"
        case .itemMissing: "הפריט נמחק"
        case .server(let code): "שגיאת שרת (\(code))"
        }
    }
}

/// An account saved on the watch. Several can be saved; one is active.
struct StoredAccount: Codable, Hashable, Identifiable, Sendable {
    let username: String
    var displayName: String?
    var refreshToken: String

    var id: String { username }
    /// Same fallback as the web app: no display name → the username.
    var shownName: String { (displayName?.isEmpty == false ? displayName : nil) ?? username }
}

/// Firebase email/password auth over the Identity Toolkit REST API.
/// Users type a username; the synthetic email and password padding match the web app.
/// Keeps a list of saved accounts in the Keychain; only the active one holds an ID token.
final class FirebaseAuthClient {
    private(set) var accounts: [StoredAccount] = []
    /// The active account's username.
    private(set) var username: String?
    private var refreshToken: String? { account(username)?.refreshToken }
    private var idToken: String?
    private var idTokenExpiry = Date.distantPast
    /// Shared in-flight refresh, so parallel requests trigger only one refresh call.
    private var refreshTask: Task<String, Error>?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        loadAccounts()
    }

    var hasSession: Bool { username != nil && refreshToken != nil }
    var activeAccount: StoredAccount? { account(username) }

    func account(_ username: String?) -> StoredAccount? {
        guard let username else { return nil }
        return accounts.first { $0.username == username }
    }

    // MARK: - Sign in / out

    /// Manual sign-in: adds (or updates) the account and makes it active.
    func signIn(username input: String, password: String) async throws {
        let username = Self.normalizedUsername(input)
        guard !username.isEmpty, !password.isEmpty else { throw AppError.invalidCredentials }

        var request = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(FirebaseConfig.apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": Self.email(forUsername: username),
            "password": Self.authPassword(password),
            "returnSecureToken": true,
        ])

        let json = try await send(request)
        guard let idToken = json["idToken"] as? String,
              let refreshToken = json["refreshToken"] as? String else { throw AppError.server(0) }

        upsert(username: username, refreshToken: refreshToken, displayName: nil)
        self.username = username
        storeIDToken(idToken, expiresIn: json["expiresIn"])
        saveAccounts()
    }

    /// Removes an account from the watch. If it was the active one, no account is active afterwards.
    func removeAccount(_ username: String) {
        accounts.removeAll { $0.username == username }
        if self.username == username { deactivate() }
        saveAccounts()
    }

    func updateDisplayName(_ name: String?, for username: String) {
        guard let index = accounts.firstIndex(where: { $0.username == username }),
              let name, !name.isEmpty, accounts[index].displayName != name else { return }
        accounts[index].displayName = name
        saveAccounts()
    }

    // MARK: - ID token

    /// Returns an ID token for the active account, refreshing it when it expires
    /// within 5 minutes (or when forced after a 401).
    func validIDToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let idToken, idTokenExpiry.timeIntervalSinceNow > 300 {
            return idToken
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let username, let refreshToken else { throw AppError.sessionExpired }

        let result: TokenExchange
        do {
            result = try await exchange(refreshToken: refreshToken)
        } catch AppError.invalidCredentials, AppError.permissionDenied {
            // The refresh token was revoked (password changed, account disabled).
            // Only drop it if the active account wasn't switched while waiting.
            if self.username == username, self.refreshToken == refreshToken { removeAccount(username) }
            throw AppError.sessionExpired
        }
        guard self.username == username, self.refreshToken == refreshToken else {
            // Switched account (or signed out) while this refresh was in flight;
            // the switch already stored its own fresh ID token.
            guard let idToken else { throw AppError.sessionExpired }
            return idToken
        }
        if result.refreshToken != refreshToken {
            upsert(username: username, refreshToken: result.refreshToken, displayName: nil)
            saveAccounts()
        }
        storeIDToken(result.idToken, expiresIn: result.expiresIn)
        return result.idToken
    }

    /// An ID token for any saved account, without switching to it (e.g. to delete
    /// that account's device entry). The active account uses its normal token.
    func idToken(forAccount username: String) async throws -> String {
        if username == self.username { return try await validIDToken() }
        guard let stored = account(username) else { throw AppError.sessionExpired }
        let result = try await exchange(refreshToken: stored.refreshToken)
        if result.refreshToken != stored.refreshToken {
            upsert(username: username, refreshToken: result.refreshToken, displayName: nil)
            saveAccounts()
        }
        return result.idToken
    }

    // MARK: - Switching / logins handed over by the iPhone

    /// True when this username is saved with exactly this refresh token.
    func hasStored(username: String, refreshToken: String) -> Bool {
        account(username)?.refreshToken == refreshToken
    }

    /// Validates a refresh token (exchanges it for an ID token), then saves the
    /// account. With `makeActive` it also becomes the active account. On failure
    /// nothing changes.
    func adopt(username: String, refreshToken: String, displayName: String?, makeActive: Bool) async throws {
        let result = try await exchange(refreshToken: refreshToken)
        upsert(username: username, refreshToken: result.refreshToken, displayName: displayName)
        if makeActive || username == self.username {
            self.username = username
            storeIDToken(result.idToken, expiresIn: result.expiresIn)
        }
        saveAccounts()
    }

    /// Makes a saved account active, refreshing its ID token first. A revoked
    /// token removes the account and throws `sessionExpired`.
    func switchTo(_ username: String) async throws {
        guard let stored = account(username) else { throw AppError.sessionExpired }
        let result: TokenExchange
        do {
            result = try await exchange(refreshToken: stored.refreshToken)
        } catch AppError.invalidCredentials, AppError.permissionDenied {
            removeAccount(username)
            throw AppError.sessionExpired
        }
        upsert(username: username, refreshToken: result.refreshToken, displayName: nil)
        self.username = username
        storeIDToken(result.idToken, expiresIn: result.expiresIn)
        saveAccounts()
    }

    /// Makes a saved account active without a network call; its ID token is
    /// fetched on the first request (used after the active account was removed).
    func activateWithoutRefresh(_ username: String) {
        guard account(username) != nil else { return }
        self.username = username
        idToken = nil
        idTokenExpiry = .distantPast
        saveAccounts()
    }

    private struct TokenExchange {
        let idToken: String
        let refreshToken: String
        let expiresIn: Any?
    }

    /// Exchanges a refresh token for a new ID token (securetoken API). Does not change any state.
    private func exchange(refreshToken: String) async throws -> TokenExchange {
        var request = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(FirebaseConfig.apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let json = try await send(request)
        guard let idToken = json["id_token"] as? String else { throw AppError.server(0) }
        return TokenExchange(
            idToken: idToken,
            refreshToken: (json["refresh_token"] as? String) ?? refreshToken,
            expiresIn: json["expires_in"]
        )
    }

    private func storeIDToken(_ token: String, expiresIn: Any?) {
        idToken = token
        idTokenExpiry = Date().addingTimeInterval(JSONValue.double(expiresIn) ?? 3600)
    }

    private func deactivate() {
        username = nil
        idToken = nil
        idTokenExpiry = .distantPast
    }

    // MARK: - Storage

    /// Adds the account, or updates its token (and display name, if given).
    private func upsert(username: String, refreshToken: String, displayName: String?) {
        let name = displayName?.isEmpty == false ? displayName : nil
        if let index = accounts.firstIndex(where: { $0.username == username }) {
            accounts[index].refreshToken = refreshToken
            if let name { accounts[index].displayName = name }
        } else {
            accounts.append(StoredAccount(username: username, displayName: name, refreshToken: refreshToken))
        }
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts), let json = String(data: data, encoding: .utf8) {
            Keychain.save(json, for: .accounts)
        }
        if let username {
            Keychain.save(username, for: .activeUsername)
        } else {
            Keychain.delete(.activeUsername)
        }
    }

    private func loadAccounts() {
        if let json = Keychain.read(.accounts),
           let list = try? JSONDecoder().decode([StoredAccount].self, from: Data(json.utf8)) {
            accounts = list
        }
        // One-time migration from the single-account storage.
        if let oldUser = Keychain.read(.username), let oldToken = Keychain.read(.refreshToken) {
            if account(oldUser) == nil {
                accounts.append(StoredAccount(username: oldUser, displayName: nil, refreshToken: oldToken))
            }
            if Keychain.read(.activeUsername) == nil { Keychain.save(oldUser, for: .activeUsername) }
            Keychain.delete(.username)
            Keychain.delete(.refreshToken)
            saveAccountsListOnly()
        }
        let active = Keychain.read(.activeUsername)
        username = account(active) != nil ? active : nil
    }

    private func saveAccountsListOnly() {
        if let data = try? JSONEncoder().encode(accounts), let json = String(data: data, encoding: .utf8) {
            Keychain.save(json, for: .accounts)
        }
    }

    // MARK: - Networking

    /// Sends an auth request and maps Firebase error codes to `AppError`. Never logs bodies.
    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is URLError {
            throw AppError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? ""
            if message.hasPrefix("TOO_MANY_ATTEMPTS") { throw AppError.tooManyAttempts }
            let credentialErrors = ["INVALID_LOGIN_CREDENTIALS", "EMAIL_NOT_FOUND", "INVALID_PASSWORD",
                                    "INVALID_EMAIL", "USER_DISABLED", "USER_NOT_FOUND",
                                    "TOKEN_EXPIRED", "INVALID_REFRESH_TOKEN", "INVALID_GRANT_TYPE"]
            if credentialErrors.contains(where: message.hasPrefix) { throw AppError.invalidCredentials }
            if status == 401 || status == 403 { throw AppError.permissionDenied }
            throw AppError.server(status)
        }
        return json
    }

    // MARK: - Username → synthetic email (must match the web app exactly)

    static func normalizedUsername(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func email(forUsername username: String) -> String {
        if username.range(of: "^[a-z0-9._-]+$", options: .regularExpression) != nil {
            return "\(username)@inv-user.app"
        }
        return "u-\(base32(Array(username.utf8)))@inv-user.app"
    }

    /// Lowercase RFC 4648 base32 without padding — a direct port of the web app's `b32enc`.
    static func base32(_ bytes: [UInt8]) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var bits = 0
        var value: UInt32 = 0
        var output = ""
        for byte in bytes {
            value = (value << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[Int((value >> UInt32(bits - 5)) & 31)])
                bits -= 5
            }
        }
        if bits > 0 {
            output.append(alphabet[Int((value << UInt32(5 - bits)) & 31)])
        }
        return output
    }

    /// Firebase needs 6+ characters; legacy short passwords are padded with zeros ("1234" → "123400").
    static func authPassword(_ password: String) -> String {
        password.count >= 6 ? password : password + String(repeating: "0", count: 6 - password.count)
    }
}

// MARK: - Keychain

enum Keychain {
    enum Key: String {
        /// Saved accounts (JSON list).
        case accounts
        case activeUsername
        /// Legacy single-account keys, migrated on first launch.
        case username
        case refreshToken
    }

    private static let service = "com.yosefdana.inventoryapp.watchkitapp.session"

    private static func query(_ key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    static func save(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query(key).merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    static func read(_ key: Key) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: Key) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
