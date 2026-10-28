import Foundation
import Capacitor
import WatchConnectivity

/// Hands the iPhone app's current login to the Apple Watch app over
/// WatchConnectivity, so the watch signs in without typing a password.
/// JS: `WatchLink.send({ username, displayName, refreshToken, manual })` → `{ sent: Bool }`.
/// The refresh token is never logged.
@objc(WatchLinkPlugin)
public class WatchLinkPlugin: CAPPlugin, CAPBridgedPlugin, WCSessionDelegate {
    public let identifier = "WatchLinkPlugin"
    public let jsName = "WatchLink"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "send", returnType: CAPPluginReturnPromise)
    ]

    /// How long `send` waits for the session to finish activating.
    private static let activationTimeout: TimeInterval = 3

    /// Actions waiting for activation. Only touched on the main queue.
    private var activationWaiters: [() -> Void] = []

    override public func load() {
        activateIfNeeded()
    }

    @objc func send(_ call: CAPPluginCall) {
        guard WCSession.isSupported(),
              let username = call.getString("username"), !username.isEmpty,
              let refreshToken = call.getString("refreshToken"), !refreshToken.isEmpty else {
            call.resolve(["sent": false])
            return
        }
        let displayName = call.getString("displayName") ?? username
        // true from "חבר את השעון לחשבון הזה"; automatic sends are false.
        let manual = call.getBool("manual") ?? false

        whenActivated {
            let session = WCSession.default
            guard session.activationState == .activated,
                  session.isPaired,
                  session.isWatchAppInstalled else {
                call.resolve(["sent": false])
                return
            }
            do {
                // `ts` makes every context unique, so it is delivered even if the login is unchanged.
                try session.updateApplicationContext([
                    "username": username,
                    "displayName": displayName,
                    "refreshToken": refreshToken,
                    "manual": manual,
                    "ts": Date().timeIntervalSince1970,
                ])
                call.resolve(["sent": true])
            } catch {
                call.resolve(["sent": false])
            }
        }
    }

    // MARK: - Activation

    private func activateIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate !== self { session.delegate = self }
        if session.activationState == .notActivated { session.activate() }
    }

    /// Runs `action` on the main queue once the session is activated, or after
    /// the timeout — whichever comes first. `action` runs exactly once.
    private func whenActivated(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            if WCSession.default.activationState == .activated {
                action()
                return
            }
            var didRun = false
            let runOnce = {
                guard !didRun else { return }
                didRun = true
                action()
            }
            self.activationWaiters.append(runOnce)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationTimeout, execute: runOnce)
            self.activateIfNeeded()
        }
    }

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            let waiters = self.activationWaiters
            self.activationWaiters.removeAll()
            waiters.forEach { $0() }
        }
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        // Called when the user switches to another watch; reactivate for the new one.
        session.activate()
    }
}
