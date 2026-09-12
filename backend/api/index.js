const express = require("express");
const mongoose = require("mongoose");
const admin = require("firebase-admin");
const cors = require("cors");

const app = express();
// Base64 receipt images can exceed Express defaults; allow larger JSON payloads.
app.use(express.json({ limit: "8mb" }));
app.use(express.urlencoded({ extended: true, limit: "8mb" }));
app.use(cors());

if (!admin.apps.length) {
  if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is missing");
  }

  admin.initializeApp({
    credential: admin.credential.cert(
      JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)
    ),
  });
}

async function requireAuth(req, res, next) {
  try {
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

// ✅ MongoDB connection (cached for Vercel)
let isConnected = false;
let indexesReady = false;

async function connectDB() {
  if (isConnected && indexesReady) return;

  if (!process.env.MONGODB_URI) {
    throw new Error("MONGODB_URI is missing");
  }

  await mongoose.connect(process.env.MONGODB_URI);
  isConnected = true;

  if (!indexesReady) {
    const indexes = await User.collection.indexes();
    for (const index of indexes) {
      const keys = Object.keys(index.key || {});
      if (index.unique && keys.length === 1 && keys[0] === "localId") {
        await User.collection.dropIndex(index.name);
      }
    }
    await User.syncIndexes();
    indexesReady = true;
  }
}

// TODO: 
// Bikin collection nya punya user id 
// Collection nya cuma satu aja supaya bisa di scaling


// User ID String, unique, foreign key
//
// TODO: Make the schema fit the expense schema
const ExpenseSchema = new mongoose.Schema(
  {
    ownerId: { type: String, required: true, index: true },
    localId: { type: String, required: true },
    name: { type: String, required: true },
    amount: { type: Number, required: true },
    category: { type: String, required: true },
    type: { type: String, required: true },
    date: { type: String, required: true },
  },
  {
    timestamps: true,
    collection: "niggas",
  }
);

ExpenseSchema.index({ ownerId: 1, localId: 1 }, { unique: true });
const User = mongoose.models.Expense || mongoose.model("Expense", ExpenseSchema);

const parserApiKey =
  process.env.GEMINI_KEY ||
  process.env.GEMINI_API_KEY ||
  process.env.GOOGLE_STUDIO_API_KEY ||
  process.env.GOOGLE_API_KEY;
const azureDocumentEndpoint = String(
  process.env.AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT || ""
).replace(/\/+$/, "");
const azureDocumentKey = process.env.AZURE_DOCUMENT_INTELLIGENCE_KEY || "";

function normalizeParsedExpense(value) {
  const amount = Number(value?.amount);
  const type = String(value?.type || "others").toLowerCase();
  return {
    name: String(value?.name || "Unknown expense").trim(),
    amount: Number.isFinite(amount) ? Math.max(0, Math.round(amount)) : 0,
    category: String(value?.category || "general").trim().toLowerCase(),
    type: ["expected", "unexpected", "others"].includes(type)
      ? type
      : "others",
  };
}

/**
 * Parse a notification into the expense fields understood by the app.
 * The API key stays on the backend; notification text is never sent directly
 * from the mobile app to Google.
 */
app.post("/api/parse-notification", requireAuth, async (req, res) => {
  try {
    if (!parserApiKey) {
      return res.status(503).json({ error: "Gemini API key is not configured" });
    }

    const notification = String(req.body?.message || "").trim();
    if (!notification) {
      return res.status(400).json({ error: "Notification message is required" });
    }

    const prompt = `You extract expenses from a generic mobile notification.
Return only valid JSON with exactly these keys: name (string), amount (integer
in the source currency), category (short lowercase string), and type (one of
expected, unexpected, others). If it is not clearly an expense, still return
the best reasonable interpretation and use others. Do not include markdown.
Notification title: ${String(req.body?.title || "")}
Notification app: ${String(req.body?.packageName || "")}
Notification message: ${notification}`;

    const response = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=" +
        encodeURIComponent(parserApiKey),
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: {
              type: "OBJECT",
              properties: {
                name: { type: "STRING" },
                amount: { type: "INTEGER" },
                category: { type: "STRING" },
                type: { type: "STRING", enum: ["expected", "unexpected", "others"] },
              },
              required: ["name", "amount", "category", "type"],
            },
          },
        }),
      }
    );

    const body = await response.json();
    if (!response.ok) {
      const providerError = body.error?.message || "Gemini request failed";
      return res.status(502).json({ error: providerError });
    }

    const text = body.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (!text) return res.status(502).json({ error: "Gemini returned no parsed expense" });
    const jsonText = text.replace(/^```(?:json)?\s*|\s*```$/gi, "").trim();
    return res.json(normalizeParsedExpense(JSON.parse(jsonText)));
  } catch (err) {
    return res.status(502).json({ error: `Could not parse notification: ${err.message}` });
  }
});

const RECEIPT_CATEGORIES = [
  "makanan",
  "school supply",
  "baju",
  "elektronik",
  "transportasi",
  "kesehatan",
  "hiburan",
];

function normalizeReceiptItem(value) {
  const amount = Number(value?.amount);
  const quantity = Number(value?.quantity);
  const category = String(value?.category || "makanan").trim().toLowerCase();
  const type = String(value?.type || "others").toLowerCase();
  return {
    name: String(value?.name || "Unknown item").trim(),
    quantity: Number.isFinite(quantity) && quantity > 0 ? Math.round(quantity) : 1,
    amount: Number.isFinite(amount) ? Math.max(0, Math.round(amount)) : 0,
    category: RECEIPT_CATEGORIES.includes(category) ? category : "makanan",
    type: ["expected", "unexpected", "others"].includes(type) ? type : "others",
  };
}

function normalizeReceiptDate(value) {
  const date = String(value || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const parsed = new Date(`${date}T00:00:00Z`);
  return Number.isNaN(parsed.getTime()) ? null : date;
}

class ReceiptProviderError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

function isAzureConfigured() {
  return Boolean(azureDocumentEndpoint && azureDocumentKey);
}

function shouldUseAzureFallback(error) {
  return !error?.status || [429, 500, 502, 503, 504].includes(error.status);
}

async function fetchWithTimeout(url, options, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

function receiptPrompt() {
  return `You extract itemized purchases from a photo of a store or
restaurant receipt. Read the receipt date and every purchased line item, and ignore lines such as
subtotal, cash, change, or payment method. If the receipt also lists a tax
(PPN/tax) and/or a service charge, distribute those charges proportionally
across every item so each item's "amount" already includes its share of the
tax and service charge. Return only valid JSON with an "items" array. Each
item has: name (string), quantity (integer, default 1), amount (integer,
final price for that whole line, in the receipt's currency, tax/service
included), category (one of ${RECEIPT_CATEGORIES.join(", ")}), and type (one
of expected, unexpected, others). The top-level "date" must be the purchase
date in YYYY-MM-DD format, or null if it cannot be read. Do not include markdown.`;
}

async function parseReceiptWithGemini(imageBase64, mimeType) {
  const response = await fetchWithTimeout(
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=" +
      encodeURIComponent(parserApiKey),
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: receiptPrompt() },
              { inline_data: { mime_type: mimeType, data: imageBase64 } },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: {
            type: "OBJECT",
            properties: {
              date: { type: "STRING", nullable: true },
              items: {
                type: "ARRAY",
                items: {
                  type: "OBJECT",
                  properties: {
                    name: { type: "STRING" },
                    quantity: { type: "INTEGER" },
                    amount: { type: "INTEGER" },
                    category: { type: "STRING" },
                    type: { type: "STRING", enum: ["expected", "unexpected", "others"] },
                  },
                  required: ["name", "quantity", "amount", "category", "type"],
                },
              },
            },
            required: ["date", "items"],
          },
        },
      }),
    },
    15000
  );

  const body = await response.json();
  if (!response.ok) {
    throw new ReceiptProviderError(
      body.error?.message || "Gemini request failed",
      response.status
    );
  }

  const text = body.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
  if (!text) throw new ReceiptProviderError("Gemini returned no parsed receipt");
  const jsonText = text.replace(/^```(?:json)?\s*|\s*```$/gi, "").trim();
  const parsed = JSON.parse(jsonText);
  if (!Array.isArray(parsed?.items) || parsed.items.length === 0) {
    throw new ReceiptProviderError("Gemini returned no receipt items");
  }
  return parsed;
}

function azureFieldValue(field) {
  return (
    field?.valueString ??
    field?.valueDate ??
    field?.valueNumber ??
    field?.valueInteger ??
    field?.valueCurrency?.amount ??
    field?.value
  );
}

function azureItemValue(item, fieldName) {
  return azureFieldValue(item?.valueObject?.[fieldName]);
}

function addAzureTaxToItems(items, total) {
  const lineTotal = items.reduce((sum, item) => sum + item.amount, 0);
  const adjustment = total > lineTotal ? total - lineTotal : 0;
  if (!adjustment || !lineTotal) return items;

  let allocated = 0;
  return items.map((item, index) => {
    const share = index === items.length - 1
      ? adjustment - allocated
      : Math.round((adjustment * item.amount) / lineTotal);
    allocated += share;
    return { ...item, amount: item.amount + share };
  });
}

async function parseReceiptWithAzure(imageBase64) {
  const analyzeUrl =
    `${azureDocumentEndpoint}/documentintelligence/documentModels/prebuilt-receipt:analyze` +
    "?api-version=2024-11-30";
  const response = await fetchWithTimeout(
    analyzeUrl,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Ocp-Apim-Subscription-Key": azureDocumentKey,
      },
      body: JSON.stringify({ base64Source: imageBase64 }),
    },
    15000
  );

  if (response.status !== 202) {
    const body = await response.text();
    throw new ReceiptProviderError(
      body || "Azure Document Intelligence request failed",
      response.status
    );
  }

  const operationLocation = response.headers.get("operation-location");
  if (!operationLocation) {
    throw new ReceiptProviderError("Azure did not return an operation URL");
  }

  let result;
  for (let attempt = 0; attempt < 20; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    const pollResponse = await fetchWithTimeout(
      operationLocation,
      { headers: { "Ocp-Apim-Subscription-Key": azureDocumentKey } },
      10000
    );
    const pollBody = await pollResponse.json();
    if (!pollResponse.ok) {
      throw new ReceiptProviderError(
        pollBody.error?.message || "Azure polling failed",
        pollResponse.status
      );
    }
    if (pollBody.status === "succeeded") {
      result = pollBody.analyzeResult;
      break;
    }
    if (pollBody.status === "failed") {
      throw new ReceiptProviderError(
        pollBody.error?.message || "Azure could not read the receipt"
      );
    }
  }

  if (!result) throw new ReceiptProviderError("Azure receipt analysis timed out", 504);

  const document = result.documents?.[0];
  const fields = document?.fields || {};
  const rawItems = fields.Items?.valueArray || [];
  const items = rawItems.map((item) => ({
    name: String(azureItemValue(item, "Description") || "Unknown item"),
    quantity: Number(azureItemValue(item, "Quantity")) || 1,
    amount: Number(
      azureItemValue(item, "TotalPrice") ?? azureItemValue(item, "Price")
    ) || 0,
    category: "makanan",
    type: "others",
  }));
  const total = Number(azureFieldValue(fields.Total)) || 0;

  return {
    date: azureFieldValue(fields.TransactionDate),
    items: addAzureTaxToItems(items, total),
  };
}

/**
 * Parse a photo of a purchase receipt into a line-item split bill.
 * Tax/service charges printed on the receipt are distributed proportionally
 * into each item's amount so every returned item is already final price.
 */
app.post("/api/parse-receipt", requireAuth, async (req, res) => {
  try {
    if (!parserApiKey && !isAzureConfigured()) {
      return res.status(503).json({ error: "No receipt parser is configured" });
    }

    const imageBase64 = String(req.body?.image || "").trim();
    if (!imageBase64) {
      return res.status(400).json({ error: "Receipt image is required" });
    }
    const mimeType = String(req.body?.mimeType || "image/jpeg");

    let parsed;
    let provider = "azure";
    let geminiError;
    if (parserApiKey) {
      try {
        parsed = await parseReceiptWithGemini(imageBase64, mimeType);
        provider = "gemini";
      } catch (error) {
        geminiError = error;
      }
    }

    if (!parsed && isAzureConfigured() && shouldUseAzureFallback(geminiError)) {
      parsed = await parseReceiptWithAzure(imageBase64);
      provider = "azure";
    }

    if (!parsed) {
      throw geminiError || new ReceiptProviderError("Receipt parser failed");
    }

    const items = Array.isArray(parsed?.items) ? parsed.items.map(normalizeReceiptItem) : [];
    if (items.length === 0) {
      return res.status(422).json({ error: "No items were detected on the receipt" });
    }
    return res.json({ date: normalizeReceiptDate(parsed?.date), items, provider });
  } catch (err) {
    return res.status(err.status >= 400 ? err.status : 502).json({
      error: `Could not parse receipt: ${err.message}`,
    });
  }
});

/**
 * GET current exchange rates with IDR as the base currency.
 */
app.get("/api/exchange-rates", requireAuth, async (req, res) => {
  try {
    const response = await fetch("https://open.er-api.com/v6/latest/IDR");
    if (!response.ok) {
      return res.status(502).json({ error: "Exchange-rate provider unavailable" });
    }
    const data = await response.json();
    res.json({
      base: "IDR",
      rates: {
        IDR: 1,
        USD: data.rates.USD,
        EUR: data.rates.EUR,
      },
    });
  } catch (err) {
    res.status(502).json({ error: "Could not retrieve exchange rates" });
  }
});

/**
 * CREATE
 * POST /api/users
 */
app.post("/api/users", requireAuth, async (req, res) => {
  try {
    await connectDB();
    if (!req.body.localId) {
      return res.status(400).json({ error: "localId is required" });
    }
    const localId = String(req.body.localId);
    const user = await User.findOneAndUpdate(
      {
        ownerId: req.user.uid,
        localId,
      },
      {
        $set: {
          ownerId: req.user.uid,
          localId,
          name: req.body.name,
          amount: req.body.amount,
          category: req.body.category,
          type: req.body.type,
          date: req.body.date,
        },
      },
      {
        new: true,
        upsert: true,
        runValidators: true,
        setDefaultsOnInsert: true,
      }
    );
    res.status(200).json(user);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

/**
 * READ (all)
 * GET /api/users
 */
app.get("/api/users", requireAuth, async (req, res) => {
  await connectDB();
  const users = await User.find({ ownerId: req.user.uid });
  res.json(users);
});

/**
 * READ (one)
 * GET /api/users/:id
 */
app.get("/api/users/:id", requireAuth, async (req, res) => {
  await connectDB();
  const user = await User.findOne({ _id: req.params.id, ownerId: req.user.uid });
  if (!user) return res.status(404).json({ message: "Not found" });
  res.json(user);
});

/**
 * UPDATE
 * PUT /api/users/:id
 */
app.put("/api/users/:id", requireAuth, async (req, res) => {
  try {
    await connectDB();
    const updates = {
      name: req.body.name,
      amount: req.body.amount,
      category: req.body.category,
      type: req.body.type,
      date: req.body.date,
    };
    const user = await User.findOneAndUpdate(
      { _id: req.params.id, ownerId: req.user.uid },
      updates,
      { new: true, runValidators: true }
    );
    if (!user) return res.status(404).json({ message: "Not found" });
    res.json(user);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

/**
 * DELETE
 * DELETE /api/users/:id
 */
app.delete("/api/users/:id", requireAuth, async (req, res) => {
  await connectDB();
  await User.findOneAndDelete({ _id: req.params.id, ownerId: req.user.uid });
  res.json({ message: "Deleted" });
});

/**
 * BULK DELETE
 * POST /api/users/delete-all
 * Deletes every expense owned by the authenticated user in a single query.
 */
app.post("/api/users/delete-all", requireAuth, async (req, res) => {
  try {
    await connectDB();
    const result = await User.deleteMany({ ownerId: req.user.uid });
    res.status(200).json({ message: "Deleted", deletedCount: result.deletedCount });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * READ (one by localId)
 * GET /api/users/local/:localId
 */
app.get("/api/users/local/:localId", requireAuth, async (req, res) => {
  try {
    await connectDB();

    const user = await User.findOne({
      localId: req.params.localId,
      ownerId: req.user.uid,
    });

    if (!user) {
      return res.status(404).json({ message: "Not found" });
    }

    res.json(user);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});


module.exports = app;