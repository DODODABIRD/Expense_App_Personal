const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  EXPENSE_CONTEXT_PROJECTION,
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
      createdAt: new Date("2026-09-27T00:00:00Z"),
    })
  );
  const query = {
    select(value) {
      state.projection = value;
      return this;
    },
    sort(value) {
      state.sort = value;
      return this;
    },
    limit(value) {
      state.limit = value;
      return this;
    },
    lean() {
      return Promise.resolve(expenses);
    },
  };
  const Expense = {
    find(filter) {
      state.filter = filter;
      return query;
    },
  };
  const Reference = {
    async findOneAndUpdate(...args) {
      state.upsert = args;
    },
  };

  const itemCount = await refreshNotificationContext({
    Expense,
    Reference,
    ownerId: "firebase-user-1",
  });

  assert.equal(itemCount, MAX_NOTIFICATION_CONTEXT_ITEMS);
  assert.deepEqual(state.filter, { ownerId: "firebase-user-1" });
  assert.equal(state.projection, EXPENSE_CONTEXT_PROJECTION);
  assert.deepEqual(state.sort, { date: -1, createdAt: -1 });
  assert.equal(state.limit, MAX_NOTIFICATION_CONTEXT_ITEMS);
  assert.deepEqual(state.upsert[0], { ownerId: "firebase-user-1" });
  assert.equal(state.upsert[1].$set.items.length, MAX_NOTIFICATION_CONTEXT_ITEMS);
  assert.deepEqual(state.upsert[1].$set.items[0], {
    expenseitem: "Expense 0",
    expenseprice: 1,
    category: "makanan",
    type: "expected",
    date: "2026-09-27",
  });
  assert.equal(state.upsert[2].upsert, true);
});

test("loads one user's context document and keeps legacy items compatible", async () => {
  const state = { findCalls: 0 };
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
  const query = {
    select(value) {
      state.projection = value;
      return this;
    },
    lean() {
      return Promise.resolve({ items });
    },
  };
  const Reference = {
    findOne(filter) {
      state.findCalls += 1;
      state.filter = filter;
      return query;
    },
  };

  const context = await loadNotificationContext({
    Reference,
    ownerId: "firebase-user-2",
  });

  assert.equal(state.findCalls, 1);
  assert.deepEqual(state.filter, { ownerId: "firebase-user-2" });
  assert.equal(state.projection, "items");
  assert.equal(context.length, MAX_NOTIFICATION_CONTEXT_ITEMS);
  assert.deepEqual(context[0], items[0]);

  const legacyContext = await loadNotificationContext({
    Reference: {
      findOne() {
        return {
          select() {
            return this;
          },
          lean: async () => ({
            items: [{ expenseitem: "Coffee", expenseprice: 25000 }],
          }),
        };
      },
    },
    ownerId: "firebase-user-3",
  });
  assert.deepEqual(legacyContext, [
    { expenseitem: "Coffee", expenseprice: 25000 },
  ]);
});