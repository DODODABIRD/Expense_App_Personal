const express = require("express");
const admin = require("firebase-admin");
const db = require("../db");
const { broadcastLiveChange } = require("../lib/broadcast");
const r2 = require("../services/r2Service");
const PORTFOLIO_SEED = require("../../content/portfolio.json");
const RAG_KNOWLEDGE_SEED = require("../../public/asset/rag_knowledge.json");

const router = express.Router();

const CSV_MAX_ROWS = 5000;

const DOWNLOAD_URL_PATTERN = /^(https?:\/\/|\/(?!\/))/i;
const APP_SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function sendDbError(res, err) {
  res.status(500).json({ success: false, error: err.message });
}

function isUniqueViolation(err) {
  return Boolean(err && err.code === "23505");
}

function normalizeDownloadApp(input) {
  const source = input && typeof input === "object" && !Array.isArray(input) ? input : {};
  const slug = String(source.slug || "").trim().toLowerCase();
  if (!APP_SLUG_PATTERN.test(slug)) {
    return { error: "slug must use lowercase letters, numbers and dashes" };
  }
  if (slug.length > 40) return { error: "slug is too long" };

  const name = String(source.name || "").trim();
  if (!name) return { error: "name is required" };

  const iconUrl = String(source.icon_url || "").trim();
  if (iconUrl && !DOWNLOAD_URL_PATTERN.test(iconUrl)) {
    return { error: "icon_url must start with / or http(s)://" };
  }

  let sortOrder = 0;
  if (source.sort_order !== undefined && source.sort_order !== null && source.sort_order !== "") {
    sortOrder = Number(source.sort_order);
    if (!Number.isFinite(sortOrder)) {
      return { error: "sort_order must be a number" };
    }
  }

  return {
    app: {
      slug,
      name: name.slice(0, 120),
      tagline: String(source.tagline || "").trim().slice(0, 300),
      description: String(source.description || "").trim().slice(0, 2000),
      icon_url: iconUrl,
      accent: String(source.accent || "").trim().slice(0, 20),
      sort_order: Math.round(sortOrder),
      active:
        source.active === undefined
          ? true
          : source.active === true || source.active === "true",
    },
  };
}

function normalizeDownloadRelease(input, { allowEmptyUrl = false } = {}) {
  const source = input && typeof input === "object" && !Array.isArray(input) ? input : {};
  const version = String(source.version || "").trim().replace(/^v/i, "");
  if (!version) return { error: "version is required" };
  if (version.length > 40) return { error: "version is too long" };

  const url = String(source.url || "").trim();
  if (!url && !allowEmptyUrl) return { error: "url is required" };
  if (url && !DOWNLOAD_URL_PATTERN.test(url)) {
    return { error: "url must start with / or http(s)://" };
  }
  if (url.length > 2048) return { error: "url is too long" };

  const releasedAt = String(source.released_at || "").trim();
  if (releasedAt && !/^\d{4}-\d{2}-\d{2}$/.test(releasedAt)) {
    return { error: "released_at must be in YYYY-MM-DD format" };
  }

  let sizeBytes = 0;
  if (
    source.size_bytes !== undefined &&
    source.size_bytes !== null &&
    source.size_bytes !== ""
  ) {
    sizeBytes = Number(source.size_bytes);
    if (!Number.isFinite(sizeBytes) || sizeBytes < 0) {
      return { error: "size_bytes must be a non-negative number" };
    }
  }

  const r2Key = String(source.r2_key || "").trim() || null;

  return {
    release: {
      version,
      url,
      size_bytes: Math.round(sizeBytes),
      released_at: releasedAt,
      notes: String(source.notes || "").trim().slice(0, 300),
      r2_key: r2Key,
    },
  };
}

async function cleanupR2Object(r2Key, { excludeReleaseId = null } = {}) {
  if (!r2Key || !r2.isConfigured()) {
    return { deleted: false, warning: null };
  }
  try {
    const remaining = await db.countReleasesByR2Key(r2Key, {
      excludeId: excludeReleaseId,
    });
    if (remaining > 0) {
      return { deleted: false, warning: null };
    }
    await r2.deleteObject(r2Key);
    return { deleted: true, warning: null };
  } catch (err) {
    console.warn("[admin] R2 cleanup failed:", err.message);
    return { deleted: false, warning: err.message };
  }
}

async function resolveR2ReleasePayload(slug, r2Key, releaseFields) {
  if (!r2.isConfigured()) {
    return { status: 503, error: "Cloudflare R2 is not configured on this server" };
  }
  if (!r2.isValidReleaseKeyForApp(slug, r2Key)) {
    return { status: 400, error: "Invalid R2 object key" };
  }
  const head = await r2.headObject(r2Key);
  if (!head) {
    return {
      status: 400,
      error: "Uploaded file was not found in R2. Please upload again.",
    };
  }
  return {
    release: {
      ...releaseFields,
      r2_key: r2Key,
      url: r2.getPublicUrl(r2Key),
      size_bytes: head.sizeBytes,
    },
  };
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

// GET /api/downloads - App download catalog for the admin panel
router.get("/api/downloads", async (req, res) => {
  try {
    await db.connectDB();
    res.json({
      success: true,
      apps: await db.listDownloadApps({
        includeInactive: true,
        includeStorageKey: true,
      }),
      r2Configured: r2.isConfigured(),
    });
  } catch (err) {
    sendDbError(res, err);
  }
});

// POST /api/downloads/apps - Create an app in the download catalog
router.post("/api/downloads/apps", async (req, res) => {
  const normalized = normalizeDownloadApp(req.body?.app || req.body);
  if (normalized.error) {
    return res.status(400).json({ success: false, error: normalized.error });
  }

  try {
    await db.connectDB();
    const app = await db.createDownloadApp(normalized.app);
    recordAdminAudit(req, "download_app_created", `download_app:${app.slug}`, {
      name: app.name,
    });
    res.status(201).json({ success: true, app });
  } catch (err) {
    if (isUniqueViolation(err)) {
      return res.status(409).json({ success: false, error: "Slug already exists" });
    }
    sendDbError(res, err);
  }
});

// PUT /api/downloads/apps/:slug - Update app metadata
router.put("/api/downloads/apps/:slug", async (req, res) => {
  const slug = String(req.params.slug || "").trim().toLowerCase();
  const input = req.body?.app || req.body;
  const normalized = normalizeDownloadApp({
    ...(input && typeof input === "object" && !Array.isArray(input) ? input : {}),
    slug,
  });
  if (normalized.error) {
    return res.status(400).json({ success: false, error: normalized.error });
  }

  try {
    await db.connectDB();
    const app = await db.updateDownloadApp(slug, normalized.app);
    if (!app) {
      return res.status(404).json({ success: false, error: "App not found" });
    }
    recordAdminAudit(req, "download_app_updated", `download_app:${slug}`, {
      name: app.name,
      active: app.active,
    });
    res.json({ success: true, app });
  } catch (err) {
    if (isUniqueViolation(err)) {
      return res.status(409).json({ success: false, error: "Slug already exists" });
    }
    sendDbError(res, err);
  }
});

// DELETE /api/downloads/apps/:slug - Remove an app and its releases
router.delete("/api/downloads/apps/:slug", async (req, res) => {
  const slug = String(req.params.slug || "").trim().toLowerCase();
  try {
    await db.connectDB();
    const r2Keys = await db.listAppReleaseR2Keys(slug);
    const deleted = await db.deleteDownloadApp(slug);
    if (!deleted) {
      return res.status(404).json({ success: false, error: "App not found" });
    }

    let deletedR2Files = 0;
    const r2Warnings = [];
    for (const key of r2Keys) {
      const cleanup = await cleanupR2Object(key);
      if (cleanup.deleted) deletedR2Files += 1;
      if (cleanup.warning) r2Warnings.push(cleanup.warning);
    }

    recordAdminAudit(req, "download_app_deleted", `download_app:${slug}`, {
      deletedR2Files,
    });
    res.json({
      success: true,
      deletedR2Files,
      ...(r2Warnings.length ? { r2Warnings } : {}),
    });
  } catch (err) {
    sendDbError(res, err);
  }
});

// POST /api/downloads/apps/:slug/releases/presign - Sign a direct R2 upload URL
router.post("/api/downloads/apps/:slug/releases/presign", async (req, res) => {
  const slug = String(req.params.slug || "").trim().toLowerCase();
  if (!r2.isConfigured()) {
    return res
      .status(503)
      .json({ success: false, error: "Cloudflare R2 is not configured on this server" });
  }

  const version = String(req.body?.version || "").trim().replace(/^v/i, "");
  if (!version) {
    return res.status(400).json({ success: false, error: "version is required" });
  }
  if (version.length > 40) {
    return res.status(400).json({ success: false, error: "version is too long" });
  }

  let releaseId = null;
  if (
    req.body?.releaseId !== undefined &&
    req.body?.releaseId !== null &&
    req.body?.releaseId !== ""
  ) {
    releaseId = Number(req.body.releaseId);
    if (!Number.isInteger(releaseId) || releaseId <= 0) {
      return res.status(400).json({ success: false, error: "Invalid release id" });
    }
  }

  try {
    await db.connectDB();
    const app = await db.getDownloadApp(slug, { includeInactive: true });
    if (!app) {
      return res.status(404).json({ success: false, error: "App not found" });
    }

    if (releaseId !== null) {
      const existingRelease = await db.getDownloadReleaseById(releaseId);
      if (!existingRelease || existingRelease.app_slug !== slug) {
        return res.status(404).json({ success: false, error: "Release not found" });
      }
    }

    const duplicate = await db.hasDownloadReleaseVersion(slug, version, {
      excludeId: releaseId,
    });
    if (duplicate) {
      return res
        .status(409)
        .json({ success: false, error: "That version already exists for this app" });
    }

    const presigned = await r2.createReleaseUploadUrl({
      slug,
      version,
      filename: req.body?.filename,
      sizeBytes: req.body?.size_bytes ?? req.body?.sizeBytes,
    });
    res.json({ success: true, ...presigned });
  } catch (err) {
    if (err?.status === 400 || err?.status === 413 || err?.status === 503) {
      return res.status(err.status).json({ success: false, error: err.message });
    }
    sendDbError(res, err);
  }
});

// POST /api/downloads/apps/:slug/releases - Add a release
router.post("/api/downloads/apps/:slug/releases", async (req, res) => {
  const slug = String(req.params.slug || "").trim().toLowerCase();
  const rawInput = req.body?.release || req.body;
  const incomingR2Key = String(rawInput?.r2_key || "").trim() || null;

  const normalized = normalizeDownloadRelease(rawInput, {
    allowEmptyUrl: Boolean(incomingR2Key),
  });
  if (normalized.error) {
    return res.status(400).json({ success: false, error: normalized.error });
  }

  try {
    await db.connectDB();
    const app = await db.getDownloadApp(slug, { includeInactive: true });
    if (!app) {
      return res.status(404).json({ success: false, error: "App not found" });
    }

    let releasePayload = { ...normalized.release, r2_key: null };
    if (incomingR2Key) {
      const resolved = await resolveR2ReleasePayload(slug, incomingR2Key, releasePayload);
      if (resolved.error) {
        return res
          .status(resolved.status)
          .json({ success: false, error: resolved.error });
      }
      releasePayload = resolved.release;
    }

    let release;
    try {
      release = await db.createDownloadRelease(slug, releasePayload);
    } catch (dbErr) {
      if (incomingR2Key) {
        await cleanupR2Object(incomingR2Key);
      }
      throw dbErr;
    }

    recordAdminAudit(
      req,
      "download_release_created",
      `download_app:${slug}`,
      { version: release.version, r2Key: release.r2_key || null }
    );
    res.status(201).json({ success: true, release });
  } catch (err) {
    if (isUniqueViolation(err)) {
      return res
        .status(409)
        .json({ success: false, error: "That version already exists for this app" });
    }
    sendDbError(res, err);
  }
});

// PUT /api/downloads/releases/:id - Update a release
router.put("/api/downloads/releases/:id", async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ success: false, error: "Invalid release id" });
  }

  const rawInput = req.body?.release || req.body;
  const incomingR2Key = String(rawInput?.r2_key || "").trim() || null;

  try {
    await db.connectDB();
    const existing = await db.getDownloadReleaseById(id);
    if (!existing) {
      return res.status(404).json({ success: false, error: "Release not found" });
    }

    const slug = existing.app_slug;
    const isNewR2Upload = Boolean(incomingR2Key && incomingR2Key !== existing.r2_key);

    const normalized = normalizeDownloadRelease(rawInput, {
      allowEmptyUrl: isNewR2Upload,
    });
    if (normalized.error) {
      return res.status(400).json({ success: false, error: normalized.error });
    }

    let releasePayload = { ...normalized.release };
    let oldKeyToDelete = null;

    if (isNewR2Upload) {
      const resolved = await resolveR2ReleasePayload(slug, incomingR2Key, releasePayload);
      if (resolved.error) {
        return res
          .status(resolved.status)
          .json({ success: false, error: resolved.error });
      }
      releasePayload = resolved.release;
      if (existing.r2_key) oldKeyToDelete = existing.r2_key;
    } else if (existing.r2_key && releasePayload.url === existing.url) {
      releasePayload.r2_key = existing.r2_key;
    } else {
      releasePayload.r2_key = null;
      if (existing.r2_key) oldKeyToDelete = existing.r2_key;
    }

    let release;
    try {
      release = await db.updateDownloadRelease(id, releasePayload);
    } catch (dbErr) {
      if (isNewR2Upload && incomingR2Key) {
        await cleanupR2Object(incomingR2Key, { excludeReleaseId: id });
      }
      throw dbErr;
    }
    if (!release) {
      if (isNewR2Upload && incomingR2Key) {
        await cleanupR2Object(incomingR2Key, { excludeReleaseId: id });
      }
      return res.status(404).json({ success: false, error: "Release not found" });
    }

    const cleanup = oldKeyToDelete
      ? await cleanupR2Object(oldKeyToDelete, { excludeReleaseId: id })
      : { deleted: false, warning: null };

    recordAdminAudit(
      req,
      "download_release_updated",
      `download_app:${release.app_slug}`,
      {
        version: release.version,
        r2Key: release.r2_key || null,
        replacedR2Key: oldKeyToDelete || null,
      }
    );
    res.json({
      success: true,
      release,
      ...(cleanup.warning ? { r2Warning: cleanup.warning } : {}),
    });
  } catch (err) {
    if (isUniqueViolation(err)) {
      return res
        .status(409)
        .json({ success: false, error: "That version already exists for this app" });
    }
    sendDbError(res, err);
  }
});

// DELETE /api/downloads/releases/:id - Delete a release
router.delete("/api/downloads/releases/:id", async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ success: false, error: "Invalid release id" });
  }

  try {
    await db.connectDB();
    const deleted = await db.deleteDownloadRelease(id);
    if (!deleted) {
      return res.status(404).json({ success: false, error: "Release not found" });
    }

    const cleanup = deleted.r2_key
      ? await cleanupR2Object(deleted.r2_key)
      : { deleted: false, warning: null };

    recordAdminAudit(
      req,
      "download_release_deleted",
      `download_app:${deleted.app_slug}`,
      {
        releaseId: id,
        version: deleted.version || null,
        r2Key: deleted.r2_key || null,
        r2Deleted: cleanup.deleted,
      }
    );
    res.json({
      success: true,
      r2Deleted: cleanup.deleted,
      ...(cleanup.warning ? { r2Warning: cleanup.warning } : {}),
    });
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
