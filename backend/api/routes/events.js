const crypto = require("crypto");
const admin = require("firebase-admin");
const { verifyToken } = require("../middleware/auth");
const { addSseClient, cleanupSseClient } = require("../lib/broadcast");

// Single-use tickets so the Firebase ID token never appears in a URL
// (proxy access logs record query strings).
const SSE_TICKET_TTL_MS = 60 * 1000;
const sseTickets = new Map();

function pruneSseTickets() {
  const now = Date.now();
  for (const [ticket, entry] of sseTickets) {
    if (now > entry.expiresAt) sseTickets.delete(ticket);
  }
}

/**
 * POST /api/events/ticket (requireAuth) → { ticket, expiresInMs }
 */
function createSseTicket(req, res) {
  pruneSseTickets();
  const ticket = crypto.randomBytes(32).toString("hex");
  sseTickets.set(ticket, {
    uid: req.user.uid,
    expiresAt: Date.now() + SSE_TICKET_TTL_MS,
  });
  res.set("Cache-Control", "no-store");
  res.json({ ticket, expiresInMs: SSE_TICKET_TTL_MS });
}

function redeemSseTicket(ticket) {
  const entry = sseTickets.get(ticket);
  if (!entry) return null;
  sseTickets.delete(ticket);
  return Date.now() > entry.expiresAt ? null : entry.uid;
}

async function sseEvents(req, res) {
  let ownerId = null;
  const authHeader = req.headers.authorization || "";
  if (authHeader.startsWith("Bearer ")) {
    const user = await verifyToken(authHeader.substring(7));
    ownerId = user?.uid || null;
  } else if (req.query.ticket) {
    ownerId = redeemSseTicket(String(req.query.ticket));
  } else {
    return res.status(401).json({ error: "Authentication required" });
  }

  if (!ownerId) {
    return res.status(401).json({ error: "Invalid or expired credentials" });
  }

  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache, no-transform",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no"
  });

  res.write(`data: ${JSON.stringify({ type: "connected", transport: "sse", ownerId })}\n\n`);

  addSseClient(ownerId, res);

  const keepAlive = setInterval(() => {
    try {
      res.write(": ping\n\n");
    } catch (e) {}
  }, 20000);

  req.on("close", () => {
    clearInterval(keepAlive);
    cleanupSseClient(res);
  });
}

module.exports = { sseEvents, createSseTicket };
