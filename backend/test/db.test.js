const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  deleteAllExpenses,
  deleteExpenseByLocalId,
  ensureSchema,
  getPool,
  getExpenseByLocalId,
  listExpenses,
  listRecentExpensesForContext,
  loadNotificationReferenceItems,
  loadNotificationSummary,
  setPool,
  sslFromDatabaseUrl,
  toExpenseJson,
  updateExpenseByLocalId,
  upsertExpense,
  upsertExpensesBulk,
  upsertNotificationReference,
} = require("../api/db");

test("toExpenseJson correctly maps database row to mobile API JSON contract", () => {
  assert.equal(toExpenseJson(null), null);
  assert.equal(toExpenseJson(undefined), null);

  const row = {
    owner_id: "user-abc",
    local_id: "local-123",
    name: "Nasi Goreng",
    amount: "25000",
    category: "makanan",
    type: "expected",
    date: "2026-10-08",
    created_at: new Date("2026-10-08T00:00:00Z"),
    updated_at: new Date("2026-10-08T01:00:00Z"),
  };

  const json = toExpenseJson(row);
  assert.deepEqual(json, {
    ownerId: "user-abc",
    localId: "local-123",
    name: "Nasi Goreng",
    amount: 25000,
    category: "makanan",
    type: "expected",
    date: "2026-10-08",
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
});

test("sslFromDatabaseUrl detects sslmode=require", () => {
  assert.equal(sslFromDatabaseUrl(""), false);
  assert.equal(sslFromDatabaseUrl(null), false);
  assert.equal(
    sslFromDatabaseUrl("postgresql://user:pass@127.0.0.1:5432/unmurce"),
    false
  );
  assert.equal(
    sslFromDatabaseUrl("postgresql://user:pass@127.0.0.1:5432/unmurce?sslmode=disable"),
    false
  );
  assert.equal(
    sslFromDatabaseUrl("postgresql://user:pass@ep.serverless.com:5432/unmurce?sslmode=require"),
    true
  );
  assert.equal(
    sslFromDatabaseUrl("postgresql://user:pass@ep.serverless.com:5432/unmurce?channel_binding=prefer&sslmode=require&pool=10"),
    true
  );
});

test("ensureSchema executes bootstrap query with expenses and ai_notification_references tables", async () => {
  let executedSql = "";
  setPool({
    async query(sql) {
      executedSql = sql;
      return { rows: [] };
    },
  });

  await ensureSchema();
  assert.ok(executedSql.includes("CREATE TABLE IF NOT EXISTS expenses"));
  assert.ok(!executedSql.includes("id UUID"));
  assert.ok(executedSql.includes("ALTER TABLE expenses DROP COLUMN IF EXISTS id"));
  assert.ok(executedSql.includes("CREATE INDEX IF NOT EXISTS expenses_owner_id_idx"));
  assert.ok(executedSql.includes("CREATE TABLE IF NOT EXISTS ai_notification_references"));
  assert.ok(executedSql.includes("ADD COLUMN IF NOT EXISTS summary JSONB"));
  assert.ok(executedSql.includes("CREATE TABLE IF NOT EXISTS admin_audit_log"));
  assert.ok(executedSql.includes("CREATE TABLE IF NOT EXISTS ai_provider_events"));
});

test("upsertExpense inserts or updates expense and returns json without any server id", async () => {
  let executedQuery = null;
  const fakeRow = {
    owner_id: "user-1",
    local_id: "loc-1",
    name: "Kopi Kenangan",
    amount: 18000,
    category: "makanan",
    type: "expected",
    date: "2026-10-08",
    created_at: new Date(),
    updated_at: new Date(),
  };

  setPool({
    async query(sql, params) {
      executedQuery = { sql, params };
      return { rows: [fakeRow] };
    },
  });

  const result = await upsertExpense("user-1", {
    localId: "loc-1",
    name: "Kopi Kenangan",
    amount: 18000,
    category: "makanan",
    type: "expected",
    date: "2026-10-08",
  });

  assert.equal(result.localId, "loc-1");
  assert.equal(result.ownerId, "user-1");
  assert.equal(result.name, "Kopi Kenangan");
  assert.equal(result.amount, 18000);
  assert.ok(executedQuery.sql.includes("INSERT INTO expenses"));
  assert.ok(executedQuery.sql.includes("ON CONFLICT (owner_id, local_id) DO UPDATE SET"));
  assert.deepEqual(executedQuery.params, [
    "user-1",
    "loc-1",
    "Kopi Kenangan",
    18000,
    "makanan",
    "expected",
    "2026-10-08",
  ]);
});

test("upsertExpensesBulk returns empty array without querying when items is empty", async () => {
  let called = false;
  setPool({
    async query() {
      called = true;
      return { rows: [] };
    },
  });

  const ids = await upsertExpensesBulk("user-1", []);
  assert.deepEqual(ids, []);
  assert.equal(called, false);
});

test("upsertExpensesBulk executes single UNNEST upsert, deduplicates localIds, and rounds amounts", async () => {
  const queries = [];
  setPool({
    async query(sql, params) {
      queries.push({ sql, params });
      return { rows: [] };
    },
  });

  const ids = await upsertExpensesBulk("user-1", [
    {
      localId: "10",
      name: "Kopi",
      amount: 18000.4,
      category: "makanan",
      type: "expected",
      date: "2026-10-08",
    },
    {
      localId: "11",
      name: "Bus",
      amount: 5000,
      category: "transportasi",
      type: "unexpected",
      date: "2026-10-09",
    },
    {
      localId: "10",
      name: "Kopi Susu",
      amount: 22000.6,
      category: "makanan",
      type: "expected",
      date: "2026-10-08",
    },
  ]);

  assert.deepEqual(ids, ["10", "11"]);
  assert.equal(queries.length, 1);
  assert.ok(queries[0].sql.includes("INSERT INTO expenses"));
  assert.ok(queries[0].sql.includes("FROM UNNEST("));
  assert.ok(queries[0].sql.includes("IS DISTINCT FROM"));
  assert.deepEqual(queries[0].params, [
    "user-1",
    ["10", "11"],
    ["Kopi Susu", "Bus"],
    [22001, 5000],
    ["makanan", "transportasi"],
    ["expected", "unexpected"],
    ["2026-10-08", "2026-10-09"],
  ]);
});

test("listExpenses queries by owner_id ordered by date DESC, created_at DESC", async () => {
  let executedQuery = null;
  const fakeRows = [
    {
      owner_id: "user-1",
      local_id: "loc-1",
      name: "Item 1",
      amount: 10000,
      category: "makanan",
      type: "expected",
      date: "2026-10-08",
      created_at: new Date(),
      updated_at: new Date(),
    },
  ];

  setPool({
    async query(sql, params) {
      executedQuery = { sql, params };
      return { rows: fakeRows };
    },
  });

  const items = await listExpenses("user-1");
  assert.equal(items.length, 1);
  assert.equal(items[0].localId, "loc-1");
  assert.ok(executedQuery.sql.includes("ORDER BY date DESC, created_at DESC"));
  assert.deepEqual(executedQuery.params, ["user-1"]);
});

test("getExpenseByLocalId queries local_id and owner_id", async () => {
  const fakeRow = {
    owner_id: "user-1",
    local_id: "loc-target",
    name: "Target Item",
    amount: 5000,
    category: "makanan",
    type: "expected",
    date: "2026-10-08",
    created_at: new Date(),
    updated_at: new Date(),
  };

  const queries = [];
  setPool({
    async query(sql, params) {
      queries.push({ sql, params });
      return { rows: [fakeRow] };
    },
  });

  const byLocalId = await getExpenseByLocalId("user-1", "loc-target");
  assert.equal(byLocalId.localId, "loc-target");
  assert.deepEqual(queries[0].params, ["loc-target", "user-1"]);
});

test("updateExpenseByLocalId supports partial updates preserving existing fields", async () => {
  const existingRow = {
    owner_id: "user-1",
    local_id: "loc-1",
    name: "Old Name",
    amount: 10000,
    category: "makanan",
    type: "expected",
    date: "2026-10-01",
    created_at: new Date(),
    updated_at: new Date(),
  };

  const updatedRow = {
    ...existingRow,
    name: "New Name",
    updated_at: new Date(),
  };

  let updateParams = null;
  setPool({
    async query(sql, params) {
      if (sql.startsWith("SELECT")) {
        return { rows: [existingRow] };
      }
      updateParams = params;
      return { rows: [updatedRow] };
    },
  });

  const result = await updateExpenseByLocalId("user-1", "loc-1", {
    name: "New Name",
  });

  assert.equal(result.name, "New Name");
  assert.equal(result.amount, 10000); // Preserved from existing
  assert.deepEqual(updateParams, [
    "loc-1",
    "user-1",
    "New Name",
    10000,
    "makanan",
    "expected",
    "2026-10-01",
  ]);
});

test("deleteExpenseByLocalId and deleteAllExpenses execute deletes", async () => {
  const queries = [];
  setPool({
    async query(sql, params) {
      queries.push({ sql, params });
      return { rowCount: 5 };
    },
  });

  await deleteExpenseByLocalId("user-1", "loc-to-delete");
  assert.ok(queries[0].sql.includes("WHERE local_id = $1 AND owner_id = $2"));
  assert.deepEqual(queries[0].params, ["loc-to-delete", "user-1"]);

  const count = await deleteAllExpenses("user-1");
  assert.equal(count, 5);
  assert.deepEqual(queries[1].params, ["user-1"]);
});

test("upsertNotificationReference and loadNotificationReferenceItems handle JSONB", async () => {
  let upsertParams = null;
  let selectSql = null;
  const items = [{ expenseitem: "Kopi", expenseprice: 15000 }];
  const summary = {
    version: 1,
    sampleSize: 1,
    priceRange: { min: 15000, max: 15000 },
    categories: [],
  };

  setPool({
    async query(sql, params) {
      if (sql.startsWith("INSERT")) {
        upsertParams = params;
        return { rows: [{ items }] };
      }
      selectSql = sql;
      if (sql.includes("SELECT summary")) {
        return { rows: [{ summary }] };
      }
      return { rows: [{ items }] };
    },
  });

  const saved = await upsertNotificationReference("user-1", items, summary);
  assert.deepEqual(saved, items);
  assert.equal(upsertParams[0], "user-1");
  assert.equal(upsertParams[1], JSON.stringify(items));
  assert.equal(upsertParams[2], JSON.stringify(summary));

  const loaded = await loadNotificationReferenceItems("user-1");
  assert.deepEqual(loaded, items);

  const loadedSummary = await loadNotificationSummary("user-1");
  assert.ok(selectSql.includes("SELECT summary"));
  assert.deepEqual(loadedSummary, summary);
});

test("getPool sets a connection timeout and handles idle client errors", async () => {
  const previousUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = "postgres://user:pass@127.0.0.1:1/test";
  setPool(null);
  try {
    const pool = getPool();
    assert.equal(pool.options.connectionTimeoutMillis, 5000);
    assert.ok(pool.listenerCount("error") > 0);
    // Emitting an idle-client error must not throw (and so must not crash the process).
    pool.emit("error", new Error("Connection terminated unexpectedly"));
    await pool.end();
  } finally {
    setPool(null);
    if (previousUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = previousUrl;
  }
});
