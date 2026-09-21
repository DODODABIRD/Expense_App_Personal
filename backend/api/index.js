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

const geminiModel =
  process.env.GEMINI_MODEL ||
  process.env.GOOGLE_MODEL ||
  "gemini-3.6-flash";

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
Return only valid JSON with exactly these keys: name (string), amount (integer in the source currency, e.g. in IDR Rupiah as full integer without decimals), category (short lowercase string), and type (one of expected, unexpected, others).
IMPORTANT: In Indonesian Rupiah (Rp / IDR), periods (.) are thousands separators (e.g. "Rp 50.000" = 50000). Never return divided amounts.
If it is not clearly an expense, still return the best reasonable interpretation and use others. Do not include markdown.
Notification title: ${String(req.body?.title || "")}
Notification app: ${String(req.body?.packageName || "")}
Notification message: ${notification}`;

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(geminiModel)}:generateContent?key=` +
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

function guessReceiptCategory(itemName) {
  const lower = String(itemName || "").toLowerCase();
  if (/bensin|pertalite|pertamax|spbu|parkir|tol|grab|gojek|taxi|ojol/.test(lower)) {
    return "transportasi";
  }
  if (/obat|apotek|panadol|paracetamol|vitamin|dokter|klinik|masker|bodrex|tolak angin/.test(lower)) {
    return "kesehatan";
  }
  if (/kabel|charger|batere|battery|mouse|keyboard|usb|headphone|earphone|hp/.test(lower)) {
    return "elektronik";
  }
  if (/kaos|kemeja|celana|baju|dress|rok|jaket|jacket|sepatu|sandal|t-shirt/.test(lower)) {
    return "baju";
  }
  if (/buku|pulpen|pensil|penghapus|kertas|atk|fotocopy|binder|spidol/.test(lower)) {
    return "school supply";
  }
  if (/bioskop|tiket|cinema|xxi|karaoke|game|billiard|wisata/.test(lower)) {
    return "hiburan";
  }
  return "makanan";
}

function normalizeReceiptItem(value) {
  const amount = Number(value?.amount);
  const quantity = Number(value?.quantity);
  const rawCat = String(value?.category || "").trim().toLowerCase();
  const category = RECEIPT_CATEGORIES.includes(rawCat)
    ? rawCat
    : guessReceiptCategory(value?.name);
  const type = String(value?.type || "others").toLowerCase();
  return {
    name: String(value?.name || "Unknown item").trim(),
    quantity: Number.isFinite(quantity) && quantity > 0 ? Math.round(quantity) : 1,
    amount: Number.isFinite(amount) ? Math.max(0, Math.round(amount)) : 0,
    category,
    type: ["expected", "unexpected", "others"].includes(type) ? type : "others",
  };
}

function normalizeReceiptDate(value) {
  if (!value) return null;
  const raw = String(value).trim();

  // 1. ISO format: YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    const parsed = new Date(`${raw}T00:00:00Z`);
    return Number.isNaN(parsed.getTime()) ? null : raw;
  }

  // 2. Common Indonesian formats: DD/MM/YYYY or DD-MM-YYYY
  const dmy = raw.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
  if (dmy) {
    const day = dmy[1].padStart(2, "0");
    const month = dmy[2].padStart(2, "0");
    const year = dmy[3];
    const iso = `${year}-${month}-${day}`;
    const parsed = new Date(`${iso}T00:00:00Z`);
    return Number.isNaN(parsed.getTime()) ? null : iso;
  }

  // 3. Fallback date string parsing (e.g. "18 Sep 2026")
  const parsed = new Date(raw);
  if (!Number.isNaN(parsed.getTime())) {
    const y = parsed.getFullYear();
    const m = String(parsed.getMonth() + 1).padStart(2, "0");
    const d = String(parsed.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  return null;
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
  return !error?.status || [400, 404, 429, 500, 502, 503, 504].includes(error.status);
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
subtotal, cash, change, or payment method.

IMPORTANT FOR INDONESIAN (IDR) RECEIPTS & NUMBER FORMATTING:
- In Indonesian receipts, prices are in Rupiah (IDR). Periods (.) are frequently used as thousands separators (e.g., "174.000" means 174000 IDR, "313.082" means 313082 IDR, "20.000" means 20000 IDR, "14.000" means 14000 IDR). Never treat those periods as decimal points.
- Always output the full integer value in the local currency without decimals (e.g., 174000, not 174; 313082, not 313).

If the receipt also lists a tax (PPN/PB1/tax) and/or a service charge (SC), distribute those charges proportionally
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
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(geminiModel)}:generateContent?key=` +
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

function parseAzureAmount(field) {
  if (!field) return 0;

  const content = String(
    field?.content ??
    field?.valueString ??
    ""
  ).trim();

  const valueNumber =
    field?.valueNumber ??
    field?.valueInteger ??
    field?.valueCurrency?.amount ??
    (typeof field?.value === "number" ? field.value : null);

  // 1. Inspect raw OCR content string for currency/thousand separator patterns
  if (content) {
    let text = content
      .replace(/^(?:Rp|IDR|RP|idr|\$|\€|\£)\.?\s*/i, "")
      .replace(/\s*(?:,\-|\.\-|\-)$/, "")
      .replace(/[\*\#\@]/g, "")
      .trim();

    // Remove single trailing tax code character like "174.000 B" or "174.000 A"
    text = text.replace(/\s+[A-Za-z]$/, "").trim();

    // Handle 'k' / 'K' (e.g. 174k, 25.5k)
    const kMatch = text.match(/^(\d+(?:[.,]\d+)?)\s*[kK]$/);
    if (kMatch) {
      const val = parseFloat(kMatch[1].replace(/,/g, "."));
      if (!Number.isNaN(val)) return Math.round(val * 1000);
    }

    // Indonesian / European dot thousands separator: e.g. "174.000", "1.250.000", "313.082"
    if (/^\d{1,3}(?:\.\d{3})+(?:,\d+)?$/.test(cleanText(text))) {
      const integerPart = cleanText(text).replace(/\./g, "").replace(/,.*/, "");
      const num = parseInt(integerPart, 10);
      if (!Number.isNaN(num)) return num;
    }

    // Double dot / noise like "174.000.00"
    if (/^\d{1,3}(?:\.\d{3})+\.\d{2}$/.test(text)) {
      const parts = text.split(".");
      parts.pop();
      const num = parseInt(parts.join(""), 10);
      if (!Number.isNaN(num)) return num;
    }

    // US comma thousands separator: e.g. "1,250,000.00" or "174,000"
    if (/^\d{1,3}(?:,\d{3})+(?:\.\d+)?$/.test(cleanText(text))) {
      const integerPart = cleanText(text).replace(/,/g, "").replace(/\..*/, "");
      const num = parseInt(integerPart, 10);
      if (!Number.isNaN(num)) return num;
    }

    // Single dot with exactly 3 digits: e.g. "313.082" or "18.620"
    const singleDotThree = text.match(/^(\d+)\.(\d{3})$/);
    if (singleDotThree) {
      return parseInt(singleDotThree[1] + singleDotThree[2], 10);
    }

    // Space as thousands separator: "174 000"
    if (/^\d{1,3}(?:\s\d{3})+$/.test(text)) {
      const num = parseInt(text.replace(/\s+/g, ""), 10);
      if (!Number.isNaN(num)) return num;
    }

    // Pure digits: "174000"
    if (/^\d+$/.test(text)) {
      const num = parseInt(text, 10);
      if (!Number.isNaN(num)) return num;
    }

    // Comma decimal: "174000,50"
    if (/^\d+,\d+$/.test(text)) {
      const num = parseInt(text.replace(/,.*/, ""), 10);
      if (!Number.isNaN(num)) return num;
    }

    // Embedded dot sequence in text: "Total : 313.082"
    const embedded = text.match(/\d{1,3}(?:\.\d{3})+/);
    if (embedded) {
      const num = parseInt(embedded[0].replace(/\./g, ""), 10);
      if (!Number.isNaN(num)) return num;
    }
  }

  // 2. Inspect valueNumber / valueCurrency.amount fallback
  if (typeof valueNumber === "number" && !Number.isNaN(valueNumber)) {
    const strVal = valueNumber.toString();
    // If Azure parsed "313.082" as float 313.082 with 3 decimal digits
    if (/\.\d{3}$/.test(strVal)) {
      return Math.round(valueNumber * 1000);
    }
    return Math.round(valueNumber);
  }

  return 0;
}

function cleanText(str) {
  return String(str || "").replace(/[^\d.,]/g, "").trim();
}

function azureFieldValue(field) {
  return (
    field?.valueString ??
    field?.valueDate ??
    field?.valueNumber ??
    field?.valueInteger ??
    field?.valueCurrency?.amount ??
    field?.value ??
    field?.content
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
  let rawItems = fields.Items?.valueArray || [];

  // Table fallback if Items field is missing or empty
  if (rawItems.length === 0 && Array.isArray(result.tables) && result.tables.length > 0) {
    const table = result.tables[0];
    const rowMap = new Map();
    for (const cell of table.cells || []) {
      if (!rowMap.has(cell.rowIndex)) rowMap.set(cell.rowIndex, []);
      rowMap.get(cell.rowIndex).push(cell);
    }
    const extracted = [];
    for (const [rowIndex, cells] of rowMap.entries()) {
      const rowText = cells.map((c) => c.content).join(" ").toLowerCase();
      if (rowIndex === 0 && /item|desc|qty|price|total|harga|nama/i.test(rowText)) continue;

      let itemPrice = 0;
      let itemQty = 1;
      let itemDesc = "";

      for (const cell of cells) {
        const amt = parseAzureAmount(cell);
        const cellText = String(cell.content || "").trim();
        if (amt > 0 && itemPrice === 0) {
          itemPrice = amt;
        } else if (/^\d{1,2}$/.test(cellText) && itemQty === 1) {
          itemQty = parseInt(cellText, 10);
        } else if (cellText.length > itemDesc.length && !/^\d+$/.test(cellText)) {
          itemDesc = cellText;
        }
      }

      if (itemPrice > 0) {
        extracted.push({
          name: itemDesc || `Item ${rowIndex}`,
          quantity: itemQty,
          amount: itemPrice,
          category: guessReceiptCategory(itemDesc),
          type: "others",
        });
      }
    }
    if (extracted.length > 0) {
      rawItems = extracted;
    }
  }

  const items = rawItems.map((item) => {
    if (item.amount !== undefined && item.name !== undefined) {
      return item;
    }

    const qtyRaw = Number(azureItemValue(item, "Quantity"));
    const quantity = Number.isFinite(qtyRaw) && qtyRaw > 0 ? Math.round(qtyRaw) : 1;
    const totalPrice = parseAzureAmount(item?.valueObject?.TotalPrice);
    const unitPrice = parseAzureAmount(item?.valueObject?.Price);

    let amount = 0;
    if (totalPrice > 0) {
      amount = totalPrice;
    } else if (unitPrice > 0) {
      amount = unitPrice * quantity;
    }

    const name = String(
      azureItemValue(item, "Description") ||
      azureItemValue(item, "Name") ||
      item?.content ||
      "Unknown item"
    ).trim();

    return {
      name: name || "Unknown item",
      quantity,
      amount,
      category: guessReceiptCategory(name),
      type: "others",
    };
  });

  let total = parseAzureAmount(fields.Total);
  if (!total) {
    const subtotal = parseAzureAmount(fields.Subtotal);
    const tax = parseAzureAmount(fields.TotalTax) || parseAzureAmount(fields.Tax);
    const tip = parseAzureAmount(fields.Tip) || parseAzureAmount(fields.ServiceCharge);
    if (subtotal > 0) {
      total = subtotal + tax + tip;
    }
  }

  // IDR scaling sanity check:
  // If total is in thousands (>= 10,000) but items were parsed as units (< 1000)
  const rawLineTotal = items.reduce((sum, item) => sum + item.amount, 0);
  if (total >= 10000 && rawLineTotal > 0 && rawLineTotal < 1000) {
    for (const item of items) {
      item.amount *= 1000;
    }
  } else if (total > 0 && total < 1000 && rawLineTotal > 0 && rawLineTotal < 1000) {
    total *= 1000;
    for (const item of items) {
      item.amount *= 1000;
    }
  } else if (rawLineTotal >= 10000) {
    for (const item of items) {
      if (item.amount > 0 && item.amount < 1000) {
        item.amount *= 1000;
      }
    }
  }

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
        console.warn(`[ReceiptParser] Gemini failed (${error.status || error.message}), falling back to Azure...`);
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