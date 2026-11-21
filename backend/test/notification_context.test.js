const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  MAX_NOTIFICATION_CONTEXT_ITEMS,
  buildNotificationTemplate,
  loadNotificationContext,
  loadNotificationTemplate,
  refreshNotificationContext,
} = require("../api/services/notificationContext");

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
    async upsertReference(ownerId, items, summary) {
      state.upsertOwnerId = ownerId;
      state.items = items;
      state.summary = summary;
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
  assert.deepEqual(state.summary, buildNotificationTemplate(state.items));
  assert.equal(state.summary.categories[0].category, "makanan");
  assert.deepEqual(state.summary.categories[0].priceRange, { min: 1, max: 100 });
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

test("builds a compact template with one price range per category", () => {
  const items = [
    { expenseitem: "Nasi Goreng", expenseprice: 20000, category: "makanan", type: "expected" },
    { expenseitem: "Sate Ayam", expenseprice: 22000, category: "makanan", type: "expected" },
    { expenseitem: "nasi goreng", expenseprice: 25000, category: "makanan", type: "unexpected" },
    { expenseitem: "Bakso", expenseprice: 30000, category: "makanan", type: "expected" },
    { expenseitem: "Nasi Goreng", expenseprice: 28000, category: "makanan", type: "expected" },
    { expenseitem: "Ojek", expenseprice: 15000, category: "transportasi", type: "unexpected" },
    { expenseitem: "", expenseprice: 10000, category: "makanan" },
    { expenseitem: "Bad amount", expenseprice: 0, category: "makanan" },
  ];

  const summary = buildNotificationTemplate(items);

  assert.equal(summary.version, 1);
  assert.equal(summary.sampleSize, 6);
  assert.deepEqual(summary.priceRange, { min: 15000, max: 30000 });

  const food = summary.categories.find((entry) => entry.category === "makanan");
  assert.equal(food.count, 5);
  assert.deepEqual(food.priceRange, { min: 20000, max: 30000 });
  assert.equal(food.averagePrice, 25000);
  assert.deepEqual(food.commonItems, ["Nasi Goreng", "Bakso", "Sate Ayam"]);
  assert.deepEqual(food.types, ["expected", "unexpected"]);

  const transport = summary.categories.find(
    (entry) => entry.category === "transportasi"
  );
  assert.deepEqual(transport.priceRange, { min: 15000, max: 15000 });
});

test("builds an empty template when there is nothing to summarize", () => {
  assert.deepEqual(buildNotificationTemplate([]), {
    version: 1,
    sampleSize: 0,
    priceRange: null,
    categories: [],
  });
});

test("prefers the stored template and rebuilds it for legacy documents", async () => {
  const stored = {
    version: 1,
    sampleSize: 1,
    priceRange: { min: 20000, max: 20000 },
    categories: [],
  };

  const fromStore = await loadNotificationTemplate({
    query: {
      async loadTemplate(ownerId) {
        assert.equal(ownerId, "firebase-user-4");
        return stored;
      },
      async loadReferenceItems() {
        throw new Error("should not read raw items");
      },
    },
    ownerId: "firebase-user-4",
  });
  assert.deepEqual(fromStore, stored);

  const rebuilt = await loadNotificationTemplate({
    query: {
      async loadTemplate() {
        return {};
      },
      async loadReferenceItems() {
        return [
          { expenseitem: "Kopi", expenseprice: 18000, category: "makanan" },
        ];
      },
    },
    ownerId: "firebase-user-5",
  });
  assert.equal(rebuilt.sampleSize, 1);
  assert.deepEqual(rebuilt.categories[0].priceRange, {
    min: 18000,
    max: 18000,
  });
});
