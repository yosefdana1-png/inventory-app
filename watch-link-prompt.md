Add automatic Apple Watch sign-in: the iPhone app hands its current login to the watch app, so the user never types a password on the watch.

## Background (already done, do not change)

`docs/index.html` (the web app inside Capacitor) now calls a native Capacitor plugin named **`WatchLink`** if it exists:
- `WatchLink.send({ username, displayName, refreshToken })` → must resolve with `{ sent: true }` when the data was handed to WatchConnectivity, or `{ sent: false }` when there is no paired watch or the watch app is not installed.
- It is called automatically every time the iPhone app starts signed in (and after switching accounts), and also from a "חבר את השעון" button in Settings.
- `refreshToken` is the Firebase Auth refresh token of the signed-in user (same Firebase project the watch app already uses).

Do not edit anything in `docs/`, the Android project or the Capacitor config.

## Part 1: iPhone app (target `App`)

1. Create `WatchLinkPlugin.swift` in the `App` target: a Capacitor plugin (`CAPPlugin`, `CAPBridgedPlugin`) with `identifier = "WatchLinkPlugin"`, `jsName = "WatchLink"`, and one method `send` (returns a promise).
   - Activate `WCSession.default` once (set a delegate, call `activate()`).
   - In `send`: read `username`, `displayName`, `refreshToken` from the call. If `WCSession.isSupported()`, the session is activated, `isPaired` and `isWatchAppInstalled` are all true → call `updateApplicationContext(["username": …, "displayName": …, "refreshToken": …, "ts": Date().timeIntervalSince1970])` and resolve `["sent": true]`. Otherwise resolve `["sent": false]`. If the session is not activated yet, wait for activation (up to ~3 seconds) before deciding.
   - Never log the token.
2. Register the plugin. This is a local plugin (not an npm package), so register it in code:
   - Create `MainViewController.swift`: `class MainViewController: CAPBridgeViewController { override open func capacitorDidLoad() { bridge?.registerPluginInstance(WatchLinkPlugin()) } }`
   - In `Main.storyboard`, change the root view controller's custom class from `CAPBridgeViewController` to `MainViewController` (module: App).
3. Make sure `npx cap sync ios` does not overwrite these files (they live in the app target, not in `public/`).

## Part 2: Watch app (the existing watch target)

1. Add a `WatchConnectivity` receiver: activate `WCSession.default` at app launch with a delegate.
2. On `session(_:didReceiveApplicationContext:)`, and also right after activation using `session.receivedApplicationContext` (in case the context arrived while the app was closed):
   - Read `username`, `displayName`, `refreshToken`.
   - Save `username` and `refreshToken` to the Keychain using the existing `FirebaseAuthClient` storage, then exchange the refresh token for an ID token with the existing refresh call (`securetoken.googleapis.com/v1/token`).
   - If that works, switch the UI to the warehouses screen (on the main actor) and reload the data. If the same user is already signed in, just update the stored token quietly.
   - If a **different** username arrives, replace the old session (the watch follows the account that is active on the iPhone), clear the in-memory cache, and reload.
   - If the refresh fails, keep the current state and do nothing visible.
3. Login screen on the watch: above the manual fields, add the line "פתח את האפליקציה באייפון כדי להתחבר אוטומטית". Keep manual login as a fallback.

## Done when

1. Both the iPhone app and the watch app build.
2. With the iPhone simulator paired to the watch simulator: signing in on the iPhone app makes the watch app sign in by itself within a few seconds, without typing.
3. Tapping "חבר את השעון" in Settings on the iPhone shows "פרטי ההתחברות נשלחו לשעון".
4. Switching accounts on the iPhone (tap the name under "ניהול מלאי") makes the watch switch to that account too.
5. Manual login on the watch still works.

Give me a short summary at the end, including anything I must do by hand (for example, pairing the iPhone and watch simulators).
