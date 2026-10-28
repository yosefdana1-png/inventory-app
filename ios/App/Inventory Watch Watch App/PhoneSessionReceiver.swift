//
//  PhoneSessionReceiver.swift
//  Inventory Watch Watch App
//

import Foundation
import WatchConnectivity

/// A login handed over by the iPhone app.
struct PhoneLogin: Sendable {
    let username: String
    let displayName: String?
    let refreshToken: String
    /// When the iPhone sent it (seconds since 1970, the context's `ts`).
    let sentAt: Double?
    /// True when sent from "חבר את השעון לחשבון הזה" on the iPhone; automatic
    /// sends (app start, account switch on the iPhone) are false.
    let manual: Bool
}

/// Receives the iPhone app's current login over WatchConnectivity
/// (sent by the `WatchLink` Capacitor plugin as an application context).
nonisolated final class PhoneSessionReceiver: NSObject, WCSessionDelegate {
    private let onLogin: @Sendable (PhoneLogin) -> Void

    init(onLogin: @escaping @Sendable (PhoneLogin) -> Void) {
        self.onLogin = onLogin
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        // A context sent while the watch app was closed is waiting here.
        handle(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    private func handle(_ context: [String: Any]) {
        guard let username = context["username"] as? String, !username.isEmpty,
              let refreshToken = context["refreshToken"] as? String, !refreshToken.isEmpty else { return }
        let displayName = context["displayName"] as? String
        let sentAt = (context["ts"] as? NSNumber)?.doubleValue
        let manual = (context["manual"] as? NSNumber)?.boolValue ?? false
        onLogin(PhoneLogin(username: username, displayName: displayName, refreshToken: refreshToken, sentAt: sentAt, manual: manual))
    }
}
