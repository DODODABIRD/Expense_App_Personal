const express = require("express");
const path = require("path");
const admin = require("firebase-admin");
const cors = require("cors");
const { requireAuth } = require("./middleware/auth");
const { createRateLimiter, byIp, byUser } = require("./lib/rateLimit");
const db = require("./db");
const PORTFOLIO_SEED = require("../content/portfolio.json");
const RAG_KNOWLEDGE_SEED = require("../public/asset/rag_knowledge.json");

// Simple cookie parser middleware
function cookieParser() {
  return (req, res, next) => {
    const cookieHeader = req.headers.cookie || "";
    req.cookies = {};
    cookieHeader.split(";").forEach((cookie) => {
      const [name, ...rest] = cookie.trim().split("=");
      if (name) {
        req.cookies[name] = rest.join("=");
      }
    });
    next();
  };
}

// Attempt to load local environment variables if available
try {
  const dotenv = require("dotenv");
  dotenv.config({ path: path.join(__dirname, "../.env.local") });
  dotenv.config();
} catch (e) {}

// Initialize Firebase Admin EARLY (before route imports) so it's available for admin login
function parseFirebaseServiceAccount(raw) {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (err) {
    try {
      const fixed = raw.replace(/"private_key":\s*"([^"]*)"/s, (match, keyContent) => {
        return '"private_key": "' + keyContent.replace(/\r/g, '').replace(/\n/g, '\\n') + '"';
      });
      return JSON.parse(fixed);
    } catch (err2) {
      const sanitized = raw.replace(/[\u0000-\u001F]+/g, (match) => {
        return match === '\n' ? '\\n' : match === '\r' ? '' : ' ';
      });
      return JSON.parse(sanitized);
    }
  }
}

if (!admin.apps.length) {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    try {
      const serviceAccount = parseFirebaseServiceAccount(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
      if (serviceAccount) {
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
        });
        console.log("Firebase Admin initialized successfully");
      }
    } catch (err) {
      console.error("Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON:", err.message);
    }
  } else {
    console.warn("Notice: FIREBASE_SERVICE_ACCOUNT_JSON is not configured.");
  }
}

// Import Groq config
const groqModel = process.env.GROQ_MODEL || "";
const groqNotificationModel = process.env.GROQ_NOTIFICATION_MODEL || groqModel;

// Import routes (after Firebase init)
const expensesRoutes = require("./routes/expenses");
const notificationsRoutes = require("./routes/notifications");
const parsingRoutes = require("./routes/parsing");
const receiptsRoutes = require("./routes/receipts");
const exchangeRoutes = require("./routes/exchange");
const eventsRoutes = require("./routes/events");
const adminRoutes = require("./routes/admin");
const { router: adminLoginRouter } = require("./routes/adminLogin");
const syncRoutes = require("./routes/sync");

// Browser origins allowed to call the API cross-origin. The website and the
// web app are same-origin and the Flutter app sends no Origin, so the
// default (empty) list blocks only third-party pages.
const CORS_ORIGINS = (process.env.CORS_ORIGINS || "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

function securityHeaders(req, res, next) {
  res.set("X-Content-Type-Options", "nosniff");
  res.set("X-Frame-Options", "SAMEORIGIN");
  res.set("Referrer-Policy", "strict-origin-when-cross-origin");
  if (req.secure) {
    res.set("Strict-Transport-Security", "max-age=15552000");
  }
  next();
}

function createApp() {
  const app = express();

  // Caddy proxies from the host into the Docker network, so the peer is a
  // loopback or private address. Trusting those hops makes req.ip the real
  // client (rate limits, audit log) and req.secure reflect HTTPS.
  app.set("trust proxy", "loopback, uniquelocal");
  app.disable("x-powered-by");
  app.use(securityHeaders);

  // Only base64 receipt images need a large JSON body.
  const smallJson = express.json({ limit: "1mb" });
  const receiptJson = express.json({ limit: "8mb" });
  app.use((req, res, next) =>
    req.path === "/api/parse-receipt"
      ? receiptJson(req, res, next)
      : smallJson(req, res, next)
  );
  app.use(express.urlencoded({ extended: true, limit: "1mb" }));
  app.use(cors({ origin: CORS_ORIGINS }));
  app.use(cookieParser());

  const ragLimit = createRateLimiter({
    windowMs: 15 * 60 * 1000,
    max: 30,
    keyFn: byIp,
    message: "Too many chat requests. Try again later.",
  });
  const notificationParseLimit = createRateLimiter({
    windowMs: 15 * 60 * 1000,
    max: 120,
    keyFn: byUser,
    message: "Too many notification parse requests. Try again later.",
  });
  const receiptParseLimit = createRateLimiter({
    windowMs: 15 * 60 * 1000,
    max: 20,
    keyFn: byUser,
    message: "Too many receipt scans. Try again later.",
  });

  // Serve static frontend assets locally and match vercel.json routes
  const publicDir = path.join(__dirname, "../public");
  app.use(express.static(publicDir));

  app.get("/expenses", (req, res) => {
    res.sendFile(path.join(publicDir, "projects/unmurce/app.html"));
  });
  app.get("/projects/unmurce", (req, res) => {
    res.sendFile(path.join(publicDir, "projects/unmurce/unmurce.html"));
  });
  app.get("/projects/docs", (req, res) => {
    res.sendFile(path.join(publicDir, "projects/unmurce/docs.html"));
  });
  app.get("/downloads", (req, res) => {
    res.sendFile(path.join(publicDir, "downloads.html"));
  });
  app.get("/downloads/:slug", (req, res) => {
    res.sendFile(path.join(publicDir, "downloads.html"));
  });

  // Public config endpoint
  app.get("/api/public-config", (_req, res) => {
    res.set("Cache-Control", "no-store, max-age=0");
    res.json({
      GROQ_MODEL: groqModel || null,
      GROQ_NOTIFICATION_MODEL: groqNotificationModel || null,
    });
  });

  // Public portfolio content used by portfolio-cms.js
  app.get("/api/portfolio", async (_req, res) => {
    res.set("Cache-Control", "no-store, max-age=0");
    try {
      await db.connectDB();
      res.json({ success: true, content: await db.getPortfolioContent() });
    } catch (err) {
      res.json({ success: true, content: PORTFOLIO_SEED, source: "file" });
    }
  });

  // Public app download catalog (latest release per app)
  app.get("/api/downloads", async (_req, res) => {
    res.set("Cache-Control", "no-store, max-age=0");
    try {
      await db.connectDB();
      res.json({ success: true, apps: await db.listDownloadApps() });
    } catch (err) {
      console.error("GET /api/downloads failed:", err);
      res.status(500).json({ success: false, error: "Could not load downloads" });
    }
  });

  app.get("/api/downloads/:slug", async (req, res) => {
    res.set("Cache-Control", "no-store, max-age=0");
    try {
      await db.connectDB();
      const app = await db.getDownloadApp(String(req.params.slug || ""));
      if (!app) {
        return res.status(404).json({ success: false, error: "App not found" });
      }
      res.json({ success: true, app });
    } catch (err) {
      console.error("GET /api/downloads/:slug failed:", err);
      res.status(500).json({ success: false, error: "Could not load this app" });
    }
  });

  // Public RAG knowledge used by the client-side fallback bot
  app.get("/api/rag-knowledge", async (_req, res) => {
    res.set("Cache-Control", "no-store, max-age=0");
    try {
      await db.connectDB();
      res.json({ success: true, knowledge: await db.getRagKnowledge() });
    } catch (err) {
      res.json({ success: true, knowledge: RAG_KNOWLEDGE_SEED, source: "file" });
    }
  });

  // RAG Chat route
  app.post("/api/rag-chat", ragLimit, parsingRoutes.ragChat);
  app.post("/api/rag-feedback", ragLimit, parsingRoutes.ragFeedback);

  // Device sync heartbeat
  app.post("/api/sync/beat", requireAuth, syncRoutes.deviceSyncBeat);

  // Notification reference routes
  app.get("/api/ai-notification-reference", requireAuth, notificationsRoutes.getNotificationReference);
  app.put("/api/ai-notification-reference", requireAuth, notificationsRoutes.putNotificationReference);
  app.post("/api/ai-notification-reference/refresh", requireAuth, notificationsRoutes.refreshNotificationRef);

  // Parse notification route
  app.post("/api/parse-notification", requireAuth, notificationParseLimit, parsingRoutes.parseNotification);

  // Parse receipt route (streaming)
  app.post("/api/parse-receipt", requireAuth, receiptParseLimit, receiptsRoutes.parseReceiptRoute);

  // Exchange rates
  app.get("/api/exchange-rates", exchangeRoutes.exchangeRates);

  // Expense CRUD routes
  app.post("/api/users", requireAuth, expensesRoutes.createExpense);
  app.post("/api/users/bulk", requireAuth, expensesRoutes.bulkUpsertExpenses);
  app.get("/api/users", requireAuth, expensesRoutes.listAllExpenses);
  app.get("/api/users/:localId", requireAuth, expensesRoutes.getExpense);
  app.put("/api/users/:localId", requireAuth, expensesRoutes.updateExpense);
  app.delete("/api/users/:localId", requireAuth, expensesRoutes.removeExpense);
  app.post("/api/users/delete-all", requireAuth, expensesRoutes.deleteAllUserExpenses);

  // SSE Events route. EventSource cannot send headers, so the browser first
  // trades its ID token for a short-lived ticket and puts that in the URL.
  app.post("/api/events/ticket", requireAuth, eventsRoutes.createSseTicket);
  app.get("/api/events", eventsRoutes.sseEvents);

  // Admin login routes (public) - MUST come before admin routes
  app.use("/dodo", adminLoginRouter);

  // Admin panel routes (session protected)
  app.use("/dodo", adminRoutes);

  // JSON instead of Express's HTML error page (e.g. malformed JSON bodies);
  // internal details are logged, never sent.
  app.use((err, req, res, next) => {
    if (res.headersSent) return next(err);
    const status = err.status || err.statusCode || 500;
    if (status >= 500) console.error(`${req.method} ${req.path} failed:`, err);
    res.status(status).json({
      error: err.expose ? err.message : "Internal server error",
    });
  });

  return app;
}

module.exports = { createApp };
