const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  deleteAllExpenses,
  deleteExpenseById,
  ensureSchema,
  getExpenseById,
  getExpenseByLocalId,
  isInvalidUuidError,
  listExpenses,
  listRecentExpensesForContext,
  loadNotificationReferenceItems,
  setPool,
  sslFromDatabaseUrl,
  toExpenseJson,
  updateExpenseById,
  upsertExpense,
  upsertNotificationReference,
} = require("../api/db");

test("toExpenseJson correctly maps database row to mobile API JSON contract", () => {
  assert.equal(toExpenseJson(null), null);
  assert.equal(toExpenseJson(undefined), null);

  const row = {
    id: "f47ac10b-58cc-4372-a567-0e02b2c3d479",
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
    _id: "f47ac10b-58cc-4372-a567-0e02b2c3d479",
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

test("isInvalidUuidError detects Postgres 22P02 error code", () => {
  assert.equal(isInvalidUuidError({ code: "22P02" }), true);
  assert.equal(isInvalidUuidError({ code: "42P01" }), false);
  assert.equal(isInvalidUuidError(null), false);
  assert.equal(isInvalidUuidError(new Error("Generic error")), false);
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
  assert.ok(executedSql.includes("CREATE INDEX IF NOT EXISTS expenses_owner_id_idx"));
  assert.ok(executedSql.includes("CREATE TABLE IF NOT EXISTS ai_notification_references"));
});

test("upsertExpense inserts or updates expense and returns json with _id", async () => {
  let executedQuery = null;
  const fakeRow = {
    id: "f47ac10b-58cc-4372-a567-0e02b2c3d479",
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

  assert.equal(result._id, fakeRow.id);
  assert.equal(result.ownerId, "user-1");
  assert.equal(result.localId, "loc-1");
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

test("listExpenses queries by owner_id ordered by date DESC, created_at DESC", async () => {
  let executedQuery = null;
  const fakeRows = [
    {
      id: "uuid-1",
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
  assert.equal(items[0]._id, "uuid-1");
  assert.ok(executedQuery.sql.includes("ORDER BY date DESC, created_at DESC"));
  assert.deepEqual(executedQuery.params, ["user-1"]);
});

test("getExpenseById and getExpenseByLocalId query correct fields", async () => {
  const fakeRow = {
    id: "uuid-target",
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

  const byId = await getExpenseById("user-1", "uuid-target");
  assert.equal(byId._id, "uuid-target");
  assert.deepEqual(queries[0].params, ["uuid-target", "user-1"]);

  const byLocalId = await getExpenseByLocalId("user-1", "loc-target");
  assert.equal(byLocalId._id, "uuid-target");
  assert.deepEqual(queries[1].params, ["loc-target", "user-1"]);
});

test("updateExpenseById supports partial updates preserving existing fields", async () => {
  const existingRow = {
    id: "uuid-update",
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

  const result = await updateExpenseById("user-1", "uuid-update", {
    name: "New Name",
  });

  assert.equal(result.name, "New Name");
  assert.equal(result.amount, 10000); // Preserved from existing
  assert.deepEqual(updateParams, [
    "uuid-update",
    "user-1",
    "New Name",
    10000,
    "makanan",
    "expected",
    "2026-10-01",
  ]);
});

test("deleteExpenseById and deleteAllExpenses execute deletes", async () => {
  const queries = [];
  setPool({
    async query(sql, params) {
      queries.push({ sql, params });
      return { rowCount: 5 };
    },
  });

  await deleteExpenseById("user-1", "uuid-to-delete");
  assert.deepEqual(queries[0].params, ["uuid-to-delete", "user-1"]);

  const count = await deleteAllExpenses("user-1");
  assert.equal(count, 5);
  assert.deepEqual(queries[1].params, ["user-1"]);
});

test("upsertNotificationReference and loadNotificationReferenceItems handle JSONB", async () => {
  let upsertParams = null;
  const items = [{ expenseitem: "Kopi", expenseprice: 15000 }];

  setPool({
    async query(sql, params) {
      if (sql.startsWith("INSERT")) {
        upsertParams = params;
        return { rows: [{ items }] };
      }
      return { rows: [{ items }] };
    },
  });

  const saved = await upsertNotificationReference("user-1", items);
  assert.deepEqual(saved, items);
  assert.equal(upsertParams[0], "user-1");
  assert.equal(upsertParams[1], JSON.stringify(items));

  const loaded = await loadNotificationReferenceItems("user-1");
  assert.deepEqual(loaded, items);
});
