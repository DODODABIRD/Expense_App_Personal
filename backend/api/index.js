const express = require("express");
const path = require("path");
const admin = require("firebase-admin");
const cors = require("cors");
const { requireAuth } = require("./middleware/auth");

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

function createApp() {
  const app = express();

  // Base64 receipt images can exceed Express defaults; allow larger JSON payloads.
  app.use(express.json({ limit: "8mb" }));
  app.use(express.urlencoded({ extended: true, limit: "8mb" }));
  app.use(cors());
  app.use(cookieParser());

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

  // Public config endpoint
  app.get("/api/public-config", (_req, res) => {
    res.set("Cache-Control", "no-store, max-age=0");
    res.json({
      GROQ_MODEL: groqModel || null,
      GROQ_NOTIFICATION_MODEL: groqNotificationModel || null,
    });
  });

  // RAG Chat route
  app.post("/api/rag-chat", parsingRoutes.ragChat);

  // Notification reference routes
  app.put("/api/ai-notification-reference", requireAuth, notificationsRoutes.putNotificationReference);
  app.post("/api/ai-notification-reference/refresh", requireAuth, notificationsRoutes.refreshNotificationRef);

  // Parse notification route
  app.post("/api/parse-notification", requireAuth, parsingRoutes.parseNotification);

  // Parse receipt route (streaming)
  app.post("/api/parse-receipt", requireAuth, receiptsRoutes.parseReceiptRoute);

  // Exchange rates
  app.get("/api/exchange-rates", exchangeRoutes.exchangeRates);

  // Expense CRUD routes
  app.post("/api/users", requireAuth, expensesRoutes.createExpense);
  app.get("/api/users", requireAuth, expensesRoutes.listAllExpenses);
  app.get("/api/users/:localId", requireAuth, expensesRoutes.getExpense);
  app.put("/api/users/:localId", requireAuth, expensesRoutes.updateExpense);
  app.delete("/api/users/:localId", requireAuth, expensesRoutes.removeExpense);
  app.post("/api/users/delete-all", requireAuth, expensesRoutes.deleteAllUserExpenses);

  // SSE Events route
  app.get("/api/events", eventsRoutes.sseEvents);

  // Admin login routes (public) - MUST come before admin routes
  app.use("/dodo", adminLoginRouter);

  // Admin panel routes (session protected)
  app.use("/dodo", adminRoutes);

  return app;
}

module.exports = { createApp };
