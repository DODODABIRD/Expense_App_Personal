const { requireAuth } = require("../middleware/auth");
const {
  loadNotificationContext,
  refreshNotificationContext,
  MAX_NOTIFICATION_CONTEXT_ITEMS,
} = require("../services/notificationContext");
const {
  listRecentExpensesForContext,
  upsertNotificationReference,
  loadNotificationReferenceItems,
  connectDB,
} = require("../db");

async function putNotificationReference(req, res) {
  if (!Array.isArray(req.body?.items)) {
    return res.status(400).json({ error: "items must be an array" });
  }

  const items = [];
  for (const item of req.body.items.slice(0, MAX_NOTIFICATION_CONTEXT_ITEMS)) {
    const expenseitem = String(item?.expenseitem || "").trim();
    const expenseprice = Number(item?.expenseprice);
    if (
      !expenseitem ||
      !Number.isSafeInteger(expenseprice) ||
      expenseprice <= 0
    ) {
      return res
        .status(400)
        .json({ error: "Each item needs a name and positive integer price" });
    }
    const contextItem = { expenseitem, expenseprice };
    for (const field of ["category", "type", "date"]) {
      const value = item?.[field]?.toString().trim();
      if (value) contextItem[field] = value;
    }
    items.push(contextItem);
  }

  try {
    await connectDB();
    const savedItems = await upsertNotificationReference(req.user.uid, items);
    return res.json({ updated: true, itemCount: savedItems.length });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

async function refreshNotificationRef(req, res) {
  try {
    await connectDB();
    const itemCount = await refreshNotificationContext({
      query: {
        listRecentExpenses: listRecentExpensesForContext,
        upsertReference: upsertNotificationReference,
      },
      ownerId: req.user.uid,
    });
    return res.json({ updated: true, itemCount });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

module.exports = {
  putNotificationReference,
  refreshNotificationRef,
};
