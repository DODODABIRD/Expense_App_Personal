# AGENTS.md

Drop-in operating instructions for coding agents. Read this file before every task.

**Working code only. Finish the job. Plausibility is not correctness.**

This file follows the [AGENTS.md](https://agents.md) open standard (Linux Foundation / Agentic AI Foundation).

---

## 0. Non-negotiables

1. **No flattery, no filler.** Skip openers like "Great question", "You're absolutely right".
2. **Disagree when you disagree.** If the user's premise is wrong, say so before doing the work.
3. **Never fabricate.** Not file paths, not commit hashes, not API names, not test results. If you don't know, read the file, run the command, or say "I don't know."
4. **Stop when confused.** If the task has two plausible interpretations, ask. Do not pick silently.
5. **Touch only what you must.** Every changed line traces directly to the user's request. No drive-by refactors.

---

## 1. Before writing code

- State your plan in one or two sentences before editing.
- Read the files you will touch. Read the files that call the files you will touch.
- Match existing patterns in the codebase. If the project uses pattern X, use pattern X.
- Surface assumptions out loud: "I'm assuming you want X, Y, Z. If that's wrong, say so."

---

## 2. Writing code: simplicity first

- No features beyond what was asked.
- No abstractions for single-use code.
- No error handling for impossible scenarios.
- If the solution runs 200 lines and could be 50, rewrite it.
- If you find yourself adding "for future extensibility", stop.

---

## 3. Surgical changes

- Do not "improve" adjacent code, comments, formatting, or imports not part of the task.
- Do not refactor code that works just because you are in the file.
- Match the project's existing style exactly: indentation, quotes, naming, file layout.

---

## 4. Goal-driven execution

- State success criteria before writing code.
- Write the verification (test, script, benchmark) where practical.
- Run the verification. Read the output. Do not claim success without checking.
- If the verification fails, fix the cause, not the test.

---

## 5. Tool use and verification

- Prefer running the code to guessing. If a test suite exists, run it.
- Never report "done" based on a plausible-looking diff alone. Plausibility is not correctness.
- When debugging, address root causes, not symptoms.

---

## 6. Session hygiene

- Context is the constraint. Long sessions with accumulated failed attempts perform worse than fresh sessions.
- Use subagents for exploration tasks that would pollute the main context.

---

## 7. Communication style

- Direct, not diplomatic. "This won't scale because X" beats "That's an interesting approach."
- Concise by default. Two or three short paragraphs unless the user asks for depth.
- When a question has a clear answer, give it. When it does not, say so.

---

## 8. When to ask, when to proceed

**Ask before proceeding when:**
- The request has two plausible interpretations and the choice materially affects output.
- The change touches load-bearing, versioned, or has a migration path.
- You need a credential, a secret, or a production resource.

**Proceed without asking when:**
- The task is trivial and reversible.
- The ambiguity can be resolved by reading the code or running a command.

---

## 9. Project Learnings

- (empty)

---

## 10. Project context

### Stack
- **Language:** Dart 3.11+
- **Framework:** Flutter (Material 3)
- **State Management:** ValueNotifier + StatefulWidget
- **Local Storage:** sqflite (SQLite)
- **Backend:** Node.js/VPS backend (MongoDB via postgres)
- **Auth:** Firebase Auth
- **Package Manager:** flutter pub

### Commands
- **Install dependencies:** `flutter pub get`
- **Build debug:** `flutter run`
- **Build release:** `flutter build apk --release` or `flutter build ios --release`
- **Run tests:** `flutter test`
- **Run single test:** `flutter test test/filename.dart`

### Layout
```
lib/
├── main.dart              # App entry, theme setup, global state
├── pages/                 # Screen/page widgets
│   ├── auth_gate.dart     # Authentication guard
│   ├── auth_page.dart     # Login/register UI
│   ├── ExpenseAddPage.dart      # Add expense form
│   ├── ExpenseEdit.dart         # Edit/delete expense
│   ├── ExpenseSumarry.dart      # Analytics dashboard
│   ├── PendingNotificationReviewPage.dart  # Review parsed notifications
│   ├── ReceiptScanPage.dart     # Receipt OCR scanner
│   ├── settings_page.dart       # App settings
│   ├── developer_logs_page.dart # Error logs viewer (hidden)
│   ├── hp2.dart                # Main home page with bottom nav
│   └── notification_permission_page.dart
├── services/
│   ├── ApiService.dart          # Backend API calls (Throw class)
│   ├── auth_service.dart        # Firebase auth wrapper
│   ├── databaseHelper.dart     # SQLite operations
│   ├── error_log_service.dart  # Local error logging
│   ├── local_notification_parser.dart  # Notification text parsing
│   ├── notification_expense_service.dart # Notification monitoring
│   └── pdf_export_service.dart # PDF generation
├── models/
│   └── expense_model.dart       # Expense data model
└── widgets/
    ├── neo_animations.dart    # Custom animations
    └── neo_brutalist_calendar.dart  # Custom date range picker

test/                       # Widget and unit tests
```

### Conventions

**Global State:**
- `appThemeMode` - ValueNotifier<ThemeMode> for dark/light theme
- `appCurrency` - ValueNotifier<String> for display currency (IDR, USD, EUR)
- `appExchangeRate` - ValueNotifier<double> for currency conversion rate

**Database:**
- Single SQLite database (`my_db.db`)
- Tables: `my_table` (expenses), `app_settings` (key-value), `pending_notification_expenses`
- Expenses have `ownerId` for multi-user isolation

**Backend API (ApiService.dart):**
- `Throw` class contains all API methods
- `baseUrl`: `https://vps.dododabird.us/api`
- `wsUrl`: `wss://vps.dododabird.us/ws` (WebSocket)
- JWT auth via Firebase ID token in `Authorization: Bearer <token>`

**Categories:** makanan, transportasi, hiburan, school supply, baju, elektronik, kesehatan, lainnya

**Expense Types:** expected, unexpected, others

**Notification Parsing:**
- Local regex-based parser for Indonesian banking/e-wallet notifications
- Cloud AI fallback for ambiguous notifications
- Supports: BCA, Mandiri, BRI, BNI, Jago, Jenius, SeaBank, BSI, CIMB, GoPay, DANA, OVO, Shopee, Grab, Tokopedia

### Forbidden
- Do not remove `captureAppError()` wrappers without good reason
- Do not bypass auth checks in API calls
- Do not change the database schema without migration logic

---

## 11. Special Features

**Easter Egg:**
- Tap home icon 10 times → JoJo reference jumpscare
- Triple-tap settings tab → Opens developer logs page

**Currency Conversion:**
- Expenses stored in IDR (default)
- Display can be converted to USD/EUR using cached exchange rates
- Rates fetched from backend and cached locally

**Notification Monitoring:**
- Reads Android notification stream via MethodChannel
- Auto-parses payment confirmations
- Queues pending reviews for user approval
