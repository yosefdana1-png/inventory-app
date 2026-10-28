# Apple Watch app for "ניהול מלאי": plan and prompt for the Xcode agent

Copy everything below the line into the Claude agent in Xcode.

---

## Goal

Add a lightweight **watchOS companion app** to the existing iOS app in this project. Its main job is to **add and remove item quantities** quickly from the wrist. It is a separate native SwiftUI app, because the iPhone app is a Capacitor web app (`docs/index.html` in a WKWebView) and watchOS has no WebView. The watch talks **directly** to the same Firebase backend over HTTPS (REST), so it works with or without the iPhone nearby.

Do not change anything in `docs/`, in the Capacitor setup, or in the Android project. Only add the watch target and its Swift files.

## Project facts (do not guess; use exactly these)

- Xcode project: `ios/App/App.xcodeproj`. The iOS app target is `App`, bundle id `com.yosefdana.inventoryapp`.
- UI language: **Hebrew, right-to-left**. All strings in Hebrew. Force RTL with `.environment(\.layoutDirection, .rightToLeft)` at the root.
- Design (matches the current iPhone app, a calm dark design with ONE gold accent): background `#0F1012`, surface/cards `#17181B`, pressed `#1D1F22`, borders `#26282C`, text `#ECE9E2`, secondary text `#A3A099`, muted `#6F6D69`, gold accent `#C6A15B` (text on gold: `#0F1012`). Status colours only when they mean something: out of stock `#C4685C`, low stock `#C98B4E`. Corner radius 8. No blue anywhere, and no bright green/red buttons: + and − are neutral (surface background, text colour), the accent is used only for the main action and highlights.

### Firebase (public web config, safe to embed)

- Web API key: `AIzaSyB01z8Qw-wxnVuHnOEiHdhrtCo_SEUKn5U`
- Realtime Database URL: `https://inventory-app-d539d-default-rtdb.europe-west1.firebasedatabase.app`
- Do **not** add the Firebase SDK. Use `URLSession` with the REST APIs below. This keeps the watch app small and avoids SDK support issues on watchOS.

### Authentication (must match the web app exactly, or login will fail)

Users log in with a **username + password**. Behind the scenes it is Firebase email/password auth with a synthetic email:

1. `username = input.trimmingCharacters(in: .whitespaces).lowercased()`
2. Email:
   - If `username` matches `^[a-z0-9._-]+$` → `"\(username)@inv-user.app"`
   - Otherwise → `"u-" + base32(utf8Bytes(username)) + "@inv-user.app"`, where base32 uses the alphabet `abcdefghijklmnopqrstuvwxyz234567`, lowercase, **no padding**. Port this JS exactly:
     ```js
     const b32enc=bytes=>{const A="abcdefghijklmnopqrstuvwxyz234567";let bits=0,val=0,out="";
       for(const b of bytes){val=(val<<8)|b;bits+=8;while(bits>=5){out+=A[(val>>>(bits-5))&31];bits-=5}}
       if(bits>0)out+=A[(val<<(5-bits))&31];return out};
     ```
3. Password: if shorter than 6 characters, **pad with zeros** up to 6 (`"1234"` → `"123400"`). Otherwise use it as typed.
4. Sign in: `POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=API_KEY` with body `{"email":…,"password":…,"returnSecureToken":true}` → `idToken` (valid 1 hour), `refreshToken`, `localId`.
5. Refresh: `POST https://securetoken.googleapis.com/v1/token?key=API_KEY` with form body `grant_type=refresh_token&refresh_token=…` → new `id_token`.
6. Store `username` and `refreshToken` in the **Keychain**, so the user logs in only once. Refresh the ID token automatically before it expires, and once more on a 401 response.
7. Show error messages in Hebrew: wrong details → "שם משתמש או סיסמה שגויים"; network → "אין חיבור לאינטרנט".

Login screen: two fields, "שם משתמש" and "סיסמה" (`SecureField`), and a "התחבר" button. watchOS lets the user type with the iPhone keyboard, dictation or Scribble, so no extra pairing code is needed in this version.

### Database reads (REST, append `?auth=ID_TOKEN` to every request)

- Display name: `GET /users/{username}/displayName.json`
- The user's warehouses: `GET /users/{username}/warehouses.json` → object `{ whId: orderNumber }`. Sort by the number.
- Warehouse name (for the list): `GET /warehouses/{whId}/name.json`. Fetch the names in parallel.
- Warehouse settings: `GET /warehouses/{whId}/features.json` (may be null) and `GET /warehouses/{whId}/sortMode.json` (may be null).
- Items: `GET /warehouses/{whId}/items.json` → object `{ itemId: { name, quantity, order, sku?, lowStock?, note?, history: {...} } }`. Ignore `history` on the watch.
- Sorting: if `sortMode == "name"`, sort by name (Hebrew locale). Otherwise sort by `order` ascending.

### Changing a quantity (must match the web app exactly)

The web app does an **atomic** update. Do the same, with a single PATCH:

`PATCH /warehouses/{whId}.json?auth=ID_TOKEN`
```json
{
  "items/{itemId}/quantity": {".sv": {"increment": DELTA}},
  "items/{itemId}/history/{NEW_ID}": {
    "action": "הוספה",
    "amount": 3,
    "result": 12,
    "by": "<displayName>",
    "date": "<ISO-8601 UTC, e.g. 2026-10-21T09:41:00.000Z>"
  }
}
```
- `action` is `"הוספה"` for adding and `"הורדה"` for removing. `amount` is always positive.
- Quantity can never go below 0. Before writing, read the fresh value with `GET /warehouses/{whId}/items/{itemId}/quantity.json`. For removing, use `DELTA = -min(amount, current)`, and skip the write if `DELTA == 0`. `result = current + DELTA`.
- `NEW_ID`: a unique id built like the web app: `base36(milliseconds since 1970) + 5 random base36 chars`.

### Low stock (optional display only)

If `features.showLowStock == true` and the item has `lowStock`: show the quantity in `#C98B4E` when `quantity <= lowStock`, and in `#C4685C` when `quantity == 0`. Otherwise show it in the normal text colour.

## Screens

1. **Login** (only when there is no saved session).
2. **Warehouses**: a list of warehouse names. Toolbar: refresh. Long press or a menu item: "התנתק", which clears the Keychain.
3. **Items** in a warehouse: each row shows the name and the quantity (colored as above). A search field at the top is nice to have. Pull to refresh.
4. **Item**: a large quantity number in the center, a big **−** button and a big **+** button (neutral style, see Design), and the item name at the top.
   - Each tap changes a *pending* amount (shown as "+3" or "−2" under the number) with a light haptic.
   - After **1.5 seconds without taps**, send **one** update with the total (one history line, not one per tap), then play a success haptic.
   - The Digital Crown also adjusts the pending amount (one step per detent).
   - On failure, show "לא נשמר — נסה שוב" and restore the number.

Keep the screens simple and readable at a glance. Use the brand colors on a dark background.

## Technical requirements

- In Xcode: **File → New → Target → watchOS → App**, as a **Watch App for the existing iOS app `App`** (companion, embedded in the iOS app). Product name `Inventory Watch`. Bundle id `com.yosefdana.inventoryapp.watchkitapp`. Display name `מלאי`.
- Minimum watchOS: the lowest version that the current Xcode SDK supports without warnings, but not below watchOS 10.
- SwiftUI + `async/await`. No third-party packages.
- Code structure: `FirebaseAuthClient` (sign in, refresh, Keychain), `DatabaseClient` (GET and PATCH helpers that attach the token and retry once on 401), models (`Warehouse`, `Item`), and one SwiftUI view per screen.
- App icon: reuse the existing app icon artwork for the watch icon set.
- After every warehouse or item refresh, cache the last result in memory, so going back is instant.
- Do not log the password or tokens.

## Done when

1. The project builds for both the iPhone and the Apple Watch simulator.
2. On the watch simulator I can log in with an existing account, see my warehouses, open one, and change a quantity.
3. The change appears in the iPhone app and on the website, with a history line "הוספה" or "הורדה" under my display name.
4. Removing more than the current quantity stops at 0.

When you finish, give me a short summary of what you added and anything I need to do by hand (signing team for the new target, etc.).
