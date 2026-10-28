# טקסטים ונכסים ל‑Google Play — "מלאי"

## שלב 0 — לפני הכל: אימות מכשיר (פעם אחת)
בטלפון האנדרואיד: התקן מהחנות את **Google Play Console** (האפליקציה של גוגל למפתחים), התחבר עם אותו חשבון גוגל של חשבון המפתח, ועקוב אחרי האימות. אחרי זה, ב‑play.google.com/console במחשב, כפתור **Create app** נפתח.

## שלב 1 — Create app
| שדה | ערך |
|---|---|
| App name | מלאי — ניהול מלאי משותף |
| Default language | Hebrew — עברית (he-IL) |
| App or game | App |
| Free or paid | Free |
| Declarations | לסמן את שתי ההצהרות (Developer Program Policies, US export laws) |

## שלב 2 — Set up your app (הרשימה בדשבורד)
- **Privacy policy**: https://yosefdana1-png.github.io/inventory-app/privacy.html
- **App access**: "All or some functionality is restricted" → Add instructions: שם משתמש `applereview` (או משתמש בדיקה ייעודי לגוגל, למשל `googlereview`), הסיסמה, והערה: `Sign in with the credentials above. Sample inventories appear on the home screen.`
- **Ads**: No, the app does not contain ads.
- **Content rating**: Start questionnaire → Email → Category: **Utility, Productivity, Communication, or Other** → כל התשובות No → יוצא Everyone / 3+.
- **Target audience**: 18 and over (הכי פשוט; אם בוחרים קטינים נכנסים לדרישות נוספות). "Appeal to children": No.
- **News app**: No. **COVID‑19 contact tracing**: No. **Data safety** — ראה למטה. **Government app**: No. **Financial features**: No / none. **Health**: No.
- **App category**: Productivity. **Tags** (אופציונלי): Inventory, Lists.
- **Store settings → Contact details**: Email `danastudio.apps@gmail.com`, Website `https://yosefdana1-png.github.io/inventory-app/`.

## Data safety (השאלון של גוגל)
"Does your app collect or share any of the required user data types?" → **Yes**.
Encrypted in transit → Yes. Users can request deletion → Yes (דרך המייל, כתוב בעמוד התמיכה).

| סוג נתון | נאסף? | משותף? | חובה/אופציונלי | מטרה |
|---|---|---|---|---|
| Personal info → Name | Yes | No | Required | App functionality, Account management |
| Personal info → User IDs | Yes | No | Required | App functionality, Account management |
| Photos and videos → Photos | Yes | No | Optional | App functionality |
| App activity → Other user‑generated content | Yes | No | Required | App functionality |

לא נאסף: מיקום, אנשי קשר, מזהי מכשיר, נתוני שימוש/אנליטיקס, מידע פיננסי.

## שלב 3 — Main store listing
**App name (30)**
```
מלאי — ניהול מלאי משותף
```
**Short description (80)**
```
מחסנים משותפים למשפחה ולצוות: כמויות, התראות מלאי נמוך וספירת מלאי בזמן אמת.
```
**Full description (4000)** — אותו תיאור כמו ב‑App Store (הסקשן "תיאור" בקובץ `store/טקסטים-לחנות.md`).

**גרפיקה** (בתיקייה `play-assets`):
- App icon 512×512: `icon-512.png`
- Feature graphic 1024×500: `feature-he.png` (ואנגלית: `feature-en.png`)
- Phone screenshots (1080×1920, 9:16): התיקייה `he/` — 6 קבצים (מינימום 2). אנגלית ב‑`en/`.
- Tablet 7"/10" — לא חובה. אם רוצים, אפשר להשתמש בצילומי האייפד (2752×2064) מ‑`store/screenshots-ipad`.

**English localization (אופציונלי)** — Add language → English (United States): Name `Malai — Shared Inventory`, Short description `Shared stock lists for families and teams: quantities, low‑stock alerts and stock counts.`, Full description מהקובץ, screenshots מ‑`en/`.

## שלב 4 — הבנייה (AAB)
במק, בטרמינל:
```
cd ~/Desktop/"אפליקציה לניהול מלאי" && npx cap sync android && cd android && ./gradlew bundleRelease
```
הקובץ: `android/app/build/outputs/bundle/release/app-release.aab` (גרסה 1.1, versionCode 2 — כבר מוגדר).

## שלב 5 — Internal testing (למשפחה, בלי ביקורת)
Testing → **Internal testing** → Create new release → Upload את ה‑AAB → Release name נשאר אוטומטי → Release notes:
```
<he-IL>
גרסה ראשונה לאנדרואיד: מחסנים משותפים, התראות מלאי נמוך, ספירת מלאי, הצטרפות בקוד QR.
</he-IL>
```
→ Next → Save → **Testers** לשונית → Create email list → הוסף את המיילים (Gmail) של המשפחה → Save → העתק את **"Copy link"** ושלח להם. כל אחד נכנס לקישור, לוחץ "Become a tester", ואז מוריד מהחנות.

בפעם הראשונה גוגל יציעו **Play App Signing** — לאשר (Google מנהלת את מפתח החתימה הסופי; ה‑upload key שלנו נשאר בקובץ ה‑jks).

## שלב 6 — Production (חנות)
אחרי שהכל ירוק ב‑Dashboard: Production → Create new release → אפשר "Add from library" את אותה בנייה → Countries: Israel (או All) → Review release → **Start rollout to Production**. ביקורת גוגל: מכמה שעות עד כמה ימים; לחשבון חדש לפעמים עד שבוע.

הערה: לחשבונות אישיים שנפתחו אחרי נובמבר 2023 גוגל דורשים לפני Production בדיקה סגורה (Closed testing) עם **12 בודקים במשך 14 יום רצופים**. אם הדשבורד מציג את הדרישה הזאת — פותחים Closed testing במקום Internal, מוסיפים 12 מיילים (משפחה + חברים), ומחכים שבועיים. Internal testing עובד בכל מקרה מיד.
