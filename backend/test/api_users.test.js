const assert = require("node:assert/strict");
const { test, before, after } = require("node:test");
const admin = require("firebase-admin");
const { setPool } = require("../api/db");

// Initialize mock Firebase Auth before requiring app
if (!admin.apps.length) {
  admin.initializeApp({ projectId: "test-project" });
}
const mockAuth = {
  verifyIdToken: async (token) => {
    if (token === "valid-token") {
      return { uid: "test-owner-id" };
    }
    throw new Error("Invalid token");
  },
};
try {
  admin.auth().verifyIdToken = mockAuth.verifyIdToken;
} catch (e) {}
admin.auth = () => mockAuth;

const { createApp } = require("../api/index");

test("Express /api/users API contract with Postgres backend", async (t) => {
  let server;
  let baseUrl;

  // In-memory table to simulate Postgres
  const dbStore = new Map();
  let aiRefStore = new Map();
  let aiSummaryStore = new Map();
  const deviceSyncStore = new Map();

  const mockPool = {
    async query(sql, params) {
      const trimmed = sql.trim();

      // ensureSchema
      if (trimmed.startsWith("CREATE TABLE")) {
        return { rows: [] };
      }

      // upsertExpensesBulk
      if (trimmed.startsWith("INSERT INTO expenses") && trimmed.includes("UNNEST(")) {
        const [ownerId, localIds, names, amounts, categories, types, dates] = params;
        for (let i = 0; i < localIds.length; i += 1) {
          const localId = localIds[i];
          const key = `${ownerId}:${localId}`;
          const existing = dbStore.get(key);
          const row = {
            owner_id: ownerId,
            local_id: localId,
            name: names[i],
            amount: amounts[i],
            category: categories[i],
            type: types[i],
            date: dates[i],
            created_at: existing ? existing.created_at : new Date("2026-10-08T00:00:00Z"),
            updated_at: new Date("2026-10-08T01:00:00Z"),
          };
          dbStore.set(key, row);
        }
        return { rows: [] };
      }

      // upsertExpense
      if (trimmed.startsWith("INSERT INTO expenses")) {
        const [ownerId, localId, name, amount, category, type, date] = params;
        const key = `${ownerId}:${localId}`;
        const existing = dbStore.get(key);
        const row = {
          owner_id: ownerId,
          local_id: localId,
          name,
          amount,
          category,
          type,
          date,
          created_at: existing ? existing.created_at : new Date("2026-10-08T00:00:00Z"),
          updated_at: new Date("2026-10-08T01:00:00Z"),
        };
        dbStore.set(key, row);
        return { rows: [row] };
      }

      // listExpenses
      if (trimmed.startsWith("SELECT * FROM expenses WHERE owner_id = $1 ORDER BY")) {
        const [ownerId] = params;
        const rows = Array.from(dbStore.values()).filter(
          (r) => r.owner_id === ownerId
        );
        return { rows };
      }

      // getExpenseByLocalId
      if (trimmed.startsWith("SELECT * FROM expenses WHERE local_id = $1 AND owner_id = $2")) {
        const [localId, ownerId] = params;
        const row = Array.from(dbStore.values()).find(
          (r) => r.local_id === localId && r.owner_id === ownerId
        );
        return { rows: row ? [row] : [] };
      }

      // updateExpenseByLocalId
      if (trimmed.startsWith("UPDATE expenses")) {
        const [localId, ownerId, name, amount, category, type, date] = params;
        let updatedRow = null;
        for (const [key, row] of dbStore.entries()) {
          if (row.local_id === localId && row.owner_id === ownerId) {
            updatedRow = {
              ...row,
              name,
              amount,
              category,
              type,
              date,
              updated_at: new Date("2026-10-08T02:00:00Z"),
            };
            dbStore.set(key, updatedRow);
            break;
          }
        }
        return { rows: updatedRow ? [updatedRow] : [] };
      }

      // deleteExpenseByLocalId
      if (trimmed.startsWith("DELETE FROM expenses WHERE local_id = $1 AND owner_id = $2")) {
        const [localId, ownerId] = params;
        for (const [key, row] of dbStore.entries()) {
          if (row.local_id === localId && row.owner_id === ownerId) {
            dbStore.delete(key);
            break;
          }
        }
        return { rowCount: 1 };
      }

      // deleteAllExpenses
      if (trimmed.startsWith("DELETE FROM expenses WHERE owner_id = $1")) {
        const [ownerId] = params;
        let count = 0;
        for (const [key, row] of dbStore.entries()) {
          if (row.owner_id === ownerId) {
            dbStore.delete(key);
            count++;
          }
        }
        return { rowCount: count };
      }

      // listRecentExpensesForContext
      if (trimmed.startsWith("SELECT name, amount, category, type, date, created_at")) {
        const [ownerId, limit] = params;
        const rows = Array.from(dbStore.values())
          .filter((r) => r.owner_id === ownerId)
          .slice(0, limit);
        return { rows };
      }

      // upsertNotificationReference
      if (trimmed.startsWith("INSERT INTO ai_notification_references")) {
        const [ownerId, itemsJson, summaryJson] = params;
        const items = JSON.parse(itemsJson);
        aiRefStore.set(ownerId, items);
        aiSummaryStore.set(ownerId, JSON.parse(summaryJson));
        return { rows: [{ items }] };
      }

      // loadNotificationSummary
      if (trimmed.startsWith("SELECT summary FROM ai_notification_references")) {
        const [ownerId] = params;
        return { rows: [{ summary: aiSummaryStore.get(ownerId) || {} }] };
      }

      // loadNotificationReference
      if (trimmed.startsWith("SELECT items, summary, updated_at FROM ai_notification_references")) {
        const [ownerId] = params;
        const items = aiRefStore.get(ownerId);
        if (!items) return { rows: [] };
        return {
          rows: [
            {
              items,
              summary: aiSummaryStore.get(ownerId) || {},
              updated_at: new Date("2026-10-08T02:00:00Z"),
            },
          ],
        };
      }

      // loadNotificationReferenceItems
      if (trimmed.startsWith("SELECT items FROM ai_notification_references")) {
        const [ownerId] = params;
        const items = aiRefStore.get(ownerId) || [];
        return { rows: [{ items }] };
      }

      // upsertDeviceSync
      if (trimmed.startsWith("INSERT INTO device_syncs")) {
        const [ownerId, deviceId, deviceName, platform, appVersion, expenseCount] = params;
        const row = {
          owner_id: ownerId,
          device_id: deviceId,
          device_name: deviceName,
          platform,
          app_version: appVersion,
          expense_count: expenseCount,
          last_sync_at: new Date("2026-10-08T03:00:00Z"),
        };
        deviceSyncStore.set(`${ownerId}:${deviceId}`, row);
        return { rows: [row] };
      }

      return { rows: [] };
    },
  };

  setPool(mockPool);

  const app = createApp();
  await new Promise((resolve) => {
    server = app.listen(0, () => {
      baseUrl = `http://127.0.0.1:${server.address().port}`;
      resolve();
    });
  });

  const authHeaders = {
    Authorization: "Bearer valid-token",
    "Content-Type": "application/json",
  };

  try {
    const unauthorizedRes = await fetch(`${baseUrl}/api/users`);
    assert.equal(unauthorizedRes.status, 401);

    // 1. POST /api/users - Create expense
    const createRes = await fetch(`${baseUrl}/api/users`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({
        localId: "local-001",
        name: "Sate Ayam",
        amount: 30000,
        category: "makanan",
        type: "expected",
        date: "2026-10-08",
      }),
    });
    assert.equal(createRes.status, 200);
    const created = await createRes.json();
    assert.equal(created._id, undefined);
    assert.equal(created.ownerId, "test-owner-id");
    assert.equal(created.localId, "local-001");
    assert.equal(created.name, "Sate Ayam");
    assert.equal(created.amount, 30000);
    assert.equal(created.category, "makanan");

    // 2. GET /api/users - List expenses
    const listRes = await fetch(`${baseUrl}/api/users`, {
      headers: authHeaders,
    });
    assert.equal(listRes.status, 200);
    const list = await listRes.json();
    assert.equal(list.length, 1);
    assert.equal(list[0].localId, created.localId);

    // 3. GET /api/users/:localId - Read one
    const getRes = await fetch(`${baseUrl}/api/users/${created.localId}`, {
      headers: authHeaders,
    });
    assert.equal(getRes.status, 200);
    const fetched = await getRes.json();
    assert.equal(fetched.localId, created.localId);
    assert.equal(fetched.name, "Sate Ayam");

    // 4. PUT /api/users/:localId - Update
    const putRes = await fetch(`${baseUrl}/api/users/${created.localId}`, {
      method: "PUT",
      headers: authHeaders,
      body: JSON.stringify({
        name: "Sate Ayam Madura",
        amount: 35000,
      }),
    });
    assert.equal(putRes.status, 200);
    const updated = await putRes.json();
    assert.equal(updated.localId, created.localId);
    assert.equal(updated.name, "Sate Ayam Madura");
    assert.equal(updated.amount, 35000);
    assert.equal(updated.category, "makanan"); // Preserved

    // 5. Unknown localId -> 404
    const missingRes = await fetch(`${baseUrl}/api/users/does-not-exist`, {
      headers: authHeaders,
    });
    assert.equal(missingRes.status, 404);

    // 6. Refresh notification context
    const refreshRes = await fetch(
      `${baseUrl}/api/ai-notification-reference/refresh`,
      {
        method: "POST",
        headers: authHeaders,
      }
    );
    assert.equal(refreshRes.status, 200);
    const refreshData = await refreshRes.json();
    assert.equal(refreshData.updated, true);
    assert.equal(refreshData.itemCount, 1);

    const savedSummary = aiSummaryStore.get("test-owner-id");
    assert.equal(savedSummary.sampleSize, 1);
    assert.equal(savedSummary.categories[0].category, "makanan");
    assert.deepEqual(savedSummary.categories[0].priceRange, {
      min: 35000,
      max: 35000,
    });

    // 7. GET the stored notification context template
    const contextRes = await fetch(
      `${baseUrl}/api/ai-notification-reference`,
      { headers: authHeaders }
    );
    assert.equal(contextRes.status, 200);
    const contextData = await contextRes.json();
    assert.equal(contextData.itemCount, 1);
    assert.equal(contextData.template.sampleSize, 1);
    assert.deepEqual(contextData.template.categories[0].priceRange, {
      min: 35000,
      max: 35000,
    });
    assert.equal(contextData.template.categories[0].category, "makanan");
    assert.ok(contextData.updatedAt);

    // 8. DELETE /api/users/:localId
    const deleteRes = await fetch(`${baseUrl}/api/users/${created.localId}`, {
      method: "DELETE",
      headers: authHeaders,
    });
    assert.equal(deleteRes.status, 200);
    const deleteData = await deleteRes.json();
    assert.equal(deleteData.message, "Deleted");

    // 9. Re-insert and test POST /api/users/delete-all
    await fetch(`${baseUrl}/api/users`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({
        localId: "local-002",
        name: "Es Teh",
        amount: 5000,
      }),
    });
    const bulkDeleteRes = await fetch(`${baseUrl}/api/users/delete-all`, {
      method: "POST",
      headers: authHeaders,
    });
    assert.equal(bulkDeleteRes.status, 200);
    const bulkData = await bulkDeleteRes.json();
    assert.equal(bulkData.message, "Deleted");
    assert.equal(bulkData.deletedCount, 1);

    // 10. POST /api/users/bulk requires auth and validates payload
    const unauthBulkRes = await fetch(`${baseUrl}/api/users/bulk`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ expenses: [] }),
    });
    assert.equal(unauthBulkRes.status, 401);

    const invalidTypeRes = await fetch(`${baseUrl}/api/users/bulk`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({ expenses: "not-an-array" }),
    });
    assert.equal(invalidTypeRes.status, 400);

    const missingLocalIdRes = await fetch(`${baseUrl}/api/users/bulk`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({ expenses: [{ name: "No ID", amount: 1000 }] }),
    });
    assert.equal(missingLocalIdRes.status, 400);

    const tooManyRes = await fetch(`${baseUrl}/api/users/bulk`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({
        expenses: Array.from({ length: 1001 }, (_, i) => ({
          localId: String(i + 1),
          name: "Item",
          amount: 1000,
        })),
      }),
    });
    assert.equal(tooManyRes.status, 400);

    // 11. POST /api/users/bulk with empty array succeeds cleanly
    const emptyBulkRes = await fetch(`${baseUrl}/api/users/bulk`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({ expenses: [] }),
    });
    assert.equal(emptyBulkRes.status, 200);
    assert.deepEqual(await emptyBulkRes.json(), {
      count: 0,
      syncedLocalIds: [],
    });

    // 12. POST /api/users/bulk upserts expenses, deduplicates, and records device sync
    const bulkUpsertRes = await fetch(`${baseUrl}/api/users/bulk`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({
        expenses: [
          {
            localId: "101",
            name: "Nasi Uduk",
            amount: 15000,
            category: "makanan",
            type: "expected",
            date: "2026-10-08",
          },
          {
            localId: "102",
            name: "GrabBike",
            amount: 22000,
            category: "transportasi",
            type: "unexpected",
            date: "2026-10-09",
          },
          {
            localId: "101",
            name: "Nasi Uduk Komplit",
            amount: 20000,
            category: "makanan",
            type: "expected",
            date: "2026-10-08",
          },
        ],
        device: {
          deviceId: "dev-1",
          deviceName: "android 14",
          platform: "android",
          appVersion: "2.0.0",
          expenseCount: 2,
        },
      }),
    });
    assert.equal(bulkUpsertRes.status, 200);
    assert.deepEqual(await bulkUpsertRes.json(), {
      count: 2,
      syncedLocalIds: ["101", "102"],
    });

    const listAfterBulkRes = await fetch(`${baseUrl}/api/users`, {
      headers: authHeaders,
    });
    assert.equal(listAfterBulkRes.status, 200);
    const listAfterBulk = await listAfterBulkRes.json();
    assert.equal(listAfterBulk.length, 2);
    const item101 = listAfterBulk.find((e) => e.localId === "101");
    assert.equal(item101.name, "Nasi Uduk Komplit");
    assert.equal(item101.amount, 20000);

    const syncedDevice = deviceSyncStore.get("test-owner-id:dev-1");
    assert.ok(syncedDevice);
    assert.equal(syncedDevice.expense_count, 2);
    assert.equal(syncedDevice.platform, "android");
  } finally {
    server.close();
  }
});
