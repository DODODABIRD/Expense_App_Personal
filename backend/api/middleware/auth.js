const admin = require("firebase-admin");

async function requireAuth(req, res, next) {
  try {
    if (!admin.apps.length) {
      return res.status(503).json({ error: "Firebase Admin is not configured on this server" });
    }
    const header = req.headers.authorization || "";
    if (!header.startsWith("Bearer ")) {
      return res.status(401).json({ error: "Authentication required" });
    }
    req.user = await admin.auth().verifyIdToken(header.substring(7));
    next();
  } catch (err) {
    res.status(401).json({ error: "Invalid or expired token" });
  }
}

async function verifyToken(token) {
  if (!admin.apps.length) return null;
  try {
    return await admin.auth().verifyIdToken(token);
  } catch (e) {
    return null;
  }
}

module.exports = { requireAuth, verifyToken };
