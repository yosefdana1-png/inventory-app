//
//  DatabaseClient.swift
//  Inventory Watch Watch App
//

import Foundation

/// Minimal Realtime Database REST client. Every request carries `?auth=ID_TOKEN`
/// and is retried once with a freshly refreshed token on 401.
final class DatabaseClient {
    private let auth: FirebaseAuthClient
    private let session: URLSession

    init(auth: FirebaseAuthClient, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    /// Reads the JSON value at `path`. Returns `nil` when the node does not exist.
    func get(_ path: String, shallow: Bool = false) async throws -> Any? {
        let data = try await send(path: path, method: "GET", body: nil, shallow: shallow)
        let value = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        return value is NSNull ? nil : value
    }

    /// Multi-path update. All keys are written atomically by the server.
    /// `account` writes as another saved account instead of the active one.
    func patch(_ path: String, values: [String: Any], account: String? = nil) async throws {
        let body = try JSONSerialization.data(withJSONObject: values)
        _ = try await send(path: path, method: "PATCH", body: body, shallow: false, account: account)
    }

    /// Removes the node at `path`. `account` deletes as another saved account.
    func delete(_ path: String, account: String? = nil) async throws {
        _ = try await send(path: path, method: "DELETE", body: nil, shallow: false, account: account)
    }

    private func send(path: String, method: String, body: Data?, shallow: Bool, account: String? = nil) async throws -> Data {
        // Another saved account: a one-off ID token for it, without switching.
        let otherAccount = account.flatMap { $0 == auth.username ? nil : $0 }
        var token = try await self.token(for: otherAccount, forceRefresh: false)
        for attempt in 0..<2 {
            var request = URLRequest(url: url(for: path, token: token, shallow: shallow))
            request.httpMethod = method
            request.httpBody = body
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is URLError {
                throw AppError.network
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return data }
            if status == 401 && attempt == 0 {
                token = try await self.token(for: otherAccount, forceRefresh: true)
                continue
            }
            // A second 401 with a fresh token means the rules deny access.
            throw status == 401 ? AppError.permissionDenied : AppError.server(status)
        }
        throw AppError.permissionDenied
    }

    private func token(for otherAccount: String?, forceRefresh: Bool) async throws -> String {
        if let otherAccount { return try await auth.idToken(forAccount: otherAccount) }
        return try await auth.validIDToken(forceRefresh: forceRefresh)
    }

    /// Builds `{databaseURL}/{path}.json?auth=…`, percent-encoding each segment
    /// (usernames may be Hebrew or contain spaces).
    private func url(for path: String, token: String, shallow: Bool) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encodedPath = path
            .split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "/")

        var components = URLComponents(url: FirebaseConfig.databaseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/" + encodedPath + ".json"
        var items = [URLQueryItem(name: "auth", value: token)]
        if shallow { items.append(URLQueryItem(name: "shallow", value: "true")) }
        components.queryItems = items
        return components.url!
    }
}
