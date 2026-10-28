//
//  AppModel.swift
//  Inventory Watch Watch App
//

import Foundation
import Observation

/// App-wide state: the saved accounts and the active one, plus in-memory caches
/// of the last loaded warehouses and items so navigating back is instant.
@Observable
final class AppModel {
    private(set) var isLoggedIn: Bool
    private(set) var displayName: String?
    /// Accounts saved on this watch, for "החלף חשבון".
    private(set) var accounts: [StoredAccount] = []
    private(set) var activeUsername: String?

    private(set) var warehouses: [Warehouse]?
    private(set) var items: [String: [Item]] = [:]
    private(set) var settings: [String: WarehouseSettings] = [:]

    /// Changes whenever a different account becomes active, so the UI resets
    /// its navigation instead of showing screens from the previous account.
    private(set) var sessionID = UUID()

    /// Shown on the login screen after the watch was signed out remotely.
    private(set) var signedOutMessage: String?
    /// Short notice on the warehouses screen (e.g. another account was disconnected).
    private(set) var notice: String?

    @ObservationIgnored private let auth = FirebaseAuthClient()
    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Refreshes `lastSeen` while the app is active.
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private lazy var db = DatabaseClient(auth: auth)
    @ObservationIgnored private var phoneLink: PhoneSessionReceiver?
    /// Logins from the iPhone are applied one after another, in arrival order.
    @ObservationIgnored private var phoneLoginTask: Task<Void, Never>?

    init() {
        isLoggedIn = auth.hasSession
        refreshAccountState()
        displayName = auth.activeAccount?.displayName
        let link = PhoneSessionReceiver { [self] login in
            Task { @MainActor in self.enqueuePhoneLogin(login) }
        }
        phoneLink = link
        link.start()
    }

    var username: String? { auth.username }

    /// Mirrors the auth client's account list into observable state.
    private func refreshAccountState() {
        accounts = auth.accounts
        activeUsername = auth.username
        isLoggedIn = auth.hasSession
    }

    private func clearCaches() {
        warehouses = nil
        items = [:]
        settings = [:]
    }

    // MARK: - Session

    /// Manual sign-in. Adds the account to the watch (or updates it) and makes it active.
    func logIn(username: String, password: String) async throws {
        let previous = auth.username
        try await auth.signIn(username: username, password: password)
        signedOutMessage = nil
        await activated(previous: previous)
    }

    /// "החלף חשבון": switches to a saved account without a password.
    /// Returns an error message to show, or nil on success.
    func switchAccount(to username: String) async -> String? {
        guard username != auth.username else { return nil }
        let previous = auth.username
        do {
            try await auth.switchTo(username)
        } catch {
            refreshAccountState()
            if case AppError.sessionExpired = error { return "החיבור לחשבון פג — התחבר אליו מחדש" }
            return (error as? LocalizedError)?.errorDescription ?? AppError.network.localizedDescription
        }
        await activated(previous: previous)
        return nil
    }

    /// Removes a saved account from the watch. The active account is signed out
    /// the same way as "התנתק".
    func removeAccount(_ username: String) async {
        if username == auth.username {
            await signOut()
            return
        }
        // Deleting under another account needs that account's own token.
        try? await db.delete(devicePath(for: username), account: username)
        defaults.removeObject(forKey: registeredKey(for: username))
        markPhoneLoginsHandled(upTo: Date().timeIntervalSince1970)
        auth.removeAccount(username)
        refreshAccountState()
    }

    /// Manual "התנתק" on the watch, for the active account: tells the iPhone not
    /// to re-connect automatically, removes this watch from the account's
    /// connected devices (the token is still valid), then removes the account.
    func signOut() async {
        guard let username = auth.username else { return }
        // "חבר את השעון" on the iPhone clears it. PATCH keeps the other prefs.
        try? await db.patch("users/\(username)/prefs", values: ["watchUnlinked": true])
        try? await db.delete(devicePath(for: username))
        defaults.removeObject(forKey: registeredKey(for: username))
        markPhoneLoginsHandled(upTo: Date().timeIntervalSince1970)
        auth.removeAccount(username)
        await activeAccountGone(message: nil)
    }

    /// After an account became active: reset caches if it is a different
    /// account, register this watch under it, start the heartbeat, reload.
    private func activated(previous: String?) async {
        let changed = previous != auth.username
        if changed {
            clearCaches()
            sessionID = UUID()
        }
        refreshAccountState()
        displayName = auth.activeAccount?.displayName
        if displayName == nil { await loadDisplayName() }
        await syncDeviceEntry(fromTimer: false)
        guard isLoggedIn else { return }
        startHeartbeat()
        if changed { try? await refreshWarehouses() }
    }

    /// The active account was removed (signed out, disconnected or revoked).
    /// Continues with another saved account if there is one, otherwise shows
    /// the login screen (with `message`, if given).
    private func activeAccountGone(message: String?) async {
        stopHeartbeat()
        clearCaches()
        displayName = nil
        refreshAccountState()
        if let next = auth.accounts.first {
            // No network needed: its ID token is fetched on the first request.
            auth.activateWithoutRefresh(next.username)
            await activated(previous: nil)
            if let message, isLoggedIn { show(notice: message) }
            if isLoggedIn { return }
        }
        refreshAccountState()
        signedOutMessage = message
    }

    private func show(notice text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(8))
            if notice == text { notice = nil }
        }
    }

    // MARK: - Login handed over by the iPhone

    private func enqueuePhoneLogin(_ login: PhoneLogin) {
        let previous = phoneLoginTask
        phoneLoginTask = Task {
            await previous?.value
            await applyPhoneLogin(login)
        }
    }

    /// The watch never follows an account switch on the iPhone automatically:
    /// - no active account on the watch → add it and make it active (first sign-in);
    /// - `manual` ("חבר את השעון לחשבון הזה") → add/update it and make it active;
    /// - otherwise → only refresh the token of that account if it is already saved.
    /// The token is validated first; if that fails nothing visible changes.
    private func applyPhoneLogin(_ login: PhoneLogin) async {
        let username = FirebaseAuthClient.normalizedUsername(login.username)
        guard !username.isEmpty else { return }
        // Each iPhone message is handled once. The last one is replayed on every
        // launch, and one sent before an account was removed is stale.
        let sentAt = login.sentAt ?? 0
        if let cutoff = phoneLoginCutoff, sentAt <= cutoff { return }
        let phoneDisplayName = login.displayName?.isEmpty == false ? login.displayName : nil

        if !isLoggedIn || login.manual {
            if isLoggedIn, auth.username == username, auth.hasStored(username: username, refreshToken: login.refreshToken) {
                auth.updateDisplayName(phoneDisplayName, for: username)
                if let phoneDisplayName { displayName = phoneDisplayName }
                markPhoneLoginsHandled(upTo: sentAt)
                return
            }
            let previous = auth.username
            do {
                try await auth.adopt(username: username, refreshToken: login.refreshToken,
                                     displayName: phoneDisplayName, makeActive: true)
            } catch {
                // Offline: leave it for the next launch. Invalid token: drop it.
                if case AppError.network = error { return }
                markPhoneLoginsHandled(upTo: sentAt)
                return
            }
            markPhoneLoginsHandled(upTo: sentAt)
            signedOutMessage = nil
            await activated(previous: previous)
            return
        }

        // Automatic send while an account is active: never change the active account.
        defer { markPhoneLoginsHandled(upTo: sentAt) }
        guard auth.account(username) != nil else { return }
        if !auth.hasStored(username: username, refreshToken: login.refreshToken) {
            try? await auth.adopt(username: username, refreshToken: login.refreshToken,
                                  displayName: phoneDisplayName, makeActive: false)
        } else {
            auth.updateDisplayName(phoneDisplayName, for: username)
        }
        if username == auth.username, let phoneDisplayName { displayName = phoneDisplayName }
        refreshAccountState()
    }

    /// iPhone logins sent at or before this time are ignored (seconds since 1970).
    private var phoneLoginCutoff: Double? {
        defaults.object(forKey: "ignorePhoneLoginsBefore") as? Double
    }

    private func markPhoneLoginsHandled(upTo time: Double) {
        guard time > (phoneLoginCutoff ?? 0) else { return }
        defaults.set(time, forKey: "ignorePhoneLoginsBefore")
    }

    // MARK: - Connected devices

    /// users/{username}/devices/{id}, the same list the iPhone app and website show.
    /// Every saved account registers this watch under the same id.
    private func devicePath(for username: String) -> String {
        "users/\(username)/devices/\(Self.deviceID)"
    }

    /// "Registered once" flag, per username.
    private func registeredKey(for username: String) -> String {
        "deviceRegistered.\(username)"
    }

    /// Random id for this watch, generated once and never changed.
    private static let deviceID: String = {
        let key = "watchDeviceID"
        if let id = UserDefaults.standard.string(forKey: key), !id.isEmpty { return id }
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let id = String((0..<20).map { _ in chars.randomElement()! })
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    /// Checks the active account's entry for this watch and keeps it up to date.
    /// - If it was registered before and the entry is gone, the watch was
    ///   disconnected from that account elsewhere: remove only that account.
    /// - Otherwise write the entry (not from the timer, which never re-creates a
    ///   missing entry) and remember that it was registered.
    private func syncDeviceEntry(fromTimer: Bool) async {
        guard isLoggedIn, let username = auth.username else { return }
        let path = devicePath(for: username)
        let wasRegistered = defaults.bool(forKey: registeredKey(for: username))

        let entry: Any?
        do {
            entry = try await db.get(path)
        } catch {
            // Offline etc.: try again next time. A revoked session is handled.
            handle(error)
            return
        }
        // The account may have changed while waiting.
        guard isLoggedIn, auth.username == username else { return }

        if entry == nil {
            if wasRegistered {
                await disconnectedRemotely(username: username)
                return
            }
            // Never registered yet: the timer must not create it.
            if fromTimer { return }
        }

        do {
            try await db.patch(path, values: [
                "platform": "Apple Watch",
                "name": "Apple Watch",
                "app": "שעון",
                "lastSeen": Int64(Date().timeIntervalSince1970 * 1000),
            ])
            guard auth.username == username else { return }
            defaults.set(true, forKey: registeredKey(for: username))
        } catch {
            handle(error)
        }
    }

    private func disconnectedRemotely(username: String) async {
        defaults.removeObject(forKey: registeredKey(for: username))
        markPhoneLoginsHandled(upTo: Date().timeIntervalSince1970)
        auth.removeAccount(username)
        await activeAccountGone(message: "השעון נותק מהחשבון")
    }

    /// Called when the app becomes active: check/refresh the entry, then keep
    /// `lastSeen` fresh every 5 minutes while active.
    func appDidBecomeActive() async {
        await syncDeviceEntry(fromTimer: false)
        startHeartbeat()
    }

    func appDidResignActive() {
        stopHeartbeat()
    }

    private func startHeartbeat() {
        stopHeartbeat()
        guard isLoggedIn else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard !Task.isCancelled, let self, self.isLoggedIn else { return }
                await self.syncDeviceEntry(fromTimer: true)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// A revoked token removes the active account (the auth client already
    /// dropped it); continue with another saved account or the login screen.
    /// Returns the error to show.
    @discardableResult
    func handle(_ error: Error) -> String {
        if case AppError.sessionExpired = error, !auth.hasSession {
            refreshAccountState()
            Task { await activeAccountGone(message: nil) }
        }
        return (error as? LocalizedError)?.errorDescription ?? AppError.network.localizedDescription
    }

    private func loadDisplayName() async {
        guard let username = auth.username else { return }
        let name = try? await db.get("users/\(username)/displayName") as? String
        guard auth.username == username else { return }
        // Same fallback as the web app: no display name → the username.
        displayName = (name?.isEmpty == false ? name : nil) ?? username
        auth.updateDisplayName(name, for: username)
        refreshAccountState()
    }

    // MARK: - Warehouses

    func refreshWarehouses() async throws {
        guard let username = auth.username else { throw AppError.sessionExpired }
        if displayName == nil { await loadDisplayName() }

        let map = try await db.get("users/\(username)/warehouses") as? [String: Any] ?? [:]
        let ids = map.keys.map { (id: $0, order: JSONValue.double(map[$0]) ?? .greatestFiniteMagnitude) }

        // Fetch every name in parallel. A warehouse the user can no longer read is skipped.
        let names = await withTaskGroup(of: (String, String?).self) { group in
            for entry in ids {
                group.addTask { [db] in
                    (entry.id, try? await db.get("warehouses/\(entry.id)/name") as? String)
                }
            }
            var result: [String: String] = [:]
            for await (id, name) in group {
                if let name { result[id] = name }
            }
            return result
        }

        warehouses = ids
            .compactMap { entry in names[entry.id].map { Warehouse(id: entry.id, name: $0, order: entry.order) } }
            .sorted { $0.order != $1.order ? $0.order < $1.order : $0.name < $1.name }
    }

    // MARK: - Items

    func refreshItems(in warehouseID: String) async throws {
        async let featuresValue = db.get("warehouses/\(warehouseID)/features")
        async let sortModeValue = db.get("warehouses/\(warehouseID)/sortMode")
        async let itemsValue = db.get("warehouses/\(warehouseID)/items")

        let features = try await featuresValue as? [String: Any]
        let sortMode = try await sortModeValue as? String
        let raw = try await itemsValue as? [String: Any] ?? [:]

        let whSettings = WarehouseSettings(
            showLowStock: features?["showLowStock"] as? Bool == true,
            sortByName: sortMode == "name"
        )
        var list = raw.compactMap { Item(id: $0.key, json: $0.value) }
        if whSettings.sortByName {
            let hebrew = Locale(identifier: "he")
            list.sort { $0.name.compare($1.name, locale: hebrew) == .orderedAscending }
        } else {
            list.sort { $0.order != $1.order ? $0.order < $1.order : $0.name < $1.name }
        }
        settings[warehouseID] = whSettings
        items[warehouseID] = list
    }

    /// Reads the current quantity of one item, or `nil` if it was deleted.
    func freshQuantity(warehouseID: String, itemID: String) async throws -> Int? {
        // Not `shallow=true`: it truncates child values to `true`, which would read as 1.
        // The name read is only an existence check for an item deleted elsewhere.
        async let quantityValue = db.get("warehouses/\(warehouseID)/items/\(itemID)/quantity")
        async let nameValue = db.get("warehouses/\(warehouseID)/items/\(itemID)/name")
        let quantity = try await quantityValue
        let name = try await nameValue
        guard quantity != nil || name != nil else { return nil }
        return max(0, JSONValue.int(quantity) ?? 0)
    }

    /// Applies `amount` (positive = add, negative = remove) exactly like the web app:
    /// one atomic PATCH with a server-side increment and a single history entry.
    /// Removal is clamped so the quantity never drops below 0. Returns the new quantity.
    func changeQuantity(warehouseID: String, itemID: String, by amount: Int) async throws -> Int {
        guard amount != 0 else { throw AppError.server(0) }
        if displayName == nil { await loadDisplayName() }

        // The fresh read also confirms the item still exists, so a deleted item
        // is never re-created as an empty node.
        guard let current = try await freshQuantity(warehouseID: warehouseID, itemID: itemID) else {
            throw AppError.itemMissing
        }
        let delta = amount > 0 ? amount : -min(-amount, current)
        guard delta != 0 else {
            updateCachedQuantity(current, warehouseID: warehouseID, itemID: itemID)
            return current
        }
        let result = current + delta

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try await db.patch("warehouses/\(warehouseID)", values: [
            "items/\(itemID)/quantity": [".sv": ["increment": delta]],
            "items/\(itemID)/history/\(Self.newHistoryID())": [
                "action": delta > 0 ? "הוספה" : "הורדה",
                "amount": abs(delta),
                "result": result,
                "by": displayName ?? auth.username ?? "",
                "date": formatter.string(from: Date()),
            ] as [String: Any],
        ])
        updateCachedQuantity(result, warehouseID: warehouseID, itemID: itemID)
        return result
    }

    private func updateCachedQuantity(_ quantity: Int, warehouseID: String, itemID: String) {
        guard let index = items[warehouseID]?.firstIndex(where: { $0.id == itemID }) else { return }
        items[warehouseID]?[index].quantity = quantity
    }

    /// Same shape as the web app's `genId()`: base36 milliseconds + 5 random base36 characters.
    static func newHistoryID() -> String {
        let millis = Int64(Date().timeIntervalSince1970 * 1000)
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let suffix = String((0..<5).map { _ in alphabet.randomElement()! })
        return String(millis, radix: 36) + suffix
    }
}
