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
  normalizeExpenseFields,
  ExpenseValidationError,
} = require("../db");
const { broadcastLiveChange } = require("../lib/broadcast");

const MAX_BULK_EXPENSES = 1000;

// Validation errors are the caller's fault and safe to show; anything else is
// logged and answered with a generic message.
function sendExpenseError(res, err, context) {
  if (err instanceof ExpenseValidationError) {
    return res.status(400).json({ error: err.message });
  }
  console.error(`${context} failed:`, err);
  return res.status(500).json({ error: `Could not ${context}` });
}

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
    sendExpenseError(res, err, "save expense");
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
    sendExpenseError(res, err, "load expenses");
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
    sendExpenseError(res, err, "load expense");
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
    sendExpenseError(res, err, "update expense");
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
    sendExpenseError(res, err, "delete expense");
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
    sendExpenseError(res, err, "delete expenses");
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

  // Invalid rows are skipped, not fatal: one bad row must not block the
  // rest of a device's sync. They stay unsynced on the device.
  const validExpenses = [];
  const rejected = [];
  for (const item of expenses) {
    try {
      normalizeExpenseFields(item);
      validExpenses.push(item);
    } catch (err) {
      if (!(err instanceof ExpenseValidationError)) throw err;
      rejected.push({ localId: String(item.localId), error: err.message });
    }
  }

  try {
    await connectDB();
    const syncedLocalIds =
      validExpenses.length > 0
        ? await upsertExpensesBulk(req.user.uid, validExpenses)
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
      ...(rejected.length > 0 ? { rejected } : {}),
    });
  } catch (err) {
    sendExpenseError(res, err, "sync expenses");
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
