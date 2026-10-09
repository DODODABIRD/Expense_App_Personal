const express = require("express");
const path = require("path");
const admin = require("firebase-admin");
const cors = require("cors");

// Attempt to load local environment variables if available
try {
  const dotenv = require("dotenv");
  dotenv.config({ path: path.join(__dirname, "../.env.local") });
  dotenv.config();
} catch (e) {}

// Import routes
const expensesRoutes = require("./routes/expenses");
const notificationsRoutes = require("./routes/notifications");
const parsingRoutes = require("./routes/parsing");
const receiptsRoutes = require("./routes/receipts");
const exchangeRoutes = require("./routes/exchange");
const eventsRoutes = require("./routes/events");

// Import Groq config
const groqModel = process.env.GROQ_MODEL || "";
const groqNotificationModel = process.env.GROQ_NOTIFICATION_MODEL || groqModel;

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

function createApp() {
  const app = express();

  // Base64 receipt images can exceed Express defaults; allow larger JSON payloads.
  app.use(express.json({ limit: "8mb" }));
  app.use(express.urlencoded({ extended: true, limit: "8mb" }));
  app.use(cors());

  // Initialize Firebase Admin if not already initialized
  if (!admin.apps.length) {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      try {
        const serviceAccount = parseFirebaseServiceAccount(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
        if (serviceAccount) {
          admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
          });
        }
      } catch (err) {
        console.error("Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON:", err.message);
      }
    } else {
      console.warn("Notice: FIREBASE_SERVICE_ACCOUNT_JSON is not configured in local environment.");
    }
  }

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
  app.put("/api/ai-notification-reference", notificationsRoutes.putNotificationReference);
  app.post("/api/ai-notification-reference/refresh", notificationsRoutes.refreshNotificationRef);

  // Parse notification route
  app.post("/api/parse-notification", parsingRoutes.parseNotification);

  // Parse receipt route (streaming)
  app.post("/api/parse-receipt", receiptsRoutes.parseReceiptRoute);

  // Exchange rates
  app.get("/api/exchange-rates", exchangeRoutes.exchangeRates);

  // Expense CRUD routes
  app.post("/api/users", expensesRoutes.createExpense);
  app.get("/api/users", expensesRoutes.listAllExpenses);
  app.get("/api/users/:id", expensesRoutes.getExpense);
  app.put("/api/users/:id", expensesRoutes.updateExpense);
  app.delete("/api/users/:id", expensesRoutes.removeExpense);
  app.post("/api/users/delete-all", expensesRoutes.deleteAllUserExpenses);
  app.get("/api/users/local/:localId", expensesRoutes.getExpenseByLocal);

  // SSE Events route
  app.get("/api/events", eventsRoutes.sseEvents);

  return app;
}

module.exports = { createApp };
