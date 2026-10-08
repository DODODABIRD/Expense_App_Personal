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

const app = require("../api/index");

test("Express /api/users API contract with Postgres backend", async (t) => {
  let server;
  let baseUrl;

  // In-memory table to simulate Postgres
  const dbStore = new Map();
  let aiRefStore = new Map();

  const mockPool = {
    async query(sql, params) {
      const trimmed = sql.trim();

      // ensureSchema
      if (trimmed.startsWith("CREATE TABLE")) {
        return { rows: [] };
      }

      // upsertExpense
      if (trimmed.startsWith("INSERT INTO expenses")) {
        const [ownerId, localId, name, amount, category, type, date] = params;
        const key = `${ownerId}:${localId}`;
        const existing = dbStore.get(key);
        const row = {
          id: existing ? existing.id : "11111111-2222-3333-4444-555555555555",
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

      // getExpenseById
      if (trimmed.startsWith("SELECT * FROM expenses WHERE id = $1 AND owner_id = $2")) {
        const [id, ownerId] = params;
        if (id === "not-a-uuid") {
          const err = new Error("invalid input syntax for type uuid");
          err.code = "22P02";
          throw err;
        }
        const row = Array.from(dbStore.values()).find(
          (r) => r.id === id && r.owner_id === ownerId
        );
        return { rows: row ? [row] : [] };
      }

      // getExpenseByLocalId
      if (trimmed.startsWith("SELECT * FROM expenses WHERE local_id = $1 AND owner_id = $2")) {
        const [localId, ownerId] = params;
        const row = Array.from(dbStore.values()).find(
          (r) => r.local_id === localId && r.owner_id === ownerId
        );
        return { rows: row ? [row] : [] };
      }

      // updateExpenseById
      if (trimmed.startsWith("UPDATE expenses")) {
        const [id, ownerId, name, amount, category, type, date] = params;
        if (id === "not-a-uuid") {
          const err = new Error("invalid input syntax for type uuid");
          err.code = "22P02";
          throw err;
        }
        let updatedRow = null;
        for (const [key, row] of dbStore.entries()) {
          if (row.id === id && row.owner_id === ownerId) {
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

      // deleteExpenseById
      if (trimmed.startsWith("DELETE FROM expenses WHERE id = $1 AND owner_id = $2")) {
        const [id, ownerId] = params;
        if (id === "not-a-uuid") {
          const err = new Error("invalid input syntax for type uuid");
          err.code = "22P02";
          throw err;
        }
        for (const [key, row] of dbStore.entries()) {
          if (row.id === id && row.owner_id === ownerId) {
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
        const [ownerId, itemsJson] = params;
        const items = JSON.parse(itemsJson);
        aiRefStore.set(ownerId, items);
        return { rows: [{ items }] };
      }

      // loadNotificationReferenceItems
      if (trimmed.startsWith("SELECT items FROM ai_notification_references")) {
        const [ownerId] = params;
        const items = aiRefStore.get(ownerId) || [];
        return { rows: [{ items }] };
      }

      return { rows: [] };
    },
  };

  setPool(mockPool);

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
    assert.equal(created._id, "11111111-2222-3333-4444-555555555555");
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
    assert.equal(list[0]._id, created._id);

    // 3. GET /api/users/:id - Read one
    const getRes = await fetch(`${baseUrl}/api/users/${created._id}`, {
      headers: authHeaders,
    });
    assert.equal(getRes.status, 200);
    const fetched = await getRes.json();
    assert.equal(fetched._id, created._id);
    assert.equal(fetched.name, "Sate Ayam");

    // 4. GET /api/users/local/:localId - Read one by localId
    const getLocalRes = await fetch(`${baseUrl}/api/users/local/local-001`, {
      headers: authHeaders,
    });
    assert.equal(getLocalRes.status, 200);
    const fetchedLocal = await getLocalRes.json();
    assert.equal(fetchedLocal.localId, "local-001");
    assert.equal(fetchedLocal._id, created._id);

    // 5. PUT /api/users/:id - Update
    const putRes = await fetch(`${baseUrl}/api/users/${created._id}`, {
      method: "PUT",
      headers: authHeaders,
      body: JSON.stringify({
        name: "Sate Ayam Madura",
        amount: 35000,
      }),
    });
    assert.equal(putRes.status, 200);
    const updated = await putRes.json();
    assert.equal(updated._id, created._id);
    assert.equal(updated.name, "Sate Ayam Madura");
    assert.equal(updated.amount, 35000);
    assert.equal(updated.category, "makanan"); // Preserved

    // 6. Test invalid UUID error handling -> 404
    const invalidUuidRes = await fetch(`${baseUrl}/api/users/not-a-uuid`, {
      headers: authHeaders,
    });
    assert.equal(invalidUuidRes.status, 404);

    // 7. Refresh notification context
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

    // 8. DELETE /api/users/:id
    const deleteRes = await fetch(`${baseUrl}/api/users/${created._id}`, {
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
  } finally {
    server.close();
  }
});
