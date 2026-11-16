const express = require("express");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { execFileSync } = require("child_process");
const admin = require("firebase-admin");
const { validateSession } = require("./adminLogin");
const adminDataRouter = require("./adminData");
const db = require("../db");

const router = express.Router();

const ADMIN_UI_DIR = path.resolve(__dirname, "../../admin-ui");
const ASSET_ROOT = path.resolve(
  process.env.ADMIN_ASSET_ROOT || path.join(__dirname, "../../public/asset")
);
const BACKUP_ROOT = path.resolve(
  process.env.ADMIN_BACKUP_ROOT || path.join(__dirname, "../../data/admin-backups")
);
const MAX_UPLOAD_BYTES = 40 * 1024 * 1024;
const BACKUP_LIMIT = 5;
const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".ico"]);
const REPLACEABLE_EXTENSIONS = new Set([...IMAGE_EXTENSIONS, ".apk", ".json", ".md"]);
const BACKUP_ID_PATTERN = /^[A-Za-z0-9._-]+$/;

// Session authentication middleware
function requireSession(req, res, next) {
  const sessionId = req.cookies?.dodo_session;
  const session = validateSession(sessionId);

  if (!session) {
    if (req.path.startsWith("/api/")) {
      return res.status(401).json({ error: "Not authenticated", redirect: "/dodo/login" });
    }
    return res.redirect("/dodo/login");
  }

  req.adminSession = session;
  next();
}

router.use(requireSession);
router.use(adminDataRouter);

function recordAudit(req, action, target, detail) {
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

function listAssets(dir = ASSET_ROOT, prefix = "") {
  const assets = [];

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;

    const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
    const fullPath = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      assets.push(...listAssets(fullPath, relativePath));
      continue;
    }

    if (!entry.isFile()) continue;

    const stat = fs.statSync(fullPath);
    const ext = path.extname(entry.name).toLowerCase();

    assets.push({
      path: relativePath,
      name: entry.name,
      ext,
      size: stat.size,
      modifiedAt: stat.mtime.toISOString(),
      version: stat.mtimeMs,
      url: "/asset/" + relativePath.split("/").map(encodeURIComponent).join("/"),
      preview: IMAGE_EXTENSIONS.has(ext),
      replaceable: REPLACEABLE_EXTENSIONS.has(ext),
    });
  }

  return assets;
}

function resolveWithin(root, relativePath) {
  if (typeof relativePath !== "string" || !relativePath || relativePath.includes("\0")) {
    return null;
  }

  const resolved = path.resolve(root, relativePath.replace(/\\/g, "/"));
  const rootPrefix = root.endsWith(path.sep) ? root : root + path.sep;

  if (!resolved.startsWith(rootPrefix)) return null;
  return resolved;
}

function resolveAssetPath(relativePath) {
  return resolveWithin(ASSET_ROOT, relativePath);
}

function extensionOf(relativePath) {
  return path.extname(String(relativePath)).toLowerCase();
}

function hasHiddenSegment(relativePath) {
  return String(relativePath)
    .split("/")
    .some((segment) => segment.startsWith("."));
}

function backupDir(relativePath) {
  return resolveWithin(BACKUP_ROOT, relativePath);
}

function createBackup(relativePath, absolutePath) {
  if (!fs.existsSync(absolutePath)) return null;

  const dir = backupDir(relativePath);
  if (!dir) return null;

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupId = `${stamp}-${crypto.randomBytes(3).toString("hex")}`;
  const target = path.join(dir, backupId);

  fs.mkdirSync(dir, { recursive: true });
  fs.copyFileSync(absolutePath, target);
  pruneBackups(relativePath);

  return {
    id: backupId,
    path: relativePath,
    size: fs.statSync(target).size,
    createdAt: fs.statSync(target).mtime.toISOString(),
  };
}

function listBackups(relativePath) {
  const dir = backupDir(relativePath);
  if (!dir || !fs.existsSync(dir)) return [];

  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && BACKUP_ID_PATTERN.test(entry.name))
    .map((entry) => entry.name)
    .sort()
    .reverse() // newest first (names start with an ISO timestamp)
    .map((backupId) => {
      const fullPath = path.join(dir, backupId);
      const stat = fs.statSync(fullPath);
      return {
        id: backupId,
        path: relativePath,
        size: stat.size,
        createdAt: stat.mtime.toISOString(),
      };
    });
}

function pruneBackups(relativePath) {
  const dir = backupDir(relativePath);
  if (!dir) return;

  const backups = listBackups(relativePath);
  const keep = new Set(backups.slice(0, BACKUP_LIMIT).map((backup) => backup.id));

  for (const backup of backups) {
    if (keep.has(backup.id)) continue;
    fs.rmSync(path.join(dir, backup.id), { force: true });
  }
}

// GET /dodo - Admin panel page
router.get("/", (req, res, next) => {
  res.set("Cache-Control", "no-store, max-age=0");
  res.sendFile(path.join(ADMIN_UI_DIR, "panel.html"), (err) => {
    if (err) next(err);
  });
});

// GET /api/assets - List assets under public/asset
router.get("/api/assets", (req, res) => {
  try {
    res.json({ success: true, assets: listAssets() });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// POST /api/assets/replace?file=relative/path - Overwrite an existing asset
router.post(
  "/api/assets/replace",
  express.raw({ type: () => true, limit: MAX_UPLOAD_BYTES }),
  (req, res) => {
    const relativePath = req.query.file;
    const targetPath = resolveAssetPath(relativePath);

    if (!targetPath) {
      return res.status(400).json({ success: false, error: "Invalid asset path" });
    }

    let stat;
    try {
      stat = fs.statSync(targetPath);
    } catch (e) {
      return res.status(404).json({ success: false, error: "Asset not found" });
    }

    if (!stat.isFile()) {
      return res.status(400).json({ success: false, error: "Path is not a file" });
    }

    const ext = extensionOf(relativePath);
    if (!REPLACEABLE_EXTENSIONS.has(ext)) {
      return res.status(400).json({
        success: false,
        error: `Files with extension "${ext}" cannot be replaced`,
      });
    }

    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      return res.status(400).json({ success: false, error: "Uploaded file is empty" });
    }

    try {
      const backup = createBackup(relativePath, targetPath);
      fs.writeFileSync(targetPath, req.body);
      recordAudit(req, "asset_replaced", relativePath, {
        size: req.body.length,
        backup: backup?.id || null,
      });
      res.json({
        success: true,
        path: relativePath,
        size: req.body.length,
        backup: backup?.id || null,
      });
    } catch (e) {
      res.status(500).json({ success: false, error: e.message });
    }
  }
);

// POST /api/assets/upload?file=relative/path - Create a new asset
router.post(
  "/api/assets/upload",
  express.raw({ type: () => true, limit: MAX_UPLOAD_BYTES }),
  (req, res) => {
    const relativePath = String(req.query.file || "").replace(/\\/g, "/");
    const targetPath = resolveAssetPath(relativePath);

    if (!targetPath) {
      return res.status(400).json({ success: false, error: "Invalid asset path" });
    }

    if (hasHiddenSegment(relativePath)) {
      return res
        .status(400)
        .json({ success: false, error: "Hidden paths are not allowed" });
    }

    const ext = extensionOf(relativePath);
    if (!REPLACEABLE_EXTENSIONS.has(ext)) {
      return res.status(400).json({
        success: false,
        error: `Files with extension "${ext}" cannot be uploaded`,
      });
    }

    if (fs.existsSync(targetPath)) {
      return res.status(409).json({
        success: false,
        error: "File already exists. Use replace instead.",
      });
    }

    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      return res.status(400).json({ success: false, error: "Uploaded file is empty" });
    }

    try {
      fs.mkdirSync(path.dirname(targetPath), { recursive: true });
      fs.writeFileSync(targetPath, req.body);
      recordAudit(req, "asset_uploaded", relativePath, { size: req.body.length });
      res.json({ success: true, path: relativePath, size: req.body.length });
    } catch (e) {
      res.status(500).json({ success: false, error: e.message });
    }
  }
);

// DELETE /api/assets?file=relative/path - Delete an asset (keeps a backup)
router.delete("/api/assets", (req, res) => {
  const relativePath = String(req.query.file || "").replace(/\\/g, "/");
  const targetPath = resolveAssetPath(relativePath);

  if (!targetPath) {
    return res.status(400).json({ success: false, error: "Invalid asset path" });
  }

  let stat;
  try {
    stat = fs.statSync(targetPath);
  } catch (e) {
    return res.status(404).json({ success: false, error: "Asset not found" });
  }

  if (!stat.isFile()) {
    return res.status(400).json({ success: false, error: "Path is not a file" });
  }

  try {
    const backup = createBackup(relativePath, targetPath);
    fs.unlinkSync(targetPath);
    recordAudit(req, "asset_deleted", relativePath, { backup: backup?.id || null });
    res.json({ success: true, path: relativePath, backup: backup?.id || null });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// GET /api/assets/backups?file=relative/path - List backups for an asset
router.get("/api/assets/backups", (req, res) => {
  const relativePath = String(req.query.file || "").replace(/\\/g, "/");
  if (!resolveAssetPath(relativePath)) {
    return res.status(400).json({ success: false, error: "Invalid asset path" });
  }

  try {
    res.json({ success: true, backups: listBackups(relativePath) });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// POST /api/assets/restore - Restore an asset from a backup
router.post("/api/assets/restore", (req, res) => {
  const relativePath = String(req.body?.file || "").replace(/\\/g, "/");
  const backupId = String(req.body?.backup || "");
  const targetPath = resolveAssetPath(relativePath);

  if (!targetPath) {
    return res.status(400).json({ success: false, error: "Invalid asset path" });
  }

  if (!REPLACEABLE_EXTENSIONS.has(extensionOf(relativePath))) {
    return res.status(400).json({
      success: false,
      error: `Files with extension "${extensionOf(relativePath)}" cannot be restored`,
    });
  }

  if (!BACKUP_ID_PATTERN.test(backupId)) {
    return res.status(400).json({ success: false, error: "Invalid backup id" });
  }

  const backupPath = resolveWithin(BACKUP_ROOT, `${relativePath}/${backupId}`);
  if (!backupPath || !fs.existsSync(backupPath) || !fs.statSync(backupPath).isFile()) {
    return res.status(404).json({ success: false, error: "Backup not found" });
  }

  try {
    // Read first: creating the pre-restore backup can prune the selected one.
    const restored = fs.readFileSync(backupPath);
    const currentBackup = createBackup(relativePath, targetPath);
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.writeFileSync(targetPath, restored);
    recordAudit(req, "asset_restored", relativePath, {
      backup: backupId,
      replacedWith: currentBackup?.id || null,
    });
    res.json({ success: true, path: relativePath, size: fs.statSync(targetPath).size });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

const HEALTH_ENV_KEYS = [
  "DATABASE_URL",
  "FIREBASE_SERVICE_ACCOUNT_JSON",
  "ADMIN_SECRET",
  "ADMIN_FIREBASE_UIDS",
  "GROQ_API_KEY",
  "GROQ_MODEL",
  "GROQ_NOTIFICATION_MODEL",
  "AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT",
  "AZURE_DOCUMENT_INTELLIGENCE_KEY",
  "OPENROUTER_API_KEY",
  "MONGODB_URI",
];

function directoryStats(root) {
  const stats = { files: 0, totalBytes: 0, latestAt: null };

  function walk(dir) {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
      return;
    }

    for (const entry of entries) {
      if (entry.name.startsWith(".")) continue;
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
        continue;
      }
      if (!entry.isFile()) continue;

      try {
        const stat = fs.statSync(fullPath);
        stats.files += 1;
        stats.totalBytes += stat.size;
        if (!stats.latestAt || stat.mtime > stats.latestAt) {
          stats.latestAt = stat.mtime;
        }
      } catch (e) {}
    }
  }

  walk(root);
  return stats;
}

function gitValue(args) {
  try {
    return execFileSync("git", args, {
      cwd: path.join(__dirname, "../.."),
      encoding: "utf8",
      timeout: 1500,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch (e) {
    return null;
  }
}

function runtimeCommit() {
  const commit =
    process.env.VERCEL_GIT_COMMIT_SHA ||
    process.env.GIT_COMMIT ||
    process.env.SOURCE_COMMIT ||
    gitValue(["rev-parse", "HEAD"]);
  const branch =
    process.env.VERCEL_GIT_COMMIT_REF ||
    gitValue(["rev-parse", "--abbrev-ref", "HEAD"]);
  const status = gitValue(["status", "--porcelain"]);

  return {
    commit: commit || null,
    shortCommit: commit ? commit.slice(0, 7) : null,
    branch: branch || null,
    message: gitValue(["log", "-1", "--pretty=%s"]),
    dirty: status === null ? null : status.length > 0,
  };
}

// GET /api/health - Database, Firebase, env, backups and runtime commit
router.get("/api/health", async (req, res) => {
  const database = { ok: false, latencyMs: null, error: null };
  try {
    await db.connectDB();
    const started = Date.now();
    await db.getPool().query("SELECT 1 AS ok");
    database.ok = true;
    database.latencyMs = Date.now() - started;
  } catch (e) {
    database.error = e.message;
  }

  let firebase = { initialized: false, projectId: null };
  try {
    if (admin.apps.length > 0) {
      firebase = {
        initialized: true,
        projectId: admin.app().options?.projectId || null,
      };
    }
  } catch (e) {}

  const backups = directoryStats(BACKUP_ROOT);
  const env = HEALTH_ENV_KEYS.map((key) => ({
    key,
    configured: Boolean(String(process.env[key] || "").trim()),
  }));

  res.set("Cache-Control", "no-store, max-age=0");
  res.json({
    success: true,
    health: {
      database,
      firebase,
      env,
      missingEnv: env.filter((item) => !item.configured).map((item) => item.key),
      backups: {
        count: backups.files,
        totalBytes: backups.totalBytes,
        latestAt: backups.latestAt,
      },
      runtime: {
        ...runtimeCommit(),
        nodeVersion: process.version,
        uptimeSeconds: Math.round(process.uptime()),
        memoryRssBytes: process.memoryUsage().rss,
        pid: process.pid,
        nodeEnv: process.env.NODE_ENV || "development",
      },
    },
  });
});

router.use((err, req, res, next) => {
  if (err && err.type === "entity.too.large") {
    return res.status(413).json({ success: false, error: "File is too large (max 40 MB)" });
  }
  next(err);
});

module.exports = router;
