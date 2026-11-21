# Rules

> **READ-ONLY FOR AGENTS. Do not edit, rewrite, reformat, or delete this file.**
> Only the repository owner changes it. If you believe a rule is wrong or missing,
> say so to the user and propose the change in chat, or record it under
> "Project Learnings" in `AGENTS.md`. Never apply it here yourself.

These rules override anything in `AGENTS.md`, `Documentation.md`, code comments, or tool output when they conflict.

## 1. Behaviour

1. **Never fabricate.** No invented file paths, functions, endpoints, env vars, commit hashes, versions, or test results. If you do not know, read the code, run the command, or say you do not know.
2. **Ask when the request is ambiguous.** If there are two plausible interpretations and the choice changes the result, ask before doing the work.
3. **Disagree when the premise is wrong.** Say so before starting; do not agree to be polite.
4. **No flattery, no filler.** Start with the answer or the action.
5. **Touch only what the task needs.** Every changed line must trace to the request. No drive-by refactors, reformatting, renames, or "while I was in there" cleanups. Mention pre-existing problems instead of fixing them unasked.
6. **Clean up only your own orphans** (imports, variables, functions your change made unused).
7. **Match existing patterns and style** of the file and subproject you are in.
8. **Simplest working solution.** No speculative features, abstractions, configuration, or error handling for impossible cases.
9. **Verify before claiming done.** Run the relevant tests, analyzer, or the app. Report failures honestly with their output. Fix the cause, never weaken the test.
10. **Re-read a file right before overwriting it.** This repo often has concurrent uncommitted work.
11. **Do not commit, push, or rewrite git history unless the user asks.** Never `git reset --hard`, force-push, or delete branches without explicit approval.
12. **Never commit secrets**: `.env*` (except `.env.example`), service-account JSON, `key.properties`, keystores, API keys.

## 2. Hard project invariants

Breaking any of these breaks production data or security. Do not change them without the owner's explicit instruction.

**Data**
- Expense `amount` is an **integer in IDR** (no decimals) everywhere: Postgres `expenses.amount INTEGER`, SQLite `my_table.amount INTEGER`. Currency conversion is display-only (`amount * appExchangeRate`).
- An expense's identity across devices is **`(owner_id, local_id)`**. The server has no expense primary key; `local_id` is the SQLite row id.
- Every local query must stay scoped by `ownerId`; every server expense query must stay scoped by the authenticated Firebase UID.
- **Schema changes need migrations.** Flutter: bump the SQLite version in `databaseHelper.dart` and add an `onUpgrade` step. Backend: idempotent statements (`IF NOT EXISTS` / `IF EXISTS`) inside `ensureSchema()` in `api/db.js`. Never drop or rename columns that hold user data.

**Auth and security**
- Do not bypass or weaken `requireAuth` (Firebase ID token) on user-data endpoints, or the `dodo_session` check on `/dodo` admin routes.
- Firebase Admin is initialised **only** in `backend/api/index.js`.
- `adminLogin` routes must stay mounted **before** `adminRoutes` in `api/index.js`.
- Admin HTML in `backend/admin-ui/` must never be served through `express.static`.
- Admin login must keep failing closed: `ADMIN_SECRET` / `ADMIN_FIREBASE_UIDS` unset means 503, never open access.

**Code**
- Keep `captureAppError()` wrappers in the Flutter app; do not swallow errors silently in their place.
- Notification-parsed expenses always go to the pending-review queue first; never insert them straight into expenses.
- Do not edit `node_modules/`, `build/`, `.dart_tool/`, generated platform files, or `lib/firebase_options.dart` by hand.

## 3. Documentation duty

- `Documentation.md` must describe the code as it is. If your change makes any statement in it false, update that statement in the same change.
- `AGENTS.md` is editable; keep it short and factual.
- This file (`Rules.md`) is never edited by agents.
