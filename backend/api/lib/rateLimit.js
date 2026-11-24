/**
 * Fixed-window, in-memory rate limiter (single process, resets on restart).
 * keyFn(req) picks the bucket, e.g. client IP or Firebase UID.
 */
function createRateLimiter({ windowMs, max, keyFn, message }) {
  const hits = new Map();

  const pruner = setInterval(() => {
    const now = Date.now();
    for (const [key, entry] of hits) {
      if (now > entry.resetAt) hits.delete(key);
    }
  }, windowMs);
  if (typeof pruner.unref === "function") pruner.unref();

  return function rateLimit(req, res, next) {
    const key = keyFn(req);
    const now = Date.now();
    let entry = hits.get(key);
    if (!entry || now > entry.resetAt) {
      entry = { count: 0, resetAt: now + windowMs };
      hits.set(key, entry);
    }
    entry.count += 1;
    if (entry.count > max) {
      res.set("Retry-After", String(Math.ceil((entry.resetAt - now) / 1000)));
      return res.status(429).json({ error: message });
    }
    next();
  };
}

const byIp = (req) => req.ip || req.socket?.remoteAddress || "unknown";
const byUser = (req) => req.user?.uid || byIp(req);

module.exports = { createRateLimiter, byIp, byUser };
