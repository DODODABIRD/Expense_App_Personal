const express = require("express");
const admin = require("firebase-admin");
const db = require("../db");

const router = express.Router();

const CSV_MAX_ROWS = 5000;

function sendDbError(res, err) {
  res.status(500).json({ success: false, error: err.message });
}

function csvCell(value) {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

// GET /api/overview - Totals, per-category and daily breakdown
router.get("/api/overview", async (req, res) => {
  try {
    await db.connectDB();
    const overview = await db.getAdminOverview();
    res.json({ success: true, ...overview });
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/owners - Expense owners with aggregate stats
router.get("/api/owners", async (req, res) => {
  try {
    await db.connectDB();
    res.json({ success: true, owners: await db.listExpenseOwners() });
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/expenses/export.csv - Export filtered expenses as CSV
router.get("/api/expenses/export.csv", async (req, res) => {
  try {
    await db.connectDB();
    const { expenses } = await db.listAdminExpenses({
      ownerId: req.query.owner,
      search: req.query.q,
      from: req.query.from,
      to: req.query.to,
      page: 1,
      pageSize: CSV_MAX_ROWS,
    });

    const header = [
      "owner_id",
      "local_id",
      "name",
      "amount",
      "category",
      "type",
      "date",
      "created_at",
      "updated_at",
    ];
    const lines = [header.join(",")];
    for (const expense of expenses) {
      lines.push(
        [
          csvCell(expense.ownerId),
          csvCell(expense.localId),
          csvCell(expense.name),
          csvCell(expense.amount),
          csvCell(expense.category),
          csvCell(expense.type),
          csvCell(expense.date),
          csvCell(expense.createdAt),
          csvCell(expense.updatedAt),
        ].join(",")
      );
    }

    const stamp = new Date().toISOString().slice(0, 10);
    res.set("Content-Type", "text/csv; charset=utf-8");
    res.set("Content-Disposition", `attachment; filename="expenses-${stamp}.csv"`);
    res.set("Cache-Control", "no-store, max-age=0");
    res.send(lines.join("\r\n"));
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/expenses - Paginated expense browser
router.get("/api/expenses", async (req, res) => {
  try {
    await db.connectDB();
    const data = await db.listAdminExpenses({
      ownerId: req.query.owner,
      search: req.query.q,
      from: req.query.from,
      to: req.query.to,
      page: req.query.page,
      pageSize: req.query.pageSize,
    });
    res.json({ success: true, ...data });
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/firebase-users - Firebase Auth user directory
router.get("/api/firebase-users", async (req, res) => {
  if (!admin.apps.length) {
    return res
      .status(503)
      .json({ success: false, error: "Firebase is not configured on this server" });
  }

  try {
    const result = await admin.auth().listUsers(1000);
    res.json({
      success: true,
      users: result.users.map((user) => ({
        uid: user.uid,
        email: user.email || null,
        displayName: user.displayName || null,
        disabled: Boolean(user.disabled),
        createdAt: user.metadata?.creationTime || null,
        lastSignInAt: user.metadata?.lastRefreshTime || null,
      })),
      truncated: result.pageToken !== undefined,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/ai-usage - Groq vs Azure provider events (last 7 days)
router.get("/api/ai-usage", async (req, res) => {
  try {
    await db.connectDB();
    const stats = await db.getAiProviderStats();
    res.json({ success: true, ...stats });
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/audit - Recent admin actions
router.get("/api/audit", async (req, res) => {
  try {
    await db.connectDB();
    const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 100));
    res.json({ success: true, logs: await db.listAdminAuditLogs(limit) });
  } catch (err) {
    sendDbError(res, err);
  }
});

module.exports = router;
