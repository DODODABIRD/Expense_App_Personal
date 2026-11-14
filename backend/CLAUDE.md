# AGENTS.md

Drop-in operating instructions for coding agents. Read this file before every task.

**Working code only. Finish the job. Plausibility is not correctness.**

This file follows the [AGENTS.md](https://agents.md) open standard (Linux Foundation / Agentic AI Foundation).

---

## 0. Non-negotiables

1. **No flattery, no filler.** Skip openers like "Great question", "You're absolutely right".
2. **Disagree when you disagree.** If the user's premise is wrong, say so before doing the work.
3. **Never fabricate.** If you don't know, read the file, run the command, or say "I don't know, let me check."
4. **Stop when confused.** If the task has two plausible interpretations, ask.
5. **Touch only what you must.** No drive-by refactors or "while I was in there" cleanups.

---

## 1. Before writing code

- State your plan in one or two sentences before editing.
- Read the files you will touch. Read the files that call the files you will touch.
- Match existing patterns in the codebase.
- Surface assumptions out loud.

---

## 2. Writing code: simplicity first

- No features beyond what was asked.
- No abstractions for single-use code.
- No error handling for impossible scenarios.
- If the solution runs 200 lines and could be 50, rewrite it.

---

## 3. Surgical changes

- Do not "improve" adjacent code, comments, or formatting that are not part of the task.
- Do not refactor code that works just because you are in the file.
- Match the project's existing style exactly.

---

## 4. Goal-driven execution

- State the success criteria before writing code.
- Run verification where practical.
- If verification fails, fix the cause, not the test.

---

## 5. Communication style

- Direct, not diplomatic.
- Concise by default.
- When a question has a clear answer, give it. When it does not, say so.

---

## 6. Commands

```bash
# Install dependencies
npm install

# Run locally
npm start

# Test
npm test
```

---

## 7. Stack

- **Language:** Node.js (JavaScript)
- **Framework:** Express.js v5
- **Database:** PostgreSQL via `pg` driver
- **Auth:** Firebase Admin SDK
- **AI Providers:** Groq API (primary), Azure Document Intelligence (fallback for receipt OCR)
- **Real-time:** WebSocket (`ws`) + Server-Sent Events (SSE)
- **Deployment:** Vercel (serverless functions + static)

---

## 8. Layout

```
backend/
├── server.js                 # HTTP/WS server bootstrap
├── api/
│   ├── index.js             # Express app factory, route registration
│   ├── db.js                # PostgreSQL connection pool, schema init, CRUD
│   ├── config/
│   │   ├── categories.js    # EXPENSE_CATEGORIES, EXPENSE_TYPES, RECEIPT_CATEGORIES
│   │   └── providers.js    # AI provider config, timeouts, Azure endpoint helpers
│   ├── lib/
│   │   ├── broadcast.js     # WS + SSE client registry, broadcastLiveChange
│   │   └── fetchWithTimeout.js
│   ├── middleware/
│   │   └── auth.js          # Firebase ID token verification (requireAuth, verifyToken)
│   ├── routes/
│   │   ├── expenses.js      # CRUD for expenses table
│   │   ├── notifications.js # AI notification reference management
│   │   ├── parsing.js       # Groq-powered notification + RAG chat parsing
│   │   ├── receipts.js      # Streaming receipt OCR (Groq → Azure fallback)
│   │   ├── exchange.js      # IDR/USD/EUR exchange rates from open.er-api.com
│   │   ├── events.js        # SSE endpoint for real-time expense updates
│   │   ├── admin.js         # Admin panel (session-protected, manages .env.local)
│   │   └── adminLogin.js    # Admin login (public)
│   └── services/
│       ├── groqService.js   # Groq chat completion + receipt parsing
│       ├── azureService.js  # Azure Document Intelligence receipt OCR
│       └── notificationContext.js  # RAG context from recent expenses
├── public/                  # Static frontend assets
│   ├── index.html           # Portfolio/landing page
│   ├── script.js, style.css
│   └── projects/unmurce/    # Unmurce expense tracker SPA
├── test/                    # Node.js test files
└── vercel.json              # Vercel routing config
```

---

## 9. API Endpoints

### Expense CRUD (auth required)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/users` | Create/upsert expense |
| GET | `/api/users` | List all expenses |
| GET | `/api/users/:id` | Get expense by UUID |
| PUT | `/api/users/:id` | Update expense |
| DELETE | `/api/users/:id` | Delete expense |
| POST | `/api/users/delete-all` | Bulk delete all expenses |
| GET | `/api/users/local/:localId` | Get expense by localId |

### AI Parsing (auth required)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/parse-notification` | Parse SMS/notification → expense (Groq) |
| POST | `/api/parse-receipt` | Parse receipt image → items (streaming NDJSON) |
| POST | `/api/rag-chat` | Portfolio chatbot (public) |

### Notification Reference (auth required)
| Method | Path | Description |
|--------|------|-------------|
| PUT | `/api/ai-notification-reference` | Save expense reference items for RAG |
| POST | `/api/ai-notification-reference/refresh` | Refresh from recent expenses |

### Real-time
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/events` | SSE stream for live expense updates |
| WS | `/ws` | WebSocket (auth via query param or `auth` message) |

### Other
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/exchange-rates` | IDR/USD/EUR rates (public) |
| GET | `/api/public-config` | Expose GROQ_MODEL, GROQ_NOTIFICATION_MODEL (public) |

### Admin Panel (session-protected via /dodo)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/dodo/login` | Admin login page |
| POST | `/dodo/api/login-secret` | Login with ADMIN_SECRET |
| POST | `/dodo/api/login-firebase` | Login with Firebase ID token |
| POST | `/dodo/api/logout` | Logout |
| GET | `/dodo/api/check` | Check session status |
| GET | `/dodo` | Admin panel (manage .env.local) |
| GET | `/dodo/load` | Load current env vars |
| POST | `/dodo/save` | Save env vars to .env.local |

---

## 10. Database Schema

### `expenses` table
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | Primary key |
| owner_id | TEXT | Firebase UID, indexed |
| local_id | TEXT | Client-generated ID, UNIQUE with owner_id |
| name | TEXT | |
| amount | INTEGER | In smallest currency unit (IDR tanpa decimals) |
| category | TEXT | One of EXPENSE_CATEGORIES |
| type | TEXT | "expected" or "unexpected" |
| date | TEXT | ISO date string |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | Auto-updated |

### `ai_notification_references` table
| Column | Type | Notes |
|--------|------|-------|
| owner_id | TEXT | Primary key |
| items | JSONB | Array of {expenseitem, expenseprice, category?, type?, date?} |
| updated_at | TIMESTAMPTZ | |

---

## 11. Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| DATABASE_URL | Yes | PostgreSQL connection string |
| FIREBASE_SERVICE_ACCOUNT_JSON | Yes (prod) | Firebase Admin service account JSON |
| GROQ_API_KEY | Yes (AI) | Groq API key |
| GROQ_MODEL | No | Groq model for receipt parsing |
| GROQ_NOTIFICATION_MODEL | No | Groq model for notification parsing |
| AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT | No | Azure endpoint |
| AZURE_DOCUMENT_INTELLIGENCE_KEY | No | Azure key |
| ADMIN_SECRET | No | Admin panel secret key (if not set, panel is open in dev) |
| ADMIN_FIREBASE_UIDS | No | Comma-separated Firebase UIDs allowed for admin |
| PORT | No | Server port (default 3000) |

---

## 12. Key Patterns

### Auth middleware
```js
const { requireAuth } = require("./api/middleware/auth");
// Attaches req.user with Firebase UID
```

### Database schema initialization
Schema auto-creates on first connection via `ensureSchema()`. No migrations needed.

### Real-time broadcast
```js
const { broadcastLiveChange } = require("./api/lib/broadcast");
broadcastLiveChange(ownerId, { type: "expense_created", item });
// Pushes to all WS + SSE clients for that user
```

### Expense amount
All amounts are **integers in smallest unit** (IDR: no decimals, e.g., 50000 = Rp50.000).

### Receipt parsing (streaming)
`POST /api/parse-receipt` returns NDJSON stream:
```
{"type":"progress","stage":"groq","status":"processing","progress":0.4}
{"type":"result","date":"2025-01-15","items":[...],"provider":"groq"}
```

### Groq → Azure fallback for receipts
Groq is tried first. If it fails (400, 404, 429, 5xx), Azure Document Intelligence is used as fallback.

### Admin Panel
Access at `/dodo/login`. Session-based auth (24hr expiry). Two login methods:
- **Secret key**: Set `ADMIN_SECRET` env var
- **Firebase token**: Set `ADMIN_FIREBASE_UIDS` to restrict access to specific users

### Admin route mounting order
Login routes (`adminLogin`) MUST be mounted BEFORE admin panel routes (`adminRoutes`) to ensure `/dodo/login` is accessible.

---

## 13. Forbidden

- Do not change the expense amount convention (integer in IDR, no decimals).
- Do not modify `node_modules` or generated files.
- Do not add Firebase Auth initialization outside of `api/index.js`.
