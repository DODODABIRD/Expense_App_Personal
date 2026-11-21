# AGENTS.md

Operating guide for coding agents working in this repository.

1. Read **`Rules.md`** first. It is binding and **read-only**: never edit it.
2. Use this file for how to work here.
3. Use **`Documentation.md`** for how the system works (endpoints, schemas, flows). Keep it in sync with your changes.

Claude Code loads `Rules.md` and this file through the root `CLAUDE.md`.

## Repository map

```
/
├── Rules.md            read-only rules
├── AGENTS.md           this file
├── Documentation.md    full technical reference
├── CLAUDE.md           imports Rules.md + AGENTS.md for Claude Code
├── backend/            Node.js API + admin panel + public website (one Express app)
└── frontend/
    └── expenseapp/     Flutter app "UNMURCE" (Android-first)
```

The two subprojects are independent: separate dependencies, tests, and deploys. They talk only over HTTP (`/api/*`).

## Stack

| | Backend (`backend/`) | App (`frontend/expenseapp/`) |
|---|---|---|
| Language | JavaScript, CommonJS | Dart, SDK `^3.11.0` |
| Framework | Express 5, `ws` 8 | Flutter (stable channel), Material 3 |
| Data | PostgreSQL via raw `pg` (no ORM) | SQLite via `sqflite` (`my_db.db`, version 6) |
| Auth | Firebase Admin (verifies ID tokens) | Firebase Auth, email/password |
| AI | Groq (primary), Azure Document Intelligence (receipt fallback) | calls backend only |
| Runtime | Node 24 in Docker (`node:24.22-alpine3.24`) on a VPS | Android app, id `com.example.expenseapp` |
| Tests | `node:test`, no DB needed (mock pool) | `flutter_test` |

`backend/vercel.json` is legacy and does not work as-is; production is Docker on a VPS.

## Commands

Backend (run in `backend/`):

```bash
npm install                           # install
npm start                             # node server.js, port $PORT or 3000
npm test                              # node --test, all files in test/
node --test test/admin.test.js        # single file
```

Local run needs `backend/.env.local` (copy `.env.example`; see Documentation.md → Configuration). Tests need no database. Keep `.env.local` free of real Firebase/Groq values when testing: `admin`, `admin_features` and `downloads` tests load it, so real `FIREBASE_SERVICE_ACCOUNT_JSON` / `GROQ_API_KEY` values make them use real Firebase or the network (`api_users` mocks Firebase itself).

App (run in `frontend/expenseapp/`):

```bash
flutter pub get                       # install
flutter run                           # debug on a device/emulator
flutter test                          # all tests
flutter test test/pdf_import_service_test.dart   # single file
flutter analyze                       # lint (flutter_lints)
flutter build apk --release           # release; signing from android/key.properties, else debug key
```

Point the app at another backend with `--dart-define=EXPENSE_API_BASE_URL=... --dart-define=EXPENSE_WS_URL=...` (defaults: `https://dododabird.us/api`, `wss://dododabird.us/ws`).

Deploy and VPS operations: see Documentation.md → Deployment & operations.

## Layout

Backend:

```
backend/
├── server.js              HTTP server + WebSocket upgrade (/ws, /api/ws); listens on PORT
├── api/
│   ├── index.js           createApp(): env, Firebase Admin init, middleware, all route mounting
│   ├── db.js              pg Pool, ensureSchema(), every SQL query
│   ├── config/            categories.js, providers.js (AI timeouts, Azure endpoint)
│   ├── lib/               broadcast.js (WS+SSE registry), fetchWithTimeout.js
│   ├── middleware/auth.js requireAuth / verifyToken (Firebase ID token)
│   ├── routes/            expenses, sync, notifications, parsing, receipts, exchange, events,
│   │                      adminLogin (login, /dodo/static), admin (session gate, panel page, assets, health),
│   │                      adminData (everything else under /dodo/api)
│   └── services/          groqService, azureService, notificationContext
├── admin-ui/              /dodo panel HTML + static/ (served by routes, not express.static)
├── public/                public website: portfolio, /downloads, /expenses web app, unmurce pages, asset/
├── content/portfolio.json seed for the portfolio CMS
├── scripts/vps-ops.sh     VPS ops shell functions (update-backend etc.), sourced from ~/.bashrc
├── test/                  *.test.js
├── Dockerfile, .dockerignore, .env.example, vercel.json (legacy)
```

App:

```
frontend/expenseapp/
├── lib/
│   ├── main.dart          boot, error handlers, global ValueNotifiers, theme
│   ├── pages/             auth_gate, auth_page, hp2 (home shell), ExpenseAddPage, ExpenseEdit,
│   │                      ExpenseSumarry, ReceiptScanPage, PendingNotificationReviewPage,
│   │                      notification_permission_page, settings_page, ai_context_page, developer_logs_page
│   ├── services/          ApiService (class Throw), auth_service, databaseHelper (class DatabaseHelp),
│   │                      notification_expense_service, local_notification_parser,
│   │                      pdf_export_service, pdf_import_service, error_log_service
│   ├── models/expense_model.dart
│   └── widgets/           neo_animations, neo_brutalist_calendar
├── android/app/src/main/kotlin/com/example/expenseapp/  MainActivity.kt, NotificationListener.kt
└── test/
```

File names are historical and inconsistent (`ExpenseSumarry.dart`, `hp2.dart`, class `Throw`). Do not rename them unless asked.

## Conventions

Backend:
- User routes export plain `(req, res)` handlers that `api/index.js` mounts one per path (e.g. `app.post("/api/users", requireAuth, expensesRoutes.createExpense)`); `/dodo` routes are Express routers mounted with `app.use("/dodo", …)`. Protect user routes with `requireAuth` and read the UID from `req.user`.
- All SQL lives in `api/db.js`. Add a table or column by editing `ensureSchema()` idempotently.
- After any expense mutation, call `broadcastLiveChange(ownerId, {type, ...})` from `api/lib/broadcast.js`.
- Admin mutations write an `admin_audit_log` row.
- Tests inject a mock pool with `setPool()`; follow that pattern instead of needing a real DB.

App:
- State is `StatefulWidget` + three global `ValueNotifier`s in `main.dart`: `appThemeMode`, `appCurrency`, `appExchangeRate`. No state library.
- Persisted settings go into the SQLite `app_settings` key/value table.
- Writes are local first, then sync to the server in the background.
- Log unexpected errors with `captureAppError(error, stack, 'context')`.
- UI is neo-brutalist: `GoogleFonts.itim`, black borders, hard shadows (blur 0), palette in Documentation.md.
- Categories in pickers: `makanan`, `transportasi`, `hiburan`, `school supply`, `baju`, `elektronik`, `kesehatan` (plus `lainnya` from parsers). Types: `expected`, `unexpected`, `others`.
- User-facing copy is mostly Indonesian; keep the language of the screen you are editing.

## Workflow

- Plan in one or two sentences before editing; for larger work list steps with a verification for each.
- Iterate with single-file test runs; run the full suite of the subproject you touched before finishing.
- For UI changes, run the app and check visually.
- Commits: subject under 72 characters, body explains why.
- Work may happen in git worktrees under `.claude/worktrees/`; stay inside the one you were given.

## Project Learnings

Agents append one concrete line here when the user corrects an approach. Tighten an existing line instead of adding a duplicate; remove lines that no longer apply.

- Re-read a file right before writing it: this repo carries concurrent uncommitted work (e.g. in-progress features in `backend/admin-ui`), so a full-file overwrite can destroy changes made since the last read.
