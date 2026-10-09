const { requireAuth } = require("../middleware/auth");
const {
  listExpenses,
  upsertExpense,
  getExpenseById,
  getExpenseByLocalId,
  updateExpenseById,
  deleteExpenseById,
  deleteAllExpenses,
  connectDB,
  isInvalidUuidError,
} = require("../db");
const { broadcastLiveChange } = require("../lib/broadcast");

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
 * GET /api/users/:id
 */
async function getExpense(req, res) {
  try {
    await connectDB();
    const user = await getExpenseById(req.user.uid, req.params.id);
    if (!user) return res.status(404).json({ message: "Not found" });
    res.json(user);
  } catch (err) {
    if (isInvalidUuidError(err)) {
      return res.status(404).json({ message: "Not found" });
    }
    res.status(500).json({ error: err.message });
  }
}

/**
 * UPDATE
 * PUT /api/users/:id
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
    const user = await updateExpenseById(req.user.uid, req.params.id, updates);
    if (!user) return res.status(404).json({ message: "Not found" });
    broadcastLiveChange(req.user.uid, { type: "expense_updated", item: user });
    res.json(user);
  } catch (err) {
    if (isInvalidUuidError(err)) {
      return res.status(404).json({ message: "Not found" });
    }
    res.status(400).json({ error: err.message });
  }
}

/**
 * DELETE
 * DELETE /api/users/:id
 */
async function removeExpense(req, res) {
  try {
    await connectDB();
    await deleteExpenseById(req.user.uid, req.params.id);
    broadcastLiveChange(req.user.uid, { type: "expense_deleted", id: req.params.id });
    res.json({ message: "Deleted" });
  } catch (err) {
    if (isInvalidUuidError(err)) {
      return res.status(404).json({ message: "Not found" });
    }
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
 * READ (one by localId)
 * GET /api/users/local/:localId
 */
async function getExpenseByLocal(req, res) {
  try {
    await connectDB();
    const user = await getExpenseByLocalId(req.user.uid, req.params.localId);
    if (!user) {
      return res.status(404).json({ message: "Not found" });
    }
    res.json(user);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

module.exports = {
  createExpense,
  listAllExpenses,
  getExpense,
  updateExpense,
  removeExpense,
  deleteAllUserExpenses,
  getExpenseByLocal,
};
