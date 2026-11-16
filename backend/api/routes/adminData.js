const express = require("express");
const admin = require("firebase-admin");
const db = require("../db");
const { broadcastLiveChange } = require("../lib/broadcast");
const PORTFOLIO_SEED = require("../../content/portfolio.json");
const RAG_KNOWLEDGE_SEED = require("../../public/asset/rag_knowledge.json");

const router = express.Router();

const CSV_MAX_ROWS = 5000;

function sendDbError(res, err) {
  res.status(500).json({ success: false, error: err.message });
}

function recordAdminAudit(req, action, target, detail) {
  db.connectDB()
    .then(() =>
      db.insertAdminAudit({
        actor: req.adminSession?.uid || "unknown",
        action,
        target,
        detail,
        ip: req.ip,
      })
    )
    .catch((e) => console.warn("[admin] audit log failed:", e.message));
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

// GET /api/monthly - Monthly spending trend (last 12 months)
router.get("/api/monthly", async (req, res) => {
  try {
    await db.connectDB();
    res.json({ success: true, months: await db.getMonthlyTrend() });
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/devices - Last sync report per owner/device
router.get("/api/devices", async (req, res) => {
  try {
    await db.connectDB();
    res.json({
      success: true,
      devices: await db.listDeviceSyncs(req.query.owner),
    });
  } catch (err) {
    sendDbError(res, err);
  }
});

// PUT /api/expenses/:ownerId/:localId - Support edit of a single expense
router.put("/api/expenses/:ownerId/:localId", async (req, res) => {
  const ownerId = String(req.params.ownerId || "").trim();
  const localId = String(req.params.localId || "").trim();
  if (!ownerId || !localId) {
    return res
      .status(400)
      .json({ success: false, error: "ownerId and localId are required" });
  }

  if (
    req.body?.amount !== undefined &&
    !Number.isFinite(Number(req.body.amount))
  ) {
    return res.status(400).json({ success: false, error: "amount must be a number" });
  }

  try {
    await db.connectDB();
    const expense = await db.updateExpenseByLocalId(ownerId, localId, {
      name: req.body?.name,
      amount: req.body?.amount,
      category: req.body?.category,
      type: req.body?.type,
      date: req.body?.date,
    });
    if (!expense) {
      return res.status(404).json({ success: false, error: "Expense not found" });
    }
    broadcastLiveChange(ownerId, { type: "expense_updated", item: expense });
    recordAdminAudit(req, "expense_updated", `${ownerId}/${localId}`, {
      name: expense.name,
      amount: expense.amount,
    });
    res.json({ success: true, expense });
  } catch (err) {
    sendDbError(res, err);
  }
});

// DELETE /api/expenses/:ownerId/:localId - Support removal of a single expense
router.delete("/api/expenses/:ownerId/:localId", async (req, res) => {
  const ownerId = String(req.params.ownerId || "").trim();
  const localId = String(req.params.localId || "").trim();
  if (!ownerId || !localId) {
    return res
      .status(400)
      .json({ success: false, error: "ownerId and localId are required" });
  }

  try {
    await db.connectDB();
    const existing = await db.getExpenseByLocalId(ownerId, localId);
    if (!existing) {
      return res.status(404).json({ success: false, error: "Expense not found" });
    }
    await db.deleteExpenseByLocalId(ownerId, localId);
    broadcastLiveChange(ownerId, { type: "expense_deleted", localId });
    recordAdminAudit(req, "expense_deleted", `${ownerId}/${localId}`, {
      name: existing.name,
      amount: existing.amount,
    });
    res.json({ success: true, localId });
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/portfolio - Editable portfolio content
router.get("/api/portfolio", async (req, res) => {
  try {
    await db.connectDB();
    res.json({ success: true, content: await db.getPortfolioContent() });
  } catch (err) {
    res.json({
      success: true,
      content: PORTFOLIO_SEED,
      source: "file",
      warning: err.message,
    });
  }
});

// PUT /api/portfolio - Replace portfolio content
router.put("/api/portfolio", async (req, res) => {
  const content = req.body?.content || req.body;
  if (!content || typeof content !== "object" || Array.isArray(content)) {
    return res
      .status(400)
      .json({ success: false, error: "content must be a JSON object" });
  }
  for (const key of ["profile", "featured", "apk"]) {
    if (
      content[key] !== undefined &&
      (typeof content[key] !== "object" || Array.isArray(content[key]))
    ) {
      return res
        .status(400)
        .json({ success: false, error: `${key} must be an object` });
    }
  }
  for (const key of ["projects", "experience"]) {
    if (content[key] !== undefined && !Array.isArray(content[key])) {
      return res.status(400).json({ success: false, error: `${key} must be an array` });
    }
  }

  try {
    await db.connectDB();
    await db.savePortfolioContent(content);
    recordAdminAudit(req, "portfolio_updated", "portfolio_content", {
      projects: Array.isArray(content.projects) ? content.projects.length : 0,
      experience: Array.isArray(content.experience) ? content.experience.length : 0,
      apkVersion: content.apk?.version || null,
    });
    res.json({ success: true, content });
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/rag/stats - Chat volume, latency and feedback totals
router.get("/api/rag/stats", async (req, res) => {
  try {
    await db.connectDB();
    res.json({ success: true, ...(await db.getRagStats()) });
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/rag/events - Chat log with optional feedback/unanswered filter
router.get("/api/rag/events", async (req, res) => {
  try {
    await db.connectDB();
    res.json({
      success: true,
      events: await db.listRagEvents({
        limit: req.query.limit,
        feedback: req.query.feedback,
        unanswered: req.query.unanswered === "1",
      }),
    });
  } catch (err) {
    sendDbError(res, err);
  }
});

// GET /api/rag/knowledge - Current chatbot knowledge base
router.get("/api/rag/knowledge", async (req, res) => {
  try {
    await db.connectDB();
    res.json({ success: true, knowledge: await db.getRagKnowledge() });
  } catch (err) {
    res.json({
      success: true,
      knowledge: RAG_KNOWLEDGE_SEED,
      source: "file",
      warning: err.message,
    });
  }
});

// PUT /api/rag/knowledge - Replace the chatbot knowledge base
router.put("/api/rag/knowledge", async (req, res) => {
  const knowledge = req.body?.knowledge || req.body;
  if (!knowledge || typeof knowledge !== "object" || Array.isArray(knowledge)) {
    return res
      .status(400)
      .json({ success: false, error: "knowledge must be a JSON object" });
  }
  if (knowledge.faqs !== undefined && !Array.isArray(knowledge.faqs)) {
    return res.status(400).json({ success: false, error: "faqs must be an array" });
  }

  try {
    await db.connectDB();
    await db.saveRagKnowledge(knowledge);
    recordAdminAudit(req, "rag_knowledge_updated", "rag_knowledge", {
      faqs: Array.isArray(knowledge.faqs) ? knowledge.faqs.length : 0,
    });
    res.json({ success: true, knowledge });
  } catch (err) {
    sendDbError(res, err);
  }
});

// POST /api/rag/events/:id/add-to-knowledge - Turn an unanswered question into an FAQ
router.post("/api/rag/events/:id/add-to-knowledge", async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ success: false, error: "Invalid event id" });
  }

  const question = String(req.body?.question || "").trim();
  const answer = String(req.body?.answer || "").trim();
  let keywords = req.body?.keywords;
  if (Array.isArray(keywords)) {
    keywords = keywords.map((word) => String(word).trim()).filter(Boolean);
  } else {
    keywords = String(keywords || "")
      .split(",")
      .map((word) => word.trim())
      .filter(Boolean);
  }

  if (!question || !answer || keywords.length === 0) {
    return res.status(400).json({
      success: false,
      error: "question, answer and at least one keyword are required",
    });
  }

  try {
    await db.connectDB();
    const knowledge = await db.getRagKnowledge();
    knowledge.faqs = Array.isArray(knowledge.faqs) ? knowledge.faqs : [];
    knowledge.faqs.push({ keywords, question, answer });
    await db.saveRagKnowledge(knowledge);
    await db.resolveRagEvent(id);
    recordAdminAudit(req, "rag_faq_added", `rag_event:${id}`, {
      question,
      keywords,
    });
    res.json({ success: true, faqs: knowledge.faqs.length });
  } catch (err) {
    sendDbError(res, err);
  }
});

// POST /api/rag/events/:id/resolve - Dismiss an unanswered question
router.post("/api/rag/events/:id/resolve", async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ success: false, error: "Invalid event id" });
  }

  try {
    await db.connectDB();
    const resolved = await db.resolveRagEvent(id);
    if (!resolved) {
      return res.status(404).json({ success: false, error: "Chat event not found" });
    }
    recordAdminAudit(req, "rag_event_resolved", `rag_event:${id}`, {});
    res.json({ success: true });
  } catch (err) {
    sendDbError(res, err);
  }
});

module.exports = router;
