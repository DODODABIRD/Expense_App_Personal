# Documentation

Technical reference for the whole repository. It describes the code as it is; when you change behaviour, update the matching section here (see `Rules.md` §3).

Contents:
1. [System overview](#1-system-overview)
2. [Flutter app](#2-flutter-app-frontendexpenseapp)
3. [Backend](#3-backend-backend)
4. [Configuration](#4-configuration)
5. [Deployment & operations](#5-deployment--operations)
6. [Testing](#6-testing)
7. [Known gaps and inconsistencies](#7-known-gaps-and-inconsistencies)

---

## 1. System overview

The repo holds two independent subprojects:

- **`frontend/expenseapp/`**: a Flutter expense tracker, shown on device as **UNMURCE** (pubspec version 2.0.0). Android-first; reads Android payment notifications to suggest expenses.
- **`backend/`**: a single Express 5 app that serves:
  - the JSON API used by the app (`/api/*`);
  - an admin panel (`/dodo`);
  - a public website: portfolio with an AI chatbot, an app download catalog, and a web version of the expense app.

```
                    ┌────────────────────────────┐
  Flutter app ──────►  backend (Express, Node 24) ├──► PostgreSQL
  (SQLite local) HTTP│  /api/*  /dodo  /  (static) │
       │             │  WS /ws, SSE /api/events    ├──► Groq API (LLM, vision)
       │             └──────────────┬─────────────┘──► Azure Document Intelligence
       │                            │               ──► open.er-api.com (FX rates)
       └──── Firebase Auth ◄────────┘ (Admin SDK verifies ID tokens)
  Browser (portfolio, /expenses web app, /dodo admin) ──► same backend
```

Default public host: `https://dododabird.us` (app defaults `https://dododabird.us/api` and `wss://dododabird.us/ws`). Firebase project: `unmurce-2f3e3`.

**Data ownership.** Each user's data is keyed by Firebase UID:
- `ownerId` in SQLite;
- `owner_id` in Postgres.

An expense is identified across devices by `(owner_id, local_id)`, where `local_id` is the SQLite row id. Amounts are integers in IDR.

---

## 2. Flutter app (`frontend/expenseapp/`)

### 2.1 Versions and dependencies

**Toolchain**
- Dart SDK `^3.11.0`.
- Flutter is the stable channel. `.metadata` records revision `90673a4e…` but no version number.

**Dependencies in use**

| Package | Used for |
|---|---|
| `firebase_core`, `firebase_auth` | Authentication |
| `sqflite`, `path_provider` | Local database and file paths |
| `http` | Backend API calls |
| `intl` | Formatting |
| `google_fonts` | Fonts |
| `image_picker` | Receipt photos |
| `pdf` | PDF export |
| `syncfusion_flutter_pdf` | PDF import |
| `file_picker` | Choosing files to import |
| `media_store_plus`, `file_saver`, `open_filex` | Saving and opening files |
| `share_plus` | Sharing |
| `android_intent_plus` | Android intents |
| `flutter_native_splash` | Splash screen (configured in pubspec only) |

**Declared but never imported:** `mongo_dart`, `objectid`, `flutter_svg`, `postgres`, `table_calendar`.

`package:path` is imported but comes in transitively; it is not declared.

**Assets**
- `assets/app_icon.png`, `assets/appiconv2.jpg` (launcher icon), `assets/splash_logo.png`, `lib/asset/JOJO.jpeg`.

**Android**
- Namespace / applicationId `com.example.expenseapp`; label `UNMURCE`.
- Java 17.
- Permissions: `INTERNET`, `CAMERA` (optional feature).
- `NotificationListener` service.
- Release signing reads `android/key.properties`, else falls back to the debug key.
- `android/app/google-services.json` is committed. There is no iOS `GoogleService-Info.plist`.

### 2.2 Boot and navigation

**`main()`** (`lib/main.dart`) runs these steps in order:
1. Install error handlers. `FlutterError.onError` and `PlatformDispatcher.onError` both log via `captureAppError`.
2. `initializeDateFormatting('id_ID')`.
3. `Firebase.initializeApp`.
4. Load the `theme_mode` setting.
5. `runApp`.

**Global state** (in `main.dart`):

| Notifier | Default |
|---|---|
| `appThemeMode` | `ThemeMode.light` |
| `appCurrency` | `'IDR'` |
| `appExchangeRate` | `1` |

The theme is Material 3, seeded from `#5DF9FF`.

**`AuthGate`** listens to `authStateChanges`:
- signed out → `AuthPage` (login, register, password reset; email required, password ≥ 6 chars);
- signed in → `HomePage2` (`hp2.dart`).

**`HomePage2`** is a 3-page `PageView` with a floating neo-brutalist bottom bar:

| Index | Page |
|---|---|
| 0 | Expense list (`ListWithCards`) |
| 1 | Embedded `ExpenseAddPage` |
| 2 | `SettingsPage` |

On start, `HomePage2`:
- restores the currency;
- loads the pending-notification count;
- starts the notification parser;
- shows the notification-permission onboarding once.

On app resume it reloads the pending count and restarts the parser.

**Navigation** (all pushes use `SmoothPageRoute`):

| From | To |
|---|---|
| Header receipt icon (badge, `99+` cap) | `PendingNotificationReviewPage` |
| Hero card "Details" | `ExpenseSumarryPage` |
| Expense card (list or analytics page) | `ExpenseEdit(expenseId)` |
| Add page scan button | `ReceiptScanPage` |
| Settings | `AiContextPage` |
| Easter egg | `DeveloperLogsPage` |

**Expense list**
- Filter sheet: category, type, date range.
- Sort: newest, oldest, highest, lowest.
- Pull-to-refresh.
- There is a `_searchQuery` field, but nothing sets it (dead code).

### 2.3 Pages

| Page | Behaviour |
|---|---|
| `auth_page.dart` | Login/register/reset with Indonesian error messages. |
| `ExpenseAddPage.dart` | Fields: name, amount (`#,###` id_ID formatting), quick-add buttons (+5k … +500k), 7 categories, type, date (`NeoBrutalistCalendar`). Saves via `DatabaseHelp.insertData`. |
| `ExpenseEdit.dart` | Loads with `getDataById`. Quick adjust buttons (+10k/+50k/+100k/-10k/-50k). Save → `updateTs`; delete → `deleteTs`. |
| `ExpenseSumarry.dart` | "Expense Analytics", described below. |
| `ReceiptScanPage.dart` | See §2.8. |
| `PendingNotificationReviewPage.dart` | Edit, approve or discard notification-parsed drafts. Approve moves the row into `my_table`. `needs_input` drafts show the raw notification text and an empty name/amount; approving needs a name and an amount > 0. The list is loaded once when the page opens. |
| `notification_permission_page.dart` | Indonesian onboarding. "Izinkan Akses Notifikasi" enables the parser and opens Android listener settings; "Nanti Saja" closes it. |
| `settings_page.dart` | Sections listed below. |
| `ai_context_page.dart` | "AI memory": shows the server's per-category notification template, with refresh. See §2.10. |
| `developer_logs_page.dart` | Lists error logs; refresh, export/share as text, delete all. |

**`ExpenseSumarry.dart` ("Expense Analytics")**
- Total.
- Last-7-days review.
- Category and type distribution (Terencana / Tak Terduga / Lainnya).
- Discipline warning when unexpected spending exceeds 35%.
- Outlier detector:
  - needs ≥ 3 expenses;
  - with fewer than 4 expenses, the threshold is mean + 1.5σ;
  - otherwise it is Q3 + 1.5·IQR (interpolated quartiles), falling back to σ when the IQR is 0;
  - an outlier must also be above the mean.

**`settings_page.dart` sections**

| Section | Contents |
|---|---|
| Data & sync | Pending count + retry, re-sync all, load online expenses, update/view AI notification reference, export PDF, import PDF, delete all |
| Preferences | Currency (IDR/USD/EUR), dark theme, expense reminders (stored only; nothing reads it) |
| Automation | Auto expense parser switch, allowed payment apps |
| Account | Change password, delete account |
| Signed-in account | Email and sign-out |
| About | Hard-coded "Version 2.0.0" |

### 2.4 Local database (SQLite)

File `my_db.db`, **version 7** (`lib/services/databaseHelper.dart`, class `DatabaseHelp`). `_ensureSettingsTable` runs on every open.

| Table | Columns |
|---|---|
| `my_table` (expenses) | `id INTEGER PK AUTOINCREMENT`, `mongoId TEXT`, `ownerId TEXT NOT NULL`, `name TEXT NOT NULL`, `amount INTEGER NOT NULL`, `date TEXT NOT NULL`, `category TEXT NOT NULL`, `type TEXT NOT NULL`, `synced INTEGER DEFAULT 0` |
| `app_settings` | `key TEXT PK`, `value TEXT NOT NULL` |
| `pending_notification_expenses` | `id INTEGER PK AUTOINCREMENT`, `ownerId`, `name`, `amount INTEGER`, `date`, `category`, `type`, `sourceApp`, `receivedAt` (all NOT NULL); since v7 also `rawTitle TEXT`, `rawText TEXT`, `notificationKey TEXT` (unique with `ownerId`), `status TEXT` (`ready` / `needs_input`, default `ready`), `aiStatus TEXT` (`pending` / `done` / `failed`, default `done`), `aiAttempts INTEGER`, `aiNextRetryAt INTEGER` (ms), `userEdited INTEGER` |

**Migrations (`onUpgrade`):**

| Upgrade from | Change |
|---|---|
| < 3 | Add `mongoId`, `synced` |
| < 4 | Add `ownerId` |
| < 5 | Create `app_settings` |
| < 6 | Create `pending_notification_expenses` |
| < 7 | Add the raw-text, key, `status`, AI-retry and `userEdited` columns to `pending_notification_expenses`, plus the unique index on `(ownerId, notificationKey)` |

**Legacy rows.** `assignLegacyExpensesToCurrentUser` adopts rows with `ownerId IS NULL` on every list load.

**`app_settings` keys:**

| Key | Value |
|---|---|
| `theme_mode` | `dark` / `light` |
| `currency` | `IDR` / `USD` / `EUR` |
| `rate_<CUR>` | Cached exchange rate |
| `device_id` | `<ms base36>-<hex>` |
| `notification_permission_onboarding_shown` | Set once the onboarding has been considered |
| `expense_reminders` | Stored only |
| `auto_expense_parser` | Anything except `'false'` means enabled |
| `notification_allowed_apps` | JSON list of packages, or `__all_notifications__` |
| `pending_cloud_notifications` | Legacy JSON retry queue. No longer written; leftover entries are converted into drafts once and the value becomes `[]` |

### 2.5 Backend client (`lib/services/ApiService.dart`, class `Throw`)

**Compile-time configuration** (`--dart-define`):

| Define | Default |
|---|---|
| `EXPENSE_API_BASE_URL` | `https://dododabird.us/api` |
| `EXPENSE_WS_URL` | `wss://dododabird.us/ws` |
| `EXPENSE_APP_VERSION` | `2.0.0` |

All calls send `Authorization: Bearer <Firebase ID token>`, except `getPublicConfig`. There is no HTTP retry.

| Method | HTTP | Timeout | Notes |
|---|---|---|---|
| `getOnlineExpenses` | GET `/users` | 15s | |
| `getExchangeRates` | GET `/exchange-rates` | 10s | Reads `rates` |
| `parseReceipt` | POST `/parse-receipt` `{image, mimeType}` | 45s (until response headers only) | Cancellable; handles the NDJSON stream |
| `parseNotification` | POST `/parse-notification` `{title, message, packageName}` | 30s | |
| `getAiNotificationReference` | GET `/ai-notification-reference` | 15s | |
| `saveAiNotificationReference` | PUT `/ai-notification-reference` `{items}` | 30s | |
| `createExpense` | POST `/users` `{localId, name, amount, category, type, date}` | 10s | On 200/201 → `markSynced`; errors swallowed |
| `updateUserByLocalId` | PUT `/users/{localId}` | 10s | 2xx → `markSynced`; 404 → false |
| `deleteUserByLocalId` | DELETE `/users/{localId}` | none | Fire-and-forget |
| `deleteAllExpenses` | POST `/users/delete-all` | 15s | |
| `syncPendingExpenses` | POST `/users/bulk` | 30s | Single-flight serialized; pushes in chunks of 500 with a shared `http.Client`, single token fetch, embedded `device` heartbeat on the final chunk, and 404 fallback to `POST /users` |
| `reportDeviceSync` | POST `/sync/beat` `{deviceId, deviceName, platform, appVersion, expenseCount}` | 10s | Throttled to a 30s cooldown after a successful heartbeat |
| `connectLiveWebSocket` etc. | WS `wsUrl?token=` | — | Sends `{type:'auth'}` and pings every 25s. **Not called anywhere.** |
| `getPublicConfig` | GET `/public-config` | 10s | **Not called anywhere.** |

### 2.6 Sync (offline-first)

**Local changes**

| Action | What happens |
|---|---|
| Insert | Row written locally (`synced` defaults to 0), then `createExpense` runs in the background |
| Edit | Row updated with `synced = 0`, then `updateUserByLocalId` (not awaited) |
| Delete | Local delete and server delete are both fire-and-forget. A failed server delete is **not retried**. |
| Approve a notification draft | Transaction moves the draft into `my_table`, then sync |

**Pushes to the server.** `syncPendingExpenses` runs:
- on every list load and on app resume;
- from Settings "Retry sync";
- from "Re-sync all", which marks every row unsynced, shows a loading overlay, and reloads the list without triggering a second sync pass.

Concurrent sync calls are serialized into at most one queued follow-up pass. Rows are pushed in chunks of 500 via `POST /api/users/bulk` (falling back to `POST /api/users` on 404) using a single HTTP client and token, and each confirmed chunk is marked `synced = 1` in one SQLite transaction (`markManySynced`). The server upserts on `(owner_id, local_id)`, so re-sending is safe.

**Pulls from the server.** Manual only, through "Load online expenses":
- `GET /users` → `importMissingExpenses`;
- inserts rows whose `localId` is missing locally, keeping the same id;
- sets `synced = 1`.

**Delete all.** The server bulk delete runs first. Local tables are wiped only if it succeeds.

**Delete account.** Deletes the user's expenses (server first, then local `my_table`) and pending drafts, then the Firebase account. The server's `ai_notification_references` / `device_syncs` rows and local `app_settings` are **not** deleted. There is no re-authentication; only password change re-authenticates.

**Live updates.** None in the app, because the WebSocket client is never connected.

### 2.7 Currency

- Supported currencies: **IDR, USD, EUR** only.
- Formatting:

  | Currency | Format |
  |---|---|
  | IDR | `Rp`, `id_ID`, 0 decimals |
  | USD | `$`, `en_US`, 2 decimals |
  | EUR | `€`, `de_DE`, 2 decimals |

- Storage is always IDR integers. Display value = `amount * appExchangeRate`.

**Changing currency**
1. IDR sets the rate to 1.
2. Otherwise the app fetches `/exchange-rates` and caches `rate_<CUR>`.
3. If the fetch fails it uses the cached rate.
4. With no cached rate it fails with "Exchange rate unavailable while offline" and keeps the old currency.

**At startup** the saved currency is restored only if a cached rate exists. There is no automatic refresh.

**Known gap:** the add, edit and receipt pages save the typed number as-is even when the display currency is USD/EUR.

### 2.8 Receipt scanning

1. `ImagePicker` (camera or gallery) with quality 65, max 1600 px.
2. The image is base64-encoded (png if the path ends `.png`, else jpeg) and sent to `POST /parse-receipt`.
3. The response is either plain JSON `{date, items, provider}` or an `application/x-ndjson` stream.
   - Progress lines drive the progress UI.
   - The `result` line carries the data.
   - An `error` line throws.
   - Cancelling closes the HTTP client and throws `ReceiptScanCancelledException`.
4. Provider label: `groq` → "Groq AI", `azure` → "Azure AI Document Intelligence".
5. Items become editable drafts:
   - category falls back to `makanan` if missing or invalid;
   - type defaults to `others`;
   - changing the quantity rescales the amount by unit price.
6. Checked items are inserted with `insertData`. When only part of the quantity is kept, the name gets ` (x/y porsi)`.

### 2.9 Notification parser

**Native side (Kotlin)**

`MainActivity.kt` registers these channels:

| Channel | Type | Methods / data |
|---|---|---|
| `expense_app/platform` | MethodChannel | `isAndroid` |
| `expense_app/notifications` | MethodChannel | `openSettings`, `isEnabled`, `setAllowedPackages{packages, allowAll}`, `setParserActive{active}`, `takePending` (returns the unacknowledged queue, removes nothing), `ack{keys}` (removes those entries), `start` |
| `expense_app/notification_events` | EventChannel | A "new notification" hint only; the payload is not used |

`NotificationListener.kt` handles incoming notifications:
- **Drops** them when the parser is inactive, the package is not allowed, or the notification is ongoing.
- **Text** is BIG_TEXT (else TEXT), plus SUB_TEXT and TEXT_LINES.
- **Dedup** uses the signature `package_title_text` within 60 s.
- **Payload** is `{key, title, text, packageName, postTime}`, with `key = package|postTime|hash(title+text)`.
- **Durable queue:** every payload is first appended to a SharedPreferences queue (newest 500), then a hint is sent to the event sink. Entries leave the queue only through `ack`, so a dead engine or a crash cannot lose a notification. Entries in the pre-v7 queue format (plain strings) are dropped.

**Dart pipeline** (`notification_expense_service.dart`)
`processPending()` runs on start, on every native hint and every 1 minute. It does two things in order:

1. **Drain** (`_drainNativeQueue`, single-flight): `takePending` → for each entry, skip noise and income (these are acked and dropped), run `LocalNotificationParser.parse`, and insert a row in `pending_notification_expenses`, then `ack` the keys. A row is never lost for parsing reasons:
   - local parser found an amount → `status = 'ready'` with its name/category/type;
   - no amount → `status = 'needs_input'`, `amount = 0`, name `Perlu dilengkapi`, category `lainnya`, type `unexpected`; the review page shows the raw text and the user types the amount.
   - both set `aiStatus = 'pending'` and keep `rawTitle` / `rawText`.
   - Duplicates are rejected by the unique `(ownerId, notificationKey)` index. With no signed-in user nothing is acked, so entries wait in the native queue until login. An entry whose insert throws is not acked and is retried on the next drain.
2. **Enrich** (`_enrichPendingWithAi`, single-flight): for rows with `aiStatus = 'pending'` and `aiNextRetryAt` due, `POST /parse-notification`. A result needs amount > 0 (a `Unknown expense` / empty name is treated as no name). `applyAiEnrichment` then updates name, category and type, and the amount only while the draft is `needs_input`; it never touches a draft the user already edited (`userEdited = 1`). If the AI finds no amount, `aiStatus` becomes `failed` and the local draft stays. On network/server errors the row backs off `2^(n-1)` minutes (cap 1 hour) and becomes `failed` after 6 attempts. A failed AI call never removes a draft.

`pending_cloud_notifications` (the old JSON retry queue) is migrated into drafts once by `_migrateLegacyQueue`; entries of other owners are kept.

**Local parser** (`local_notification_parser.dart`)
- **Tier 1:** per-app parsers chosen by package substring: gojek/gopay, dana, ovo, bca, mandiri/livin, bri, bni, jago, jenius/btpn, seabank, bsi, cimb/octo, shopee, grab, tokopedia.
- **Tier 2:** a universal financial parser.
- **Ignored:** OTP and security messages always; promotions unless they contain a payment keyword; income unless it is "transfer keluar" or "gagal".
- **Amount:** prefers `Rp`/`IDR` amounts and skips balance or limit context.
- **Merchant:** taken after di/ke/to/at/untuk.
- **Category:** regex dictionary.
- **Type:** always `unexpected`.

**Supported apps** (`supportedApps`; all enabled by default):

| Package | Label |
|---|---|
| `com.bca` | BCA Mobile |
| `com.mybca` | myBCA |
| `com.bca.mybca.omni.android` | myBCA (Play Store) |
| `id.bmri.livin` | Livin' by Mandiri |
| `id.co.bni.newmobile` | wondr by BNI |
| `src.com.bni` | BNI Mobile |
| `com.bri.bmo` | BRImo |
| `com.jago.app` | Bank Jago |
| `com.btpn.jenius` | Jenius BTPN |
| `com.beepr.bank` | SeaBank |
| `com.bsi.mobile` | BSI Mobile |
| `id.co.btn.mobile` | BTN Mobile |
| `com.cimbniaga.octomobile` | CIMB OCTO Mobile |
| `com.permatabank.mobile` | PermataME |
| `com.danamon.dbank` | Danamon D-Bank |
| `id.dana` | DANA |
| `ovo.id` | OVO |
| `com.gojek.app` | GoPay / Gojek |
| `com.gopay.wallet` | GoPay App |
| `com.shopee.id` | Shopee / SPay |
| `com.grabtaxi.passenger` | Grab |
| `com.tokopedia.tkpd` | Tokopedia |
| `id.flip` | Flip |
| `com.telkom.mwallet` | LinkAja |
| `com.finaccel.android` | Kredivo |
| `com.akulaku.android` | Akulaku |
| `com.android.shell` | Android Shell (debug) |

The key `__all_notifications__` allows every app.

**First-run onboarding.** If `notification_permission_onboarding_shown` is unset, the flag is written immediately. `NotificationPermissionPage` opens only if listener access is not already enabled, so it shows at most once per install.

### 2.10 AI notification reference ("AI memory")

**Refresh** (`updateAiNotificationReference`):
1. Merge local expenses with online expenses, de-duplicated by `local:<id>`.
2. Map each to `{expenseitem, expenseprice, category?, type?, date?}`.
3. Send the list with PUT `/ai-notification-reference`.

The server builds a per-category template, which is shown on `AiContextPage`. Amounts there are always shown in Rp with `jt`/`rb` suffixes.

### 2.11 PDF export and import

**Export** (`pdf_export_service.dart`)
- **Page 1: "EXPENSE REPORT".**
  - Header with account and timestamp.
  - Table: NAMA TRANSAKSI / KATEGORI / TIPE / TANGGAL / NOMINAL.
  - "TOTAL PENGELUARAN" box.
- **Page 2: "EXPENSE SUMMARY & ANALYTICS".**
  - KPIs: total, average, highest.
  - Category breakdown.
  - Type cards.
  - "Evaluasi Finansial" message.
- Amounts are shown in the display currency.
- **Backup payload:** the PDF keywords hold `expenseapp-backup-v1:<base64 JSON>` with `{version:1, currency, expenses:[{name, amount, date, category, type}]}`.
- **Saving:**
  - Android: MediaStore, Downloads/`ExpenseApp`, then opened with a VIEW intent.
  - Other platforms: `FileSaver` + `OpenFilex`.
  - File name `expense-report-<ms>.pdf`.

**Import** (`pdf_import_service.dart`, Syncfusion)
- **Backup path:** if the backup keywords are present, the rows are restored exactly.
- **Fallback path:** otherwise the printed table is rebuilt from word positions:
  - rows are clustered within 6 pt;
  - column edges come from the header words;
  - dates in Indonesian or English month names are accepted;
  - non-IDR amounts are divided back by the cached rate;
  - PDFs that are not from this app are rejected.
- **UI flow:** pick a PDF → parse → drop exact duplicates (name|amount|date|category|type) → confirm → insert with `synced = 0` → sync.

### 2.12 Error logging and easter eggs

**Error logging**
- `captureAppError(error, stack, context)` appends JSONL to `<ApplicationSupportDirectory>/developer_error_logs.jsonl` (serialised writes).
- `readLogs` returns newest first.
- Export writes `error-logs-<ts>.txt`.

**Easter eggs**

| Trigger | Result |
|---|---|
| Tap the Settings tab 3 times within 2 s | Opens `DeveloperLogsPage` |
| Home counter reaches exactly 10 | Full-screen `JOJO.jpeg` dialog |

The Home counter goes up when Home is tapped while already on Home, and also when the pager changes to Home. It resets on other tabs.

### 2.13 Design system (neo-brutalism)

- **Font:** `GoogleFonts.itim`.
- **Borders:** black, 1.2–3 px (1.5 and 2 are the most common).
- **Shadows:** hard, blur 0; offsets mostly `(2,2)`–`(4,4)`, up to `(6,6)`.
- **Corner radius:** 8–36.

**Colors**

| Role | Hex |
|---|---|
| Primary / seed | `#5DF9FF` |
| Expected | `#F9EB5D` |
| Unexpected / error | `#FF5D5D` |
| Others | `#5D9BFF` |
| Card | `#D9D9D9` |
| Hero light / dark | `#E8FDFF` / `#1E2830` |
| Settings pill | `#C77DFF` |
| Success | `#06D6A0` |

**Category colors**

| Category | Hex |
|---|---|
| makanan | `#FFD166` |
| school supply | `#C77DFF` |
| baju | `#FF99C8` |
| elektronik | `#70D6FF` |
| transportasi | `#06D6A0` |
| kesehatan | `#FF70A6` |
| hiburan | `#B5E48C` |

**Widgets** (`neo_animations.dart`):
- `NeoBouncy`
- `NeoButton`
- `FadeSlideAnimation`
- `SmoothPageRoute` (320 ms in, 260 ms out)

`NeoBrutalistCalendar` is a custom range/single-date picker built on material + intl; it does not use `table_calendar`.

`NeoSnackBar` (`neo_snackbar.dart`): standardized floating neo-brutalist snackbar with green `#06D6A0` (`success`) and red `#FF5D5D` (`error`) variants.

### 2.14 Categories and types

- **Picker categories:** `makanan`, `transportasi`, `hiburan`, `school supply`, `baju`, `elektronik`, `kesehatan`.
- **`lainnya`** comes only from parsers, pending review, and import.
- **Types:** `expected` (Terencana), `unexpected` (Tak Terduga), `others` (Lainnya).
- **Model defaults:** category `general`, type `others`.

---

## 3. Backend (`backend/`)

### 3.1 Runtime

**`server.js`**
- Creates the app with `createApp()` from `api/index.js`.
- Wraps it in `http.createServer` and listens on `PORT` (default 3000).
- Handles WebSocket upgrades on `/ws` and `/api/ws`; other upgrade paths are destroyed.
- Requiring `server.js` starts listening.

**`api/index.js`**
1. Loads env from `backend/.env.local`, then `.env`.
2. Initialises Firebase Admin from `FIREBASE_SERVICE_ACCOUNT_JSON`. If it is unset, it only warns, and authenticated routes return 503.
3. Middleware, in order:
   1. JSON / urlencoded parsers (8 MB limit);
   2. `cors()` with defaults, so all origins are allowed;
   3. a cookie parser;
   4. `express.static(public/)`.
4. Page routes, then API routes.
5. `/dodo` login router, then the `/dodo` admin router (in that order).

There is no `trust proxy` setting, so behind a reverse proxy `req.ip` is the proxy's address.

**Auth types**

| Name | How it works | Failure responses |
|---|---|---|
| **FB** | `Authorization: Bearer <Firebase ID token>`, verified by `api/middleware/auth.js` | 401 if missing/invalid; 503 if Firebase is not initialised |
| **SESS** | `dodo_session` cookie | `/api` paths: 401 `{error, redirect:"/dodo/login"}`; pages: redirect to `/dodo/login` |

### 3.2 Endpoints

#### Pages

| Path | Serves |
|---|---|
| `/` | `public/index.html` (portfolio) |
| `/expenses` | `public/projects/unmurce/app.html` (web expense app) |
| `/projects/unmurce` | `public/projects/unmurce/unmurce.html` |
| `/projects/docs` | `public/projects/unmurce/docs.html` |
| `/downloads`, `/downloads/:slug` | `public/downloads.html` |
| `/dodo/login` | `admin-ui/login.html` (redirects to `/dodo` if already logged in) |
| `/dodo` (SESS) | `admin-ui/panel.html` |
| `/dodo/static/*` | `admin-ui/static/*` (public CSS/JS, no data) |

#### Public API

| Method & path | Request → response |
|---|---|
| GET `/api/public-config` | → `{GROQ_MODEL, GROQ_NOTIFICATION_MODEL}` (the notification model falls back to `GROQ_MODEL` here only). Used as the Docker healthcheck. |
| GET `/api/portfolio` | → `{success, content}`; falls back to `content/portfolio.json` on a DB error |
| GET `/api/downloads` | → `{success, apps}` (active apps, each with `latest` and `releases`) |
| GET `/api/downloads/:slug` | → `{success, app}`, or 404 |
| GET `/api/rag-knowledge` | → `{success, knowledge}`; falls back to `public/asset/rag_knowledge.json` |
| POST `/api/rag-chat` | `{message}` (truncated to 500 chars; empty → 400) → `{reply, interested, provider, eventId}` |
| POST `/api/rag-feedback` | `{eventId, vote:"up"\|"down"}` → `{success, id, feedback}` |
| GET `/api/exchange-rates` | → `{base:"IDR", rates:{IDR:1, USD, EUR}}`; 502 on provider failure |

#### User API (FB)

| Method & path | Request → response |
|---|---|
| GET `/api/events` | SSE stream (§3.4). Firebase ID token in the Bearer header or `?token=`; 401 if missing/invalid, also 401 (not 503) when Firebase is not configured |
| POST `/api/users` | `{localId*, name, amount, category, type, date}` → the expense. Upserts on `(owner_id, local_id)`. Broadcasts `expense_created`. |
| POST `/api/users/bulk` | `{expenses* (≤ 1000), device?}` → `{count, syncedLocalIds}`. Single-statement `UNNEST` upsert on `(owner_id, local_id)`; optionally updates `device_syncs`. Broadcasts `bulk_upserted`. |
| GET `/api/users` | → array ordered by `date DESC, created_at DESC` |
| GET `/api/users/:localId` | → the expense, or 404 |
| PUT `/api/users/:localId` | partial fields → the updated expense, or 404. Broadcasts `expense_updated`. |
| DELETE `/api/users/:localId` | → `{message:"Deleted"}` (even if the row did not exist). Broadcasts `expense_deleted`. |
| POST `/api/users/delete-all` | → `{message, deletedCount}`. Broadcasts `bulk_deleted`. |
| POST `/api/sync/beat` | `{deviceId*, deviceName, platform, appVersion, expenseCount}` → `{success, lastSyncAt}` (upserts `device_syncs`) |
| GET `/api/ai-notification-reference` | → `{updated, itemCount, updatedAt, template}` |
| PUT `/api/ai-notification-reference` | `{items:[{expenseitem, expenseprice>0, category?, type?, date?}]}` (items beyond 100 are truncated; 400 if a kept item has an empty name or a non-positive/non-integer price) → `{updated, itemCount}` |
| POST `/api/ai-notification-reference/refresh` | → rebuilds from the latest 100 expenses |
| POST `/api/parse-notification` | `{message*, title?, packageName?}` → `{name, amount, category, type}` |
| POST `/api/parse-receipt` | `{image* (base64), mimeType?}` → NDJSON stream (§3.5) |

#### Admin login (public)

| Method & path | Behaviour |
|---|---|
| POST `/dodo/api/login-secret` | `{secret}`. Returns 429 if throttled, 503 if `ADMIN_SECRET` is unset, 401 if wrong. |
| POST `/dodo/api/login-firebase` | `{token}`: a raw Firebase ID token pasted by the user. Returns 429, 400, 503 (no Firebase or empty `ADMIN_FIREBASE_UIDS`), 403 (UID not allowed) or 401. |
| POST `/dodo/api/logout` | Clears the session. |
| GET `/dodo/api/check` | → `{authenticated, uid?}` |

#### Admin data (SESS)

| Method & path | Purpose |
|---|---|
| GET `/dodo/api/overview` | Totals, categories, last 14 days, last 12 months |
| GET `/dodo/api/owners` | Up to 500 owners by total |
| GET `/dodo/api/expenses` | Filters `owner, q, from, to, page, pageSize (≤500)` |
| GET `/dodo/api/expenses/export.csv` | Same filters, max 5000 rows |
| PUT `/dodo/api/expenses/:ownerId/:localId` | Edit an expense (broadcast + audit) |
| DELETE `/dodo/api/expenses/:ownerId/:localId` | Delete an expense (broadcast + audit) |
| GET `/dodo/api/firebase-users` | Firebase user directory (first 1000) |
| GET `/dodo/api/ai-usage` | `ai_provider_events`, last 7 days, plus recent events |
| GET `/dodo/api/audit?limit` | Audit log (1–200, default 100) |
| GET `/dodo/api/monthly` | 12-month trend (the panel uses `overview.monthly` instead) |
| GET `/dodo/api/devices?owner` | `device_syncs` |
| GET `/dodo/api/portfolio`, PUT `/dodo/api/portfolio` | Portfolio CMS content |
| GET `/dodo/api/downloads` | Download apps, including inactive ones, `r2_key`, and `r2Configured` flag |
| POST `/dodo/api/downloads/apps` | Create an app; slug `^[a-z0-9]+(-[a-z0-9]+)*$`, ≤ 40 chars |
| PUT `/dodo/api/downloads/apps/:slug`, DELETE `/dodo/api/downloads/apps/:slug` | Delete cascades to releases and deletes associated R2 release objects |
| POST `/dodo/api/downloads/apps/:slug/releases/presign` | `{version*, filename*, size_bytes*, releaseId?}` → short-lived presigned R2 `PUT` URL (503 if R2 unconfigured, 409 on duplicate version) |
| POST `/dodo/api/downloads/apps/:slug/releases` | `version*`, (`url*` or `r2_key*`), `released_at` YYYY-MM-DD, `size_bytes`, `notes` ≤ 300; R2 releases verify via `HeadObject` |
| PUT `/dodo/api/downloads/releases/:id`, DELETE `/dodo/api/downloads/releases/:id` | Replacing or deleting an R2-backed release automatically deletes the superseded R2 object |
| GET `/dodo/api/rag/stats` | |
| GET `/dodo/api/rag/events?limit&feedback&unanswered=1` | Unanswered = (not answered or down-voted) and not resolved |
| GET `/dodo/api/rag/knowledge`, PUT `/dodo/api/rag/knowledge` | |
| POST `/dodo/api/rag/events/:id/add-to-knowledge` | `{question, answer, keywords}`: adds an FAQ and resolves the event |
| POST `/dodo/api/rag/events/:id/resolve` | |
| GET `/dodo/api/assets` | List files under the asset root |
| POST `/dodo/api/assets/replace?file=` | Raw body; overwrites an existing file |
| POST `/dodo/api/assets/upload?file=` | Raw body; 409 if the file exists |
| DELETE `/dodo/api/assets?file=` | Delete (backup first) |
| GET `/dodo/api/assets/backups?file=` | |
| POST `/dodo/api/assets/restore` | `{file, backup}` |
| GET `/dodo/api/health` | DB latency, Firebase project, R2 bucket health, env flags, backups, commit, Node, uptime, memory |

### 3.3 PostgreSQL schema

`ensureSchema()` in `api/db.js` creates everything idempotently on the first connection. There are no migration files.

**`expenses`**
- Columns: `owner_id TEXT NN`, `local_id TEXT NN`, `name TEXT NN`, `amount INTEGER NN`, `category TEXT NN`, `type TEXT NN`, `date TEXT NN`, `created_at TIMESTAMPTZ`, `updated_at TIMESTAMPTZ` (both default now).
- `UNIQUE(owner_id, local_id)`; index on `owner_id`.
- No primary key. The legacy `id` column is dropped.
- `updated_at` is set explicitly in SQL; there is no trigger.

**`ai_notification_references`**
- Columns: `owner_id TEXT PK`, `items JSONB`, `summary JSONB` (added via `ADD COLUMN IF NOT EXISTS`), `updated_at`.

**`admin_audit_log`**
- Columns: `id BIGSERIAL PK`, `actor`, `action`, `target`, `detail JSONB`, `ip`, `created_at`.
- Index on `created_at DESC`.

**`ai_provider_events`**
- Columns: `id BIGSERIAL PK`, `owner_id`, `provider`, `status`, `duration_ms`, `error` (≤ 500 chars), `created_at`.
- Written only by the receipt flow.

**`portfolio_content`**
- Columns: `key TEXT PK` (`'main'`), `data JSONB`, `updated_at`.
- Seeded from `content/portfolio.json` on first read.

**`rag_knowledge`**
- Columns: `key TEXT PK` (`'main'`), `data JSONB`, `updated_at`.
- Seeded from `public/asset/rag_knowledge.json` on first read.

**`rag_chat_events`**
- Columns: `id`, `question`, `answer`, `provider`, `latency_ms`, `interested`, `answered`, `feedback`, `feedback_at`, `resolved_at`, `created_at`.

**`device_syncs`**
- Columns: `owner_id`, `device_id`, `device_name`, `platform`, `app_version`, `expense_count`, `last_sync_at`.
- `PK(owner_id, device_id)`.

**`download_apps`**
- Columns: `slug TEXT PK`, `name`, `tagline`, `description`, `icon_url`, `accent`, `sort_order`, `active`, timestamps.

**`download_releases`**
- Columns: `id BIGSERIAL PK`, `app_slug`, `version`, `url`, `size_bytes BIGINT`, `released_at DATE`, `notes`, `r2_key TEXT` (added via `ADD COLUMN IF NOT EXISTS`), timestamps.
- `app_slug` is an FK to `download_apps(slug)` ON DELETE CASCADE.
- `UNIQUE(app_slug, version)`.
- `r2_key` is returned only in `/dodo/api/downloads*`, never in public `/api/downloads*`.

**Other behaviour**
- **SSL:** used (with `rejectUnauthorized:false`) only when `DATABASE_URL` contains `sslmode=require`.
- **Pool resilience:** acquiring a connection times out after 5 s (`connectionTimeoutMillis`), so an unreachable Postgres fails the request instead of hanging it. Idle-client errors (e.g. Postgres restarting) are logged via `pool.on("error")` instead of crashing the process.
- **Download seeding:** if `download_apps` is empty, the app `unmurce` is created from the portfolio's `featured`. A release is created from `portfolio.apk` when present.
- **Latest release:** chosen by semver-like comparison, then `released_at`, then `id`.

### 3.4 Real-time

**WebSocket** (`/ws`, `/api/ws`)
- Authentication: `?token=` at upgrade time, or a later `{type:"auth", token}` message.
- An invalid token still upgrades, but the socket is unauthenticated and receives nothing.
- Server messages:

  | Message | When |
  |---|---|
  | `{type:"connected", transport:"websocket", ownerId}` | On connect, only with a valid token |
  | `{type:"authenticated", transport:"websocket", ownerId}` | After a successful `auth` message |
  | `{type:"pong"}` | In reply to `{type:"ping"}` |

- There is no server heartbeat.

**SSE** (`/api/events`)
- On connect it sends `{"type":"connected","transport":"sse","ownerId"}`.
- It sends a `: ping` comment every 20 s.
- It sets `X-Accel-Buffering: no`.

**Broadcast** (`api/lib/broadcast.js`)
- An in-memory owner → clients map, so it works for a single process only.
- Events:

  | Event | Payload |
  |---|---|
  | `expense_created` | `{item}` |
  | `expense_updated` | `{item}` |
  | `expense_deleted` | `{localId}` |
  | `bulk_deleted` | `{deletedCount}` |
  | `bulk_upserted` | `{count}` |

- Sources: user routes and admin edits/deletes.

**Clients**
- The web app (`public/script.js`) uses SSE. It would use WS only if `window.EXPENSE_WS_URL` were set, and nothing sets it.
- The Flutter app does not connect to either.

### 3.5 AI pipeline

**Groq client** (`api/services/groqService.js`)
- Endpoint: `https://api.groq.com/openai/v1/chat/completions` with JSON response format.
- Model: the one passed in, else `GROQ_MODEL`, else `llama-3.3-70b-versatile`.
- Fetch timeout 7500 ms (`AI_PROVIDER_TIMEOUT_MS`).
- Strips code fences from replies.

**Receipt parsing** (`POST /api/parse-receipt`, `api/routes/receipts.js`)

The overall deadline is 7500 ms. Up-front errors are plain JSON:

| Condition | Response |
|---|---|
| Neither Groq (key + `GROQ_MODEL`) nor Azure configured | 503 |
| No image | 400 |

Otherwise the response is `application/x-ndjson`, one JSON object per line:

```
{"type":"progress","stage":"groq"|"azure","status":"processing"|"failed"|"skipped","progress":0.36..0.86,"message":"..."}
{"type":"result","date":"YYYY-MM-DD"|null,"items":[{"name","quantity","amount","category","type"}],"provider":"groq"|"azure"}
{"type":"error","message":"Could not parse receipt: ..."}
```

1. **Groq vision** (`GROQ_MODEL`, temperature 0) is raced against `min(5000 ms, remaining time)`.
2. **Azure fallback** runs only if all of these hold:
   - Groq produced no result;
   - Azure is configured;
   - the Groq error has no status, or a status in `400, 404, 429, 500, 502, 503, 504`.

   A Groq 401/403 or a 422 ("no items") does **not** fall back; a timeout (504) does.
3. **Azure** uses `prebuilt-receipt:analyze?api-version=2024-11-30`:
   - the POST fetch has a 15 s timeout;
   - it then polls every 1 s, up to 20 times;
   - post-processing handles IDR parsing, a table fallback, total/tax reconciliation and ×1000 scaling heuristics.
4. **Normalisation:**
   - `amount = max(0, round)`; `quantity` defaults to 1;
   - unknown categories are guessed by keyword; unknown types become `others`;
   - zero items → an `error` line ("No items were detected on the receipt").

   Once streaming has started the HTTP status is always 200; provider failures and "no items" arrive only as `error` lines. Only the up-front 503/400 are real status codes.
5. Every Groq/Azure attempt writes an `ai_provider_events` row.

**Notification parsing** (`POST /api/parse-notification`)
- Requires `GROQ_API_KEY` **and** `GROQ_NOTIFICATION_MODEL`; otherwise 503. There is no fallback to `GROQ_MODEL`.
- The prompt includes the user's template from `ai_notification_references` and treats it as untrusted data.
- Temperature 0.
- Output: category one of `EXPENSE_CATEGORIES` (else `lainnya`); type `expected`/`unexpected` (else `unexpected`).
- Provider errors → 502.

**Notification template** (`api/services/notificationContext.js`)

```
{version:1, sampleSize, priceRange{min,max}|null,
 categories:[{category, count, priceRange, averagePrice, commonItems(top 5), types[]}]}
```

It is built from at most 100 items.

**RAG chat** (`POST /api/rag-chat`)
- Persona "Orlando". The whole knowledge JSON (DB, else the seed file) is embedded in the system prompt.
- Model: `GROQ_MODEL` or `llama-3.3-70b-versatile`.
- Without Groq, or when Groq fails, it answers locally, in this order:
  1. FAQ keyword match;
  2. greeting;
  3. canned Indonesian reply (`answered=false`).
- Every chat is logged in `rag_chat_events`.

**Exchange rates** (`GET /api/exchange-rates`)
- Fetches `https://open.er-api.com/v6/latest/IDR` on every request, with no cache and no timeout.
- Returns IDR, USD and EUR.

### 3.6 Admin panel (`/dodo`)

**Login**

| Method | How it works |
|---|---|
| Secret | SHA-256 + `timingSafeEqual` comparison against `ADMIN_SECRET` |
| Firebase | The user pastes a Firebase ID token whose UID is in `ADMIN_FIREBASE_UIDS` |

If the relevant variable is unset, that login method returns 503. It never allows open access.

**Sessions**
- In-memory, 24 h lifetime, pruned hourly; lost on restart.
- Cookie `dodo_session`: httpOnly, sameSite strict.
- The cookie is `secure` when `NODE_ENV=production`, so production admin login needs HTTPS.

**Throttling**
- Failed attempts are counted per `req.ip`: 10 per rolling 15 minutes.
- A successful login clears the count.

**Audit actions**
- `login_success`, `login_failed`, `logout`
- `asset_replaced`, `asset_uploaded`, `asset_deleted`, `asset_restored`
- `expense_updated`, `expense_deleted`
- `portfolio_updated`
- `download_app_created`, `download_app_updated`, `download_app_deleted`
- `download_release_created`, `download_release_updated`, `download_release_deleted`
- `rag_knowledge_updated`, `rag_faq_added`, `rag_event_resolved`

**Tabs**

| Tab | What it covers |
|---|---|
| Assets | Asset manager (below) |
| Content | Portfolio JSON |
| Downloads | Apps and releases |
| Overview | Totals and trends |
| Transactions | Browse, edit, delete, CSV export |
| Users | Owners, devices, Firebase users |
| AI | Provider usage |
| RAG | Stats, unanswered questions, knowledge editor, add-to-FAQ, resolve |
| Health | Server and configuration health |
| Audit | Audit log |

**Asset manager**
- Root: `ADMIN_ASSET_ROOT`, default `public/asset`.
- Allowed extensions for replace, upload and restore: `.png .jpg .jpeg .webp .gif .svg .ico .apk .json .md`. Delete has no extension check.
- Max size 40 MB.
- Paths must stay inside the root; hidden segments are rejected on upload.
- **Backups:**
  - Location: `ADMIN_BACKUP_ROOT` (default `data/admin-backups`)`/<relative path>/<ISO stamp>-<hex>`.
  - Made before every replace, delete and restore.
  - Up to 5 kept per file.
  - Exposed only through the per-asset dialog.
- Asset writes need a writable filesystem (the Docker container). See §5 for persistence.

**Downloads catalog**
- Releases can be uploaded directly from the browser to Cloudflare R2 via presigned S3 `PUT` URLs (`releases/<slug>/v<version>/<hex>-<filename>`), or linked manually via any public URL.
- Metadata lives in PostgreSQL (`download_apps`, `download_releases`) and files in R2, so `update-backend` never resets or depends on git/container disk for releases.
- Replacing or deleting an R2-backed release (or deleting its app) automatically deletes the orphaned object from R2 when no other release references it.
- The highest version becomes `latest` automatically.

### 3.7 Public website

**`/` (portfolio)**
- `portfolio-cms.js` fills `[data-cms*]` elements from `/api/portfolio`. It then overrides the APK info from `/api/downloads/<body data-download-app or "unmurce">`.
- `model-status.js` shows the models from `/api/public-config`.
- The chatbot uses `/api/rag-knowledge`, `/api/rag-chat` and `/api/rag-feedback`.
- GitHub repos are fetched from `api.github.com`.

**`/downloads[/:slug]`**
- Catalog built from `/api/downloads`.

**`/projects/unmurce`, `/projects/docs`**
- Static product pages.

**`/expenses`**
- Web version of the expense app: Firebase compat SDK 10.12.2, jsPDF.
- Uses `/api/users*`, `/api/parse-receipt` (NDJSON), `/api/exchange-rates` and SSE `/api/events`.
- Has a localStorage demo mode (`unmurce_demo_expenses`).
- `API_BASE_URL` is `window.EXPENSE_API_BASE_URL`, else `origin + /api`.

**Public files**
- Everything under `public/` is public. That includes:
  - `asset/rag_knowledge.json`;
  - `asset/README_RAG_DOCUMENT.md` (a guide to editing the chatbot knowledge);
  - a committed release APK in `asset/appdownload/`.

**Content shapes**
- **`content/portfolio.json`:** `profile{…}`, `featured{name, description, showcase_url, app_url, docs_url}`, `projects[]`, `experience[]`, `apk{version, size_bytes, url, released_at, notes}`.
- **`rag_knowledge.json`:** profile, personality, preferences, education, skills, projects, services, contact, interesting_topics, `faqs[{keywords[], question, answer}]`. Only `faqs` is read structurally; the rest goes to the LLM as-is.

---

## 4. Configuration

### 4.1 Backend environment variables

For local runs, put them in `backend/.env.local`, starting from `.env.example`. In production they are passed with `docker run --env-file`.

| Variable | Required | Default | Purpose | In `.env.example` |
|---|---|---|---|---|
| `DATABASE_URL` | yes | — (throws) | Postgres; add `sslmode=require` for SSL | yes |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | for auth | — (warning; auth routes 503) | Firebase Admin credentials, one-line JSON | yes |
| `ADMIN_SECRET` | for secret login | empty → disabled | Admin secret | yes |
| `ADMIN_FIREBASE_UIDS` | for Firebase login | empty → disabled | Comma-separated admin UIDs | yes |
| `GROQ_API_KEY` | for AI | empty | Groq auth | no |
| `GROQ_MODEL` | for receipts/RAG via Groq | empty (RAG falls back to `llama-3.3-70b-versatile`) | Vision/chat model | no |
| `GROQ_NOTIFICATION_MODEL` | for `/parse-notification` | — (503) | Notification model | no |
| `AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT` | for Azure fallback | empty | Azure endpoint (trailing slash stripped) | no |
| `AZURE_DOCUMENT_INTELLIGENCE_KEY` | for Azure fallback | — | Azure key | no |
| `R2_ENDPOINT` | for R2 release uploads | empty → disabled (503) | Cloudflare R2 S3 endpoint (`https://<account-id>.r2.cloudflarestorage.com`) | yes |
| `R2_BUCKET` | for R2 release uploads | empty → disabled | R2 bucket name | yes |
| `R2_ACCESS_KEY_ID` | for R2 release uploads | empty → disabled | R2 S3 API access key ID | yes |
| `R2_SECRET_ACCESS_KEY` | for R2 release uploads | empty → disabled | R2 S3 API secret access key | yes |
| `R2_PUBLIC_BASE_URL` | for R2 release uploads | empty → disabled | Public base URL serving the R2 bucket (`https://...`) | yes |
| `ADMIN_ASSET_ROOT` | no | `public/asset` | Asset manager root | no |
| `ADMIN_BACKUP_ROOT` | no | `data/admin-backups` | Asset backup root | no |
| `PORT` | no | 3000 | Listen port | no |
| `NODE_ENV` | no | — (Docker sets `production`) | Secure cookie flag | no |
| `GIT_COMMIT` / `SOURCE_COMMIT` / `VERCEL_GIT_COMMIT_SHA` / `VERCEL_GIT_COMMIT_REF` | no | falls back to `git` CLI | Commit shown in the Health tab | no |

Direct browser uploads to Cloudflare R2 require a bucket CORS policy allowing `PUT` from the admin origin (`https://dododabird.us` and/or `http://localhost:3000`) with `AllowedHeaders: ["content-type", "content-disposition"]`.

### 4.2 Flutter app

- **Backend URLs and version:** `--dart-define` (see §2.5).
- **Firebase setup:**
  1. Install the CLI: `dart pub global activate flutterfire_cli`.
  2. Run `flutterfire configure` against project `unmurce-2f3e3`. This regenerates `lib/firebase_options.dart` and `android/app/google-services.json`.
  3. Enable **Email/Password** sign-in in the Firebase console.
  4. Never commit service-account credentials; those go only into the backend's `FIREBASE_SERVICE_ACCOUNT_JSON`.
- **Release signing:** `android/key.properties`, which must not be committed.

---

## 5. Deployment & operations

### 5.1 Backend on the VPS (production)

**Image** (`backend/Dockerfile`)
- Base `node:24.22-alpine3.24`, workdir `/app`, `NODE_ENV=production`, `PORT=3000`.
- Runs `npm ci --omit=dev`, then as user `node`, exposing 3000.
- `HEALTHCHECK` fetches `/api/public-config` every 30 s.
- `.dockerignore` excludes `node_modules`, `.env*` (except the example), Firebase JSON, `.git`, `test/`.
- Therefore:
  - tests cannot run in the image;
  - env must come from `--env-file`;
  - the Health tab shows no commit unless `GIT_COMMIT` is passed.

**Conventions on the VPS**

| Item | Value |
|---|---|
| Repo | `~/Expense_App_Personal` |
| Branch | `VPS_Test` |
| Image | `expense-backend` (`:latest`, `:previous` for rollback) |
| Container | `expense-backend-app` |
| Docker network | `expense-net` |
| Env file | `backend/.env.local` |
| DB backups | `~/expense-backups` |
| Postgres | container `expense-postgres`, image `postgres:16-alpine`, volume `pgdata`, on `expense-net` |
| Reverse proxy | Caddy (systemd, on the host) → `127.0.0.1:3000`; config `/etc/caddy/Caddyfile` |
| OS | Ubuntu 24.04, logged in as `root` (so `~` is `/root`) |
| Checkout | sparse: only `backend/` (plus root files) |

These names come from the ops script below; they are not enforced by code.

**Helper functions** live in `backend/scripts/vps-ops.sh` (shell functions, sourced from `~/.bashrc`). Change them there and push; on the VPS a `git pull` (or `update-backend`) updates them for new shells.

One-time install on the VPS (needs the script pulled first):

```bash
cd ~/Expense_App_Personal && git pull origin VPS_Test
echo '[ -f ~/Expense_App_Personal/backend/scripts/vps-ops.sh ] && . ~/Expense_App_Personal/backend/scripts/vps-ops.sh' >> ~/.bashrc && . ~/.bashrc
```

If an older copy of the functions was pasted into `~/.bashrc` (between `# >>> expense-backend ops >>>` and `# <<< expense-backend ops <<<`), delete that block; the script replaces it.

**Commands**

| Command | What it does |
|---|---|
| `update-backend` | Pulls `VPS_Test`, keeps the old image as `:previous`, builds, recreates the container, waits for health, prunes |
| `recreate-backend` | Recreates the container without pull/build. **Required after editing `.env.local`.** |
| `restart-backend` | Quick restart; does **not** re-read env |
| `stop-backend` / `start-backend` | Stop / start the container |
| `logs-backend` / `logs-backend-errors` | Follow the logs / show error lines from the last 500 |
| `status-backend` | Container status, health, creation time, running commit, disk |
| `rollback-backend` | Runs the `:previous` image (one step back only) |
| `shell-backend` | `sh` inside the container |
| `env-backend` | Edit `.env.local` |
| `git-info-backend` | Branch, last 3 commits, local changes |
| `backup-db` | `pg_dump` to `~/expense-backups/unmurce-<date>.sql.gz`, keeping 14 days |
| `db-shell` | Interactive `psql` |
| `disk-check` | Host and Docker disk usage |
| `docker-cleanup` | Removes dangling images and build cache older than 7 days |
| `first-setup-backend` | One time: creates the network, builds, runs |
| `first-setup-db` | One time: creates `expense-postgres` with the `pgdata` volume, using user/password/db from `DATABASE_URL` (password must not be URL-encoded) |
| `restore-db <file.sql.gz>` | Restores a `backup-db` file. Refuses if the `expenses` table already exists, so run it before `first-setup-backend` |
| `help-backend` | Lists all ops commands with short descriptions |

**Without the helpers: update by hand**

```bash
cd ~/Expense_App_Personal && git pull origin VPS_Test && cd backend \
  && docker tag expense-backend:latest expense-backend:previous 2>/dev/null; \
  docker build -t expense-backend:latest . \
  && docker rm -f expense-backend-app 2>/dev/null; \
  docker run -d --name expense-backend-app --network expense-net \
     --restart unless-stopped --env-file .env.local -p 127.0.0.1:3000:3000 expense-backend:latest \
  && sleep 5 && docker logs --tail 30 expense-backend-app
```

**Without the helpers: health check by hand**

```bash
docker ps --filter name=expense-backend-app
curl -fsS http://127.0.0.1:3000/api/public-config && echo
```

**Operational notes**
- **Env changes:** `docker restart` does not re-read `--env-file`; use `recreate-backend`. Values must be on one line, and quotes in the env file are kept literally.
- **Asset persistence:** without volumes, assets uploaded via `/dodo` and their backups live inside the container and are lost on every recreate. To persist them, add to `docker run`:
  `-v ~/Expense_App_Personal/backend/public/asset:/app/public/asset -v ~/expense-backups/assets:/app/data/admin-backups`
- **Rollback safety:** do not use `docker system prune -a`; it deletes `:previous` and breaks rollback. Use `docker-cleanup`.
- **DB helpers:** `backup-db` / `db-shell` find the Postgres container by image name. If yours does not contain `postgres`, set `EXP_DB_CONTAINER`. `DATABASE_URL` must resolve from inside that container.
- **Testing:** run `npm test` locally before pushing to `VPS_Test`.
- **Local changes on the VPS:** if `git pull` fails, inspect with `git-info-backend` first; do not `reset --hard`.
- **State lost on restart:** admin sessions and WS/SSE registries are in memory and reset on every restart.
- **Port 3000 is published on `127.0.0.1` only.** Docker-published ports bypass `ufw`, so binding to all interfaces would expose the backend directly, around the proxy. Caddy must therefore proxy to `127.0.0.1:3000` (or `localhost:3000`), not the public IP.
- **Out of repo:** the Caddyfile itself is not in the repo; the template is in "New server setup" below.

**New server setup (moving providers)**

Order matters: the database is restored before the backend starts, because the backend creates empty tables on its first request and `restore-db` then refuses.

1. **Old server — freeze and back up.** `stop-backend` (no more writes), then `backup-db`. Copy the backup and the env file to your computer, from PowerShell:
   ```powershell
   scp root@OLD_IP:~/expense-backups/unmurce-YYYY-MM-DD-HHMM.sql.gz .
   scp root@OLD_IP:~/Expense_App_Personal/backend/.env.local .
   ```
   Keep the old server running (stopped backend) until step 9 is verified.
2. **New server — base packages and firewall** (Ubuntu):
   ```bash
   apt update && apt upgrade -y && apt install -y git curl
   curl -fsSL https://get.docker.com | sh
   ufw allow OpenSSH && ufw allow 80,443/tcp && ufw enable
   ```
   Install Caddy from its official apt repository: https://caddyserver.com/docs/install#debian-ubuntu-raspbian
3. **Sparse clone of the backend only** (a private repo needs a deploy key or token):
   ```bash
   cd ~ && git clone --filter=blob:none --sparse --branch VPS_Test https://github.com/DODODABIRD/Expense_App_Personal.git
   cd ~/Expense_App_Personal && git sparse-checkout set backend
   ```
4. **Env file and helpers.** From PowerShell: `scp .env.local root@NEW_IP:~/Expense_App_Personal/backend/.env.local`. Then on the server, load the helper functions now and on every login:
   ```bash
   echo '[ -f ~/Expense_App_Personal/backend/scripts/vps-ops.sh ] && . ~/Expense_App_Personal/backend/scripts/vps-ops.sh' >> ~/.bashrc && . ~/.bashrc
   type first-setup-db
   ```
   `type` must print a function; if it says "not found", the clone in step 3 is missing `backend/scripts/`.
5. **Database:** `first-setup-db`.
6. **Restore:** from PowerShell `scp unmurce-....sql.gz root@NEW_IP:~/`, then on the server `restore-db ~/unmurce-....sql.gz`. It prints the restored expense count; compare it with the old server.
7. **Backend:** `first-setup-backend`, then `status-backend` (health must be OK).
8. **Caddy.** `/etc/caddy/Caddyfile`:
   ```
   dododabird.us {
       reverse_proxy 127.0.0.1:3000
   }
   ```
   Add any other hostnames the old Caddyfile served, then `systemctl reload caddy`. WebSocket (`/ws`) needs no extra config.
9. **DNS.** Point the A record to the new IP. If the domain is proxied by Cloudflare, set the record to "DNS only" until Caddy has obtained its certificate (`journalctl -u caddy`), then turn the proxy back on with SSL mode "Full (strict)". Check the website, `/dodo`, and a sync from the app.
10. **Afterwards:** keep the old server a few days, then cancel it. Keep at least one recent `backup-db` file off the server (step 1's `scp`), not only in `~/expense-backups`.

**Vercel.** `vercel.json` is legacy and non-functional:
- `api/index.js` exports `{createApp}`, not a handler;
- there is no `/dodo` route;
- there is no WebSocket support;
- the filesystem is read-only.

### 5.2 Flutter app release

```bash
cd frontend/expenseapp
flutter build apk --release        # or --split-per-abi for per-ABI APKs
```

To publish a build:
1. Open `/dodo` → Downloads, select the app, and click **New release**.
2. Pick the built `.apk` file to upload directly to Cloudflare R2 (or paste a public download URL).
3. The highest version becomes the default download immediately (stored in PostgreSQL + R2, independent of git).

Bump `version:` in `pubspec.yaml` and the hard-coded "Version 2.0.0" in `settings_page.dart` together.

---

## 6. Testing

**Backend** (`cd backend`)
- `npm test` runs every file; `node --test test/<file>.test.js` runs one.
- No database is needed: tests inject a mock pool (`setPool`). `api_users.test.js` initialises a mock Firebase app and stubs `verifyIdToken`; the other suites assume Firebase is not configured.
- `admin`, `admin_features` and `downloads` tests load `backend/.env.local`. Real `FIREBASE_SERVICE_ACCOUNT_JSON`, `GROQ_API_KEY`, or `R2_*` values there make `admin` / `admin_features` use real services unless cleared by the test (`downloads` and `admin_features` explicitly clear `R2_*`). Run tests with an `.env.local` that has no real `FIREBASE_SERVICE_ACCOUNT_JSON` or `GROQ_API_KEY`.

| File | Covers |
|---|---|
| `admin.test.js` | Panel redirects, secret login, asset CRUD/backups/restore, overview, expenses, CSV, audit, logout, 503 without `ADMIN_SECRET` |
| `admin_features.test.js` | Portfolio CMS, RAG admin, health, devices, admin expense edit/delete |
| `api_users.test.js` | `/api/users` CRUD and `/api/users/bulk` with mocked `verifyIdToken`, 401/404, notification reference, delete-all |
| `db.test.js` | Row mapping, SSL detection, `ensureSchema` SQL, CRUD, bulk `UNNEST` upsert, JSONB reference |
| `downloads.test.js` | Version comparison, seeding, admin app/release CRUD, R2 presign/verify/cleanup lifecycle, latest selection, public endpoints |
| `notification_context.test.js` | Reference refresh (≤ 100 items), template building |
| `r2_service.test.js` | R2 config validation, key sanitization, presigned upload signing, `headObject`, `deleteObject`, `checkBucket` |

**Flutter** (`cd frontend/expenseapp`)
- `flutter test` runs everything; `flutter test test/<file>.dart` runs one.
- Tests disable Google Fonts runtime fetching and initialise `id_ID` date formatting.

| File | Covers |
|---|---|
| `ai_context_page_test.dart` | Category ranges, empty state, retry |
| `api_sync_test.dart` | Chunked bulk push, single token fetch, embedded device heartbeat on final chunk, 404 fallback, mid-sync failure handling |
| `developer_logs_page_test.dart` | Empty state, expandable stack trace |
| `error_log_service_test.dart` | Persist/read order, export |
| `expense_edit_page_test.dart` | Null expense id |
| `expense_summary_page_test.dart` | Outlier rules, type segments, empty state |
| `local_notification_parser_test.dart` | Noise, income, ambiguity, Tier-1 apps except BSI and CIMB, amount formats, universal fallback |
| `neo_brutalist_calendar_test.dart` | Narrow dialog layout |
| `neo_snackbar_test.dart` | Success/error styling and snackbar replacement |
| `notification_expense_service_test.dart` | Reference item building, BCA package variants |
| `pdf_import_service_test.dart` | Backup restore, table recovery, non-IDR conversion, rejection of foreign PDFs |

---

## 7. Known gaps and inconsistencies

Recorded so nobody mistakes them for intended behaviour. Fix only when asked.

**App**
- `ExpenseEdit` loads its row with `getDataById`, which has no `ownerId` filter.
- Server deletes are fire-and-forget and never retried.
- Delete account leaves the server's AI reference and device-sync rows and the local `app_settings` behind.
- Amounts typed while the display currency is USD/EUR are saved without converting to IDR.
- The WebSocket client and `getPublicConfig` are never called.
- Unused dependencies: `mongo_dart`, `objectid`, `flutter_svg`, `postgres`, `table_calendar`.
- The "Expense reminders" toggle does nothing.
- The permission page says processing is local, but the cloud parser runs first.
- Naming is inconsistent: Android label "UNMURCE" vs. MaterialApp title / About "Expense App".

**Backend**
- CRUD does not validate category or type and accepts negative amounts. The parsers do clamp to ≥ 0.
- `amount INTEGER` caps at about 2.1 billion IDR.
- There is no index on `expenses.date`.
- `GET /api/exchange-rates` has no cache or timeout.
- `groqParseReceipt` ignores its `timeoutMs` argument. The Azure timeout message says "8-second", but the deadline is 7500 ms.
- The Health tab checks `OPENROUTER_API_KEY` and `MONGODB_URI`, which nothing uses.
- `loadNotificationContext` is imported but unused.
- No `trust proxy` setting, so throttling and audit IPs are the proxy's address behind a reverse proxy.
- `.env.example` has an inappropriate placeholder for `ADMIN_SECRET` and omits the `GROQ_*` / `AZURE_*` variables.
- Public pages (`index.html`, `unmurce.html`, `docs.html`) and the RAG prompt still mention MongoDB, Gemini and Vercel. None of those are used.
- `public/script.js` comments refer to `node api/index.js`; the real entry point is `server.js`.
