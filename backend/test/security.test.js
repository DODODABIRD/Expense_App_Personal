const assert = require("node:assert/strict");
const { test, before, after } = require("node:test");
const http = require("node:http");
const admin = require("firebase-admin");

// Keep the RAG chat on its local fallback (no network) and pin the CORS
// allow-list; dotenv does not override variables that are already set.
process.env.GROQ_API_KEY = "";
process.env.CORS_ORIGINS = "https://allowed.example";

if (!admin.apps.length) {
  admin.initializeApp({ projectId: "test-project" });
}
const mockAuth = {
  verifyIdToken: async (token) => {
    if (token === "valid-token") return { uid: "test-owner-id" };
    throw new Error("Invalid token");
  },
};
try {
  admin.auth().verifyIdToken = mockAuth.verifyIdToken;
} catch (e) {}
admin.auth = () => mockAuth;

const { setPool } = require("../api/db");
const { createApp } = require("../api/index");

const upserts = [];
setPool({
  async query(sql, params) {
    const trimmed = sql.trim();
    if (trimmed.startsWith("INSERT INTO expenses") && trimmed.includes("UNNEST(")) {
      upserts.push(params[1]);
      return { rows: [] };
    }
    if (trimmed.startsWith("INSERT INTO expenses")) {
      const [ownerId, localId, name, amount, category, type, date] = params;
      return {
        rows: [{ owner_id: ownerId, local_id: localId, name, amount, category, type, date }],
      };
    }
    if (trimmed.startsWith("INSERT INTO rag_chat_events")) {
      return { rows: [{ id: 1 }] };
    }
    return { rows: [] };
  },
});

let server;
let baseUrl;

before(async () => {
  server = createApp().listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

const authJson = {
  Authorization: "Bearer valid-token",
  "Content-Type": "application/json",
};

function postExpense(body) {
  return fetch(`${baseUrl}/api/users`, {
    method: "POST",
    headers: authJson,
    body: JSON.stringify({ localId: "1", name: "Kopi", date: "2026-11-24", ...body }),
  });
}

test("expense amounts must be whole IDR within the INTEGER range", async () => {
  for (const amount of [-1, "abc", null, 2147483648, true]) {
    const res = await postExpense({ amount });
    assert.equal(res.status, 400, `amount ${JSON.stringify(amount)}`);
    assert.match((await res.json()).error, /amount/);
  }

  const ok = await postExpense({ amount: "15000" });
  assert.equal(ok.status, 200);
  assert.equal((await ok.json()).amount, 15000);

  const rounded = await postExpense({ amount: 1500.6 });
  assert.equal((await rounded.json()).amount, 1501);
});

test("expense names over 200 characters are rejected", async () => {
  const res = await postExpense({ amount: 1000, name: "x".repeat(201) });
  assert.equal(res.status, 400);
  assert.match((await res.json()).error, /name/);
});

test("bulk sync skips invalid rows instead of failing the batch", async () => {
  const res = await fetch(`${baseUrl}/api/users/bulk`, {
    method: "POST",
    headers: authJson,
    body: JSON.stringify({
      expenses: [
        { localId: "10", name: "Ok", amount: 5000, date: "2026-11-24" },
        { localId: "11", name: "Bad", amount: -5, date: "2026-11-24" },
      ],
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.deepEqual(body.syncedLocalIds, ["10"]);
  assert.equal(body.rejected.length, 1);
  assert.equal(body.rejected[0].localId, "11");
  assert.deepEqual(upserts.at(-1), ["10"]);
});

test("JSON bodies are capped at 1 MB outside receipt parsing", async () => {
  const res = await fetch(`${baseUrl}/api/rag-chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: "x".repeat(1.5 * 1024 * 1024) }),
  });
  assert.equal(res.status, 413);
  assert.ok((await res.json()).error);

  // The receipt route still accepts large bodies (it fails later on auth).
  const receipt = await fetch(`${baseUrl}/api/parse-receipt`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ image: "x".repeat(1.5 * 1024 * 1024) }),
  });
  assert.equal(receipt.status, 401);
});

test("malformed JSON gets a JSON error, not an HTML page", async () => {
  const res = await fetch(`${baseUrl}/api/users`, {
    method: "POST",
    headers: authJson,
    body: "{not json",
  });
  assert.equal(res.status, 400);
  assert.match(res.headers.get("content-type"), /application\/json/);
});

test("security headers are set and x-powered-by is hidden", async () => {
  const res = await fetch(`${baseUrl}/api/public-config`);
  assert.equal(res.headers.get("x-content-type-options"), "nosniff");
  assert.equal(res.headers.get("x-frame-options"), "SAMEORIGIN");
  assert.equal(res.headers.get("x-powered-by"), null);
});

test("CORS only answers allow-listed origins", async () => {
  const allowed = await fetch(`${baseUrl}/api/public-config`, {
    headers: { Origin: "https://allowed.example" },
  });
  assert.equal(
    allowed.headers.get("access-control-allow-origin"),
    "https://allowed.example"
  );

  const other = await fetch(`${baseUrl}/api/public-config`, {
    headers: { Origin: "https://evil.example" },
  });
  assert.equal(other.headers.get("access-control-allow-origin"), null);
});

test("RAG chat is rate limited per client IP behind the proxy", async () => {
  const chat = (ip) =>
    fetch(`${baseUrl}/api/rag-chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Forwarded-For": ip },
      body: JSON.stringify({ message: "halo" }),
    });

  for (let i = 0; i < 30; i += 1) {
    assert.equal((await chat("203.0.113.7")).status, 200);
  }
  const limited = await chat("203.0.113.7");
  assert.equal(limited.status, 429);
  assert.ok(limited.headers.get("retry-after"));

  // Another client behind the same proxy has its own bucket.
  assert.equal((await chat("198.51.100.9")).status, 200);
});

function openSse(path) {
  return new Promise((resolve, reject) => {
    const req = http.get(`${baseUrl}${path}`, (res) => {
      resolve(res.statusCode);
      res.destroy();
    });
    req.on("error", reject);
  });
}

test("SSE uses single-use tickets instead of tokens in the URL", async () => {
  assert.equal(await openSse("/api/events?token=valid-token"), 401);

  const unauthTicket = await fetch(`${baseUrl}/api/events/ticket`, { method: "POST" });
  assert.equal(unauthTicket.status, 401);

  const ticketRes = await fetch(`${baseUrl}/api/events/ticket`, {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
  });
  assert.equal(ticketRes.status, 200);
  const { ticket } = await ticketRes.json();
  assert.match(ticket, /^[0-9a-f]{64}$/);

  assert.equal(await openSse(`/api/events?ticket=${ticket}`), 200);
  assert.equal(await openSse(`/api/events?ticket=${ticket}`), 401);
});
