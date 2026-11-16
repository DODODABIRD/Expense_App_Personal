const express = require("express");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
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

function backupDirNames() {
  if (!fs.existsSync(BACKUP_ROOT)) return [];
  return fs
    .readdirSync(BACKUP_ROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => entry.name)
    .sort()
    .reverse(); // newest first (names start with an ISO timestamp)
}

function backupFilePath(backupId, relativePath) {
  const segments = relativePath.split("/");
  return path.join(BACKUP_ROOT, backupId, ...segments);
}

function createBackup(relativePath, absolutePath) {
  if (!fs.existsSync(absolutePath)) return null;

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupId = `${stamp}-${crypto.randomBytes(3).toString("hex")}`;
  const target = backupFilePath(backupId, relativePath);

  fs.mkdirSync(path.dirname(target), { recursive: true });
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
  return backupDirNames()
    .map((backupId) => ({ backupId, fullPath: backupFilePath(backupId, relativePath) }))
    .filter(({ fullPath }) => fs.existsSync(fullPath) && fs.statSync(fullPath).isFile())
    .map(({ backupId, fullPath }) => {
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
  const keep = listBackups(relativePath).slice(0, BACKUP_LIMIT);
  const keepIds = new Set(keep.map((backup) => backup.id));
  for (const backupId of backupDirNames()) {
    const fullPath = backupFilePath(backupId, relativePath);
    if (!fs.existsSync(fullPath)) continue;
    if (keepIds.has(backupId)) continue;
    fs.rmSync(path.join(BACKUP_ROOT, backupId), { recursive: true, force: true });
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

  const backupPath = resolveWithin(BACKUP_ROOT, `${backupId}/${relativePath}`);
  if (!backupPath || !fs.existsSync(backupPath) || !fs.statSync(backupPath).isFile()) {
    return res.status(404).json({ success: false, error: "Backup not found" });
  }

  try {
    const currentBackup = createBackup(relativePath, targetPath);
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.copyFileSync(backupPath, targetPath);
    recordAudit(req, "asset_restored", relativePath, {
      backup: backupId,
      replacedWith: currentBackup?.id || null,
    });
    res.json({ success: true, path: relativePath, size: fs.statSync(targetPath).size });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

router.use((err, req, res, next) => {
  if (err && err.type === "entity.too.large") {
    return res.status(413).json({ success: false, error: "File is too large (max 40 MB)" });
  }
  next(err);
});

module.exports = router;
