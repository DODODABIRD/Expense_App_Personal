const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { setPool } = require("../api/db");

const assetRoot = fs.mkdtempSync(path.join(os.tmpdir(), "unmurce-feature-assets-"));
const backupRoot = fs.mkdtempSync(path.join(os.tmpdir(), "unmurce-feature-backups-"));

process.env.ADMIN_SECRET = "feature-secret";
process.env.ADMIN_FIREBASE_UIDS = "";
process.env.ADMIN_ASSET_ROOT = assetRoot;
process.env.ADMIN_BACKUP_ROOT = backupRoot;
process.env.GROQ_API_KEY = "";
process.env.R2_ENDPOINT = "";
process.env.R2_BUCKET = "";
process.env.R2_ACCESS_KEY_ID = "";
process.env.R2_SECRET_ACCESS_KEY = "";
process.env.R2_PUBLIC_BASE_URL = "";

const portfolio = {
  profile: { name: "Orlando Test" },
  projects: [{ name: "Demo" }],
  experience: [{ title: "Demo" }],
  apk: { version: "9.9.9" },
};

const knowledge = {
  faqs: [{ keywords: ["unmurce"], question: "What is Unmurce?", answer: "My app." }],
};

const expenseRow = {
  owner_id: "owner-1",
  local_id: "loc-1",
  name: "Kopi",
  amount: 15000,
  category: "makanan",
  type: "expected",
  date: "2026-11-01",
  created_at: new Date("2026-11-01T10:00:00Z"),
  updated_at: new Date("2026-11-01T10:00:00Z"),
};

const ragRows = [
  {
    id: 7,
    question: "Can you build a Django app?",
    answer: "Maybe.",
    provider: "groq",
    latency_ms: 120,
    interested: true,
    answered: true,
    feedback: null,
    resolved_at: null,
    created_at: new Date("2026-11-01T10:00:00Z"),
  },
];

function mockPool() {
  return {
    async query(sql, params = []) {
      const trimmed = sql.trim();

      if (trimmed.startsWith("CREATE") || trimmed.startsWith("ALTER")) {
        return { rows: [] };
      }
      if (trimmed.startsWith("INSERT INTO admin_audit_log")) {
        return { rows: [] };
      }
      if (trimmed.startsWith("SELECT * FROM admin_audit_log")) {
        return { rows: [] };
      }
      if (trimmed.startsWith("SELECT data FROM portfolio_content")) {
        return { rows: [{ data: portfolio }] };
      }
      if (trimmed.startsWith("INSERT INTO portfolio_content")) {
        return { rows: [] };
      }
      if (trimmed.startsWith("SELECT data FROM rag_knowledge")) {
        return { rows: [{ data: knowledge }] };
      }
      if (trimmed.startsWith("INSERT INTO rag_knowledge")) {
        return { rows: [] };
      }
      if (trimmed.startsWith("INSERT INTO rag_chat_events")) {
        return { rows: [{ id: 42 }] };
      }
      if (trimmed.includes("COUNT(*) FILTER (WHERE created_at")) {
        return {
          rows: [
            {
              total: 10,
              total_7d: 4,
              up: 3,
              down: 1,
              unanswered: 2,
              avg_latency_ms: 210,
            },
          ],
        };
      }
      if (trimmed.startsWith("SELECT provider,")) {
        return {
          rows: [{ provider: "groq", count: 8, avg_latency_ms: 190 }],
        };
      }
      if (trimmed.startsWith("SELECT id, question")) {
        return { rows: ragRows };
      }
      if (trimmed.startsWith("UPDATE rag_chat_events")) {
        return { rows: [{ id: 42, feedback: "up" }] };
      }
      if (trimmed.startsWith("SELECT * FROM device_syncs")) {
        return {
          rows: [
            {
              owner_id: "owner-1",
              device_id: "device-1",
              device_name: "android 14",
              platform: "android",
              app_version: "1.7.5",
              expense_count: 12,
              last_sync_at: new Date("2026-11-16T09:00:00Z"),
            },
          ],
        };
      }
      if (trimmed.startsWith("INSERT INTO device_syncs")) {
        return { rows: [{ last_sync_at: new Date("2026-11-16T09:00:00Z") }] };
      }
      if (trimmed.startsWith("SELECT 1 AS ok")) {
        return { rows: [{ ok: 1 }] };
      }
      if (trimmed.includes("FROM expenses WHERE local_id = $1")) {
        return { rows: [expenseRow] };
      }
      if (trimmed.startsWith("UPDATE expenses")) {
        return { rows: [{ ...expenseRow, name: params[2] ?? expenseRow.name }] };
      }
      if (trimmed.startsWith("DELETE FROM expenses")) {
        return { rowCount: 1, rows: [] };
      }

      return { rows: [] };
    },
  };
}

test("Admin portfolio, RAG, health, device and expense support endpoints", async (t) => {
  setPool(mockPool());

  const { createApp } = require("../api/index");

  let server;
  let baseUrl;

  await new Promise((resolve) => {
    server = createApp().listen(0, () => {
      baseUrl = `http://127.0.0.1:${server.address().port}`;
      resolve();
    });
  });

  t.after(() => {
    server.close();
    fs.rmSync(assetRoot, { recursive: true, force: true });
    fs.rmSync(backupRoot, { recursive: true, force: true });
  });

  const login = await fetch(`${baseUrl}/dodo/api/login-secret`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ secret: "feature-secret" }),
  });
  assert.equal(login.status, 200);
  const rawCookies = login.headers.getSetCookie
    ? login.headers.getSetCookie()
    : [login.headers.get("set-cookie")];
  const cookie = rawCookies
    .filter(Boolean)
    .map((value) => value.split(";")[0])
    .find((value) => value.startsWith("dodo_session="));
  assert.ok(cookie);

  const admin = (url, options = {}) =>
    fetch(`${baseUrl}${url}`, {
      ...options,
      headers: { Cookie: cookie, ...(options.headers || {}) },
    });

  await t.test("public portfolio endpoint returns editable content", async () => {
    const res = await fetch(`${baseUrl}/api/portfolio`);
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.content.apk.version, "9.9.9");
  });

  await t.test("admin can read and save portfolio content", async () => {
    const getRes = await admin("/dodo/api/portfolio");
    assert.equal(getRes.status, 200);
    const loaded = await getRes.json();
    assert.equal(loaded.content.projects.length, 1);

    const putRes = await admin("/dodo/api/portfolio", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        content: { ...portfolio, apk: { version: "10.0.0" } },
      }),
    });
    assert.equal(putRes.status, 200);
    const saved = await putRes.json();
    assert.equal(saved.content.apk.version, "10.0.0");
  });

  await t.test("RAG chat logs an event and accepts feedback", async () => {
    const chatRes = await fetch(`${baseUrl}/api/rag-chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: "what is unmurce" }),
    });
    assert.equal(chatRes.status, 200);
    const chat = await chatRes.json();
    assert.equal(chat.eventId, 42);
    assert.equal(chat.provider, "local");

    const feedbackRes = await fetch(`${baseUrl}/api/rag-feedback`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ eventId: 42, vote: "up" }),
    });
    assert.equal(feedbackRes.status, 200);
    const feedback = await feedbackRes.json();
    assert.equal(feedback.feedback, "up");
  });

  await t.test("RAG monitoring exposes stats, events and knowledge", async () => {
    const stats = await (await admin("/dodo/api/rag/stats")).json();
    assert.equal(stats.totals.unanswered, 2);

    const events = await (await admin("/dodo/api/rag/events?limit=50")).json();
    assert.equal(events.events.length, 1);
    assert.equal(events.events[0].question, ragRows[0].question);

    const queue = await (
      await admin("/dodo/api/rag/events?unanswered=1")
    ).json();
    assert.equal(queue.events.length, 1);

    const knowledgeRes = await (await admin("/dodo/api/rag/knowledge")).json();
    assert.equal(knowledgeRes.knowledge.faqs.length, 1);
  });

  await t.test("unanswered question can become a FAQ and be resolved", async () => {
    const addRes = await admin("/dodo/api/rag/events/7/add-to-knowledge", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        question: "Do you build Django apps?",
        answer: "Yes, I do.",
        keywords: "django, backend",
      }),
    });
    assert.equal(addRes.status, 200);
    const added = await addRes.json();
    assert.equal(added.faqs, 2);

    const resolveRes = await admin("/dodo/api/rag/events/7/resolve", {
      method: "POST",
    });
    assert.equal(resolveRes.status, 200);
  });

  await t.test("health reports db, env, backups and commit", async () => {
    process.env.R2_ENDPOINT = "";
    process.env.R2_BUCKET = "";
    process.env.R2_ACCESS_KEY_ID = "";
    process.env.R2_SECRET_ACCESS_KEY = "";
    process.env.R2_PUBLIC_BASE_URL = "";

    const res = await admin("/dodo/api/health");
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.health.database.ok, true);
    assert.deepEqual(data.health.r2, {
      configured: false,
      ok: false,
      bucket: null,
      latencyMs: null,
      error: null,
    });
    assert.ok(Array.isArray(data.health.env));
    assert.ok(data.health.env.some((item) => item.key === "DATABASE_URL"));
    assert.ok(data.health.env.some((item) => item.key === "R2_ENDPOINT"));
    assert.ok(data.health.env.some((item) => item.key === "R2_BUCKET"));
    assert.ok(data.health.backups.count >= 0);
    assert.ok("commit" in data.health.runtime);
  });

  await t.test("devices list per owner", async () => {
    const res = await admin("/dodo/api/devices?owner=owner-1");
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.devices[0].deviceId, "device-1");
    assert.equal(data.devices[0].lastSyncAt !== null, true);
  });

  await t.test("support can edit and delete a single expense", async () => {
    const updateRes = await admin("/dodo/api/expenses/owner-1/loc-1", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "Kopi Susu" }),
    });
    assert.equal(updateRes.status, 200);
    const updated = await updateRes.json();
    assert.equal(updated.expense.name, "Kopi Susu");

    const deleteRes = await admin("/dodo/api/expenses/owner-1/loc-1", {
      method: "DELETE",
    });
    assert.equal(deleteRes.status, 200);
  });

  await t.test("mobile sync heartbeat requires Firebase auth", async () => {
    const res = await fetch(`${baseUrl}/api/sync/beat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ deviceId: "device-1" }),
    });
    // Firebase is not configured in this test process, so the auth middleware
    // rejects the call before it can write a device row.
    assert.ok(res.status === 401 || res.status === 503);
  });

  await t.test("rejects an invalid portfolio payload", async () => {
    const res = await admin("/dodo/api/portfolio", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: [] }),
    });
    assert.equal(res.status, 400);
  });
});
