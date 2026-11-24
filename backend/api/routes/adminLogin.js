const express = require("express");
const crypto = require("crypto");
const path = require("path");
const db = require("../db");

const router = express.Router();

const ADMIN_UI_DIR = path.resolve(__dirname, "../../admin-ui");

// Admin credentials from environment
const ADMIN_SECRET = process.env.ADMIN_SECRET || "";
const ADMIN_FIREBASE_UIDS = (process.env.ADMIN_FIREBASE_UIDS || "")
  .split(",")
  .map((uid) => uid.trim())
  .filter(Boolean);

// Simple session store (in-memory; survives only as long as the process does)
const sessions = new Map();
const SESSION_DURATION = 24 * 60 * 60 * 1000; // 24 hours

// Login throttling: count attempts per IP inside a rolling window.
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const LOGIN_MAX_ATTEMPTS = 10;
const loginAttempts = new Map();

function generateSessionId() {
  return crypto.randomBytes(32).toString("hex");
}

function createSession(uid) {
  const sessionId = generateSessionId();
  sessions.set(sessionId, {
    uid,
    createdAt: Date.now(),
    expiresAt: Date.now() + SESSION_DURATION,
  });
  return sessionId;
}

function validateSession(sessionId) {
  if (!sessionId) return null;
  const session = sessions.get(sessionId);
  if (!session) return null;
  if (Date.now() > session.expiresAt) {
    sessions.delete(sessionId);
    return null;
  }
  return session;
}

function pruneExpiredSessions() {
  const now = Date.now();
  for (const [id, session] of sessions) {
    if (now > session.expiresAt) sessions.delete(id);
  }
  for (const [ip, entry] of loginAttempts) {
    if (now > entry.resetAt) loginAttempts.delete(ip);
  }
}

const sessionPruner = setInterval(pruneExpiredSessions, 60 * 60 * 1000);
if (typeof sessionPruner.unref === "function") sessionPruner.unref();

function clientIp(req) {
  return req.ip || req.socket?.remoteAddress || "unknown";
}

function isRateLimited(ip) {
  const entry = loginAttempts.get(ip);
  if (!entry) return false;
  if (Date.now() > entry.resetAt) {
    loginAttempts.delete(ip);
    return false;
  }
  return entry.count >= LOGIN_MAX_ATTEMPTS;
}

function registerFailedAttempt(ip) {
  const now = Date.now();
  const entry = loginAttempts.get(ip);
  if (!entry || now > entry.resetAt) {
    loginAttempts.set(ip, { count: 1, resetAt: now + LOGIN_WINDOW_MS });
    return;
  }
  entry.count += 1;
}

function clearAttempts(ip) {
  loginAttempts.delete(ip);
}

function secretMatches(provided) {
  if (!ADMIN_SECRET) return false;
  const providedHash = crypto
    .createHash("sha256")
    .update(String(provided))
    .digest();
  const expectedHash = crypto
    .createHash("sha256")
    .update(ADMIN_SECRET)
    .digest();
  return crypto.timingSafeEqual(providedHash, expectedHash);
}

function auditLogin(req, action, detail) {
  db.connectDB()
    .then(() =>
      db.insertAdminAudit({
        actor: detail.actor || "anonymous",
        action,
        target: "admin-session",
        detail,
        ip: clientIp(req),
      })
    )
    .catch(() => {});
}

function setSessionCookie(res, sessionId) {
  res.cookie("dodo_session", sessionId, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "strict",
    maxAge: SESSION_DURATION,
    path: "/",
  });
}

// Static UI assets (css/js only) - must be reachable before authentication.
router.use(
  "/static",
  express.static(path.join(ADMIN_UI_DIR, "static"), {
    index: false,
    etag: false,
    maxAge: 0,
  })
);

// Login page
router.get("/login", (req, res, next) => {
  const session = validateSession(req.cookies?.dodo_session);
  if (session) return res.redirect("/dodo");

  res.set("Cache-Control", "no-store, max-age=0");
  res.sendFile(path.join(ADMIN_UI_DIR, "login.html"), (err) => {
    if (err) next(err);
  });
});

// API: Login with secret key
router.post("/api/login-secret", (req, res) => {
  const ip = clientIp(req);

  if (isRateLimited(ip)) {
    return res.status(429).json({
      success: false,
      error: "Too many login attempts. Try again in 15 minutes.",
    });
  }

  if (!ADMIN_SECRET) {
    return res.status(503).json({
      success: false,
      error:
        "ADMIN_SECRET is not configured on this server. Secret login is disabled.",
    });
  }

  const { secret } = req.body || {};
  if (!secret || !secretMatches(secret)) {
    registerFailedAttempt(ip);
    auditLogin(req, "login_failed", { actor: "admin_secret", method: "secret" });
    return res.status(401).json({ success: false, error: "Invalid secret key" });
  }

  clearAttempts(ip);
  const sessionId = createSession("admin_secret");
  setSessionCookie(res, sessionId);
  auditLogin(req, "login_success", { actor: "admin_secret", method: "secret" });
  res.json({ success: true });
});

// API: Login with Firebase token
router.post("/api/login-firebase", async (req, res) => {
  const admin = require("firebase-admin");
  const { token } = req.body || {};
  const ip = clientIp(req);

  if (isRateLimited(ip)) {
    return res.status(429).json({
      success: false,
      error: "Too many login attempts. Try again in 15 minutes.",
    });
  }

  if (!token) {
    return res.status(400).json({ success: false, error: "Token is required" });
  }

  if (!admin.apps.length) {
    return res
      .status(503)
      .json({ success: false, error: "Firebase is not configured" });
  }

  if (ADMIN_FIREBASE_UIDS.length === 0) {
    return res.status(503).json({
      success: false,
      error:
        "ADMIN_FIREBASE_UIDS is not configured. Firebase login is disabled.",
    });
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);

    if (!ADMIN_FIREBASE_UIDS.includes(decoded.uid)) {
      registerFailedAttempt(ip);
      auditLogin(req, "login_failed", {
        actor: decoded.uid,
        method: "firebase",
        reason: "uid_not_allowed",
      });
      return res
        .status(403)
        .json({ success: false, error: "You are not authorized to access this panel" });
    }

    clearAttempts(ip);
    const sessionId = createSession(decoded.uid);
    setSessionCookie(res, sessionId);
    auditLogin(req, "login_success", { actor: decoded.uid, method: "firebase" });
    res.json({ success: true });
  } catch (err) {
    registerFailedAttempt(ip);
    auditLogin(req, "login_failed", { method: "firebase", reason: "invalid_token" });
    res
      .status(401)
      .json({ success: false, error: "Invalid or expired Firebase token" });
  }
});

// API: Logout
router.post("/api/logout", (req, res) => {
  const sessionId = req.cookies?.dodo_session;
  const session = validateSession(sessionId);
  if (sessionId) {
    sessions.delete(sessionId);
  }

  res.clearCookie("dodo_session", { path: "/" });
  if (session) {
    auditLogin(req, "logout", { actor: session.uid });
  }
  res.json({ success: true });
});

// API: Check auth status
router.get("/api/check", (req, res) => {
  const session = validateSession(req.cookies?.dodo_session);
  if (session) {
    res.json({ authenticated: true, uid: session.uid });
  } else {
    res.json({ authenticated: false });
  }
});

module.exports = {
  router,
  sessions,
  validateSession,
  createSession,
  SESSION_DURATION,
};
