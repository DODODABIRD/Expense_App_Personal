const { requireAuth } = require("../middleware/auth");
const {
  listExpenses,
  upsertExpense,
  upsertExpensesBulk,
  upsertDeviceSync,
  getExpenseByLocalId,
  updateExpenseByLocalId,
  deleteExpenseByLocalId,
  deleteAllExpenses,
  connectDB,
} = require("../db");
const { broadcastLiveChange } = require("../lib/broadcast");

const MAX_BULK_EXPENSES = 1000;

/**
 * CREATE
 * POST /api/users
 */
async function createExpense(req, res) {
  try {
    await connectDB();
    if (!req.body.localId) {
      return res.status(400).json({ error: "localId is required" });
    }
    const user = await upsertExpense(req.user.uid, {
      localId: req.body.localId,
      name: req.body.name,
      amount: req.body.amount,
      category: req.body.category,
      type: req.body.type,
      date: req.body.date,
    });
    broadcastLiveChange(req.user.uid, { type: "expense_created", item: user });
    res.status(200).json(user);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

/**
 * READ (all)
 * GET /api/users
 */
async function listAllExpenses(req, res) {
  try {
    await connectDB();
    const users = await listExpenses(req.user.uid);
    res.json(users);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/**
 * READ (one)
 * GET /api/users/:localId
 */
async function getExpense(req, res) {
  try {
    await connectDB();
    const user = await getExpenseByLocalId(req.user.uid, req.params.localId);
    if (!user) return res.status(404).json({ message: "Not found" });
    res.json(user);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/**
 * UPDATE
 * PUT /api/users/:localId
 */
async function updateExpense(req, res) {
  try {
    await connectDB();
    const updates = {
      name: req.body.name,
      amount: req.body.amount,
      category: req.body.category,
      type: req.body.type,
      date: req.body.date,
    };
    const user = await updateExpenseByLocalId(
      req.user.uid,
      req.params.localId,
      updates
    );
    if (!user) return res.status(404).json({ message: "Not found" });
    broadcastLiveChange(req.user.uid, { type: "expense_updated", item: user });
    res.json(user);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

/**
 * DELETE
 * DELETE /api/users/:localId
 */
async function removeExpense(req, res) {
  try {
    await connectDB();
    await deleteExpenseByLocalId(req.user.uid, req.params.localId);
    broadcastLiveChange(req.user.uid, {
      type: "expense_deleted",
      localId: req.params.localId,
    });
    res.json({ message: "Deleted" });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/**
 * BULK DELETE
 * POST /api/users/delete-all
 */
async function deleteAllUserExpenses(req, res) {
  try {
    await connectDB();
    const deletedCount = await deleteAllExpenses(req.user.uid);
    broadcastLiveChange(req.user.uid, { type: "bulk_deleted", deletedCount });
    res.status(200).json({ message: "Deleted", deletedCount });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/**
 * BULK UPSERT
 * POST /api/users/bulk
 */
async function bulkUpsertExpenses(req, res) {
  const expenses = req.body?.expenses;
  if (!Array.isArray(expenses)) {
    return res.status(400).json({ error: "expenses array is required" });
  }
  if (expenses.length > MAX_BULK_EXPENSES) {
    return res
      .status(400)
      .json({ error: `At most ${MAX_BULK_EXPENSES} expenses per request` });
  }
  for (const item of expenses) {
    if (
      !item ||
      item.localId === undefined ||
      item.localId === null ||
      String(item.localId).trim() === ""
    ) {
      return res
        .status(400)
        .json({ error: "Every expense must include a localId" });
    }
  }

  try {
    await connectDB();
    const syncedLocalIds =
      expenses.length > 0
        ? await upsertExpensesBulk(req.user.uid, expenses)
        : [];

    const device = req.body?.device;
    if (device && String(device.deviceId || "").trim()) {
      try {
        await upsertDeviceSync(req.user.uid, {
          deviceId: String(device.deviceId).trim(),
          deviceName: device.deviceName,
          platform: device.platform,
          appVersion: device.appVersion,
          expenseCount: device.expenseCount,
        });
      } catch (err) {
        console.error("Bulk sync device heartbeat error:", err.message);
      }
    }

    if (syncedLocalIds.length > 0) {
      broadcastLiveChange(req.user.uid, {
        type: "bulk_upserted",
        count: syncedLocalIds.length,
      });
    }

    res.status(200).json({
      count: syncedLocalIds.length,
      syncedLocalIds,
    });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

module.exports = {
  createExpense,
  bulkUpsertExpenses,
  listAllExpenses,
  getExpense,
  updateExpense,
  removeExpense,
  deleteAllUserExpenses,
};
