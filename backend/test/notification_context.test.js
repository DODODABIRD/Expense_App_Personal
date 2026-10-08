const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  MAX_NOTIFICATION_CONTEXT_ITEMS,
  loadNotificationContext,
  refreshNotificationContext,
} = require("../api/notification_context");

test("refreshes one user context with at most 100 projected expenses", async () => {
  const state = {};
  const expenses = Array.from(
    { length: MAX_NOTIFICATION_CONTEXT_ITEMS + 1 },
    (_, index) => ({
      name: `Expense ${index}`,
      amount: index + 1,
      category: "makanan",
      type: "expected",
      date: "2026-09-27",
      created_at: new Date("2026-09-27T00:00:00Z"),
    })
  );

  const query = {
    async listRecentExpenses(ownerId, limit) {
      state.ownerId = ownerId;
      state.limit = limit;
      return expenses.slice(0, limit);
    },
    async upsertReference(ownerId, items) {
      state.upsertOwnerId = ownerId;
      state.items = items;
    },
  };

  const itemCount = await refreshNotificationContext({
    query,
    ownerId: "firebase-user-1",
  });

  assert.equal(itemCount, MAX_NOTIFICATION_CONTEXT_ITEMS);
  assert.equal(state.ownerId, "firebase-user-1");
  assert.equal(state.limit, MAX_NOTIFICATION_CONTEXT_ITEMS);
  assert.equal(state.upsertOwnerId, "firebase-user-1");
  assert.equal(state.items.length, MAX_NOTIFICATION_CONTEXT_ITEMS);
  assert.deepEqual(state.items[0], {
    expenseitem: "Expense 0",
    expenseprice: 1,
    category: "makanan",
    type: "expected",
    date: "2026-09-27",
  });
});

test("loads one user's context document and keeps legacy items compatible", async () => {
  const items = Array.from(
    { length: MAX_NOTIFICATION_CONTEXT_ITEMS + 1 },
    (_, index) => ({
      expenseitem: `Expense ${index}`,
      expenseprice: index + 1,
      category: "transportasi",
      type: "unexpected",
      date: "2026-09-27",
    })
  );

  const context = await loadNotificationContext({
    query: {
      async loadReferenceItems(ownerId) {
        assert.equal(ownerId, "firebase-user-2");
        return items;
      },
    },
    ownerId: "firebase-user-2",
  });

  assert.equal(context.length, MAX_NOTIFICATION_CONTEXT_ITEMS);
  assert.deepEqual(context[0], items[0]);

  const legacyContext = await loadNotificationContext({
    query: {
      async loadReferenceItems() {
        return [{ expenseitem: "Coffee", expenseprice: 25000 }];
      },
    },
    ownerId: "firebase-user-3",
  });
  assert.deepEqual(legacyContext, [
    { expenseitem: "Coffee", expenseprice: 25000 },
  ]);
});
