const admin = require("firebase-admin");
const { verifyToken } = require("../middleware/auth");
const { addSseClient, cleanupSseClient } = require("../lib/broadcast");

async function sseEvents(req, res) {
  let token = "";
  const authHeader = req.headers.authorization || "";
  if (authHeader.startsWith("Bearer ")) {
    token = authHeader.substring(7);
  } else if (req.query.token) {
    token = String(req.query.token);
  }

  if (!token) {
    return res.status(401).json({ error: "Authentication required" });
  }

  let user;
  try {
    user = await verifyToken(token);
    if (!user) throw new Error("Invalid token");
  } catch (err) {
    return res.status(401).json({ error: "Invalid token" });
  }

  const ownerId = user.uid;

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

module.exports = { sseEvents };
