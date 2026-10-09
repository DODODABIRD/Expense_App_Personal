const { requireAuth } = require("../middleware/auth");
const { parseReceipt, ReceiptProviderError } = require("../services/azureService");
const { parseReceipt: groqParseReceipt, GroqError } = require("../services/groqService");
const { AI_PROVIDER_TIMEOUT_MS, GROQ_RECEIPT_TIMEOUT_MS, isAzureConfigured } = require("../config/providers");
const { EXPENSE_CATEGORIES, EXPENSE_TYPES } = require("../config/categories");

function normalizeReceiptItem(value) {
  const amount = Number(value?.amount);
  const quantity = Number(value?.quantity);
  const rawCat = String(value?.category || "").trim().toLowerCase();
  const category = EXPENSE_CATEGORIES.includes(rawCat)
    ? rawCat
    : guessReceiptCategory(value?.name);
  const type = String(value?.type || "others").toLowerCase();
  return {
    name: String(value?.name || "Unknown item").trim(),
    quantity: Number.isFinite(quantity) && quantity > 0 ? Math.round(quantity) : 1,
    amount: Number.isFinite(amount) ? Math.max(0, Math.round(amount)) : 0,
    category,
    type: EXPENSE_TYPES.includes(type) ? type : "others",
  };
}

function normalizeReceiptDate(value) {
  if (!value) return null;
  const raw = String(value).trim();

  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    const parsed = new Date(`${raw}T00:00:00Z`);
    return Number.isNaN(parsed.getTime()) ? null : raw;
  }

  const dmy = raw.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
  if (dmy) {
    const day = dmy[1].padStart(2, "0");
    const month = dmy[2].padStart(2, "0");
    const year = dmy[3];
    const iso = `${year}-${month}-${day}`;
    const parsed = new Date(`${iso}T00:00:00Z`);
    return Number.isNaN(parsed.getTime()) ? null : iso;
  }

  const parsed = new Date(raw);
  if (!Number.isNaN(parsed.getTime())) {
    const y = parsed.getFullYear();
    const m = String(parsed.getMonth() + 1).padStart(2, "0");
    const d = String(parsed.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  return null;
}

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

function withReceiptTimeout(operation, timeoutMs, message) {
  if (timeoutMs <= 0) {
    return Promise.reject(new ReceiptProviderError(message, 504));
  }

  let timeout;
  return Promise.race([
    Promise.resolve().then(operation),
    new Promise((_, reject) => {
      timeout = setTimeout(
        () => reject(new ReceiptProviderError(message, 504)),
        timeoutMs
      );
    }),
  ]).finally(() => clearTimeout(timeout));
}

function shouldUseReceiptFallback(error) {
  return !error?.status || [400, 404, 429, 500, 502, 503, 504].includes(error.status);
}

async function parseReceiptRoute(req, res) {
  let streamStarted = false;
  const groqApiKey = process.env.GROQ_API_KEY || "";
  const groqModel = process.env.GROQ_MODEL || "";

  const deadline = Date.now() + AI_PROVIDER_TIMEOUT_MS;
  const remainingTime = () => Math.max(0, deadline - Date.now());

  try {
    if ((!groqApiKey || !groqModel) && !isAzureConfigured()) {
      return res.status(503).json({ error: "No receipt parser is configured" });
    }

    const imageBase64 = String(req.body?.image || "").trim();
    if (!imageBase64) {
      return res.status(400).json({ error: "Receipt image is required" });
    }
    const mimeType = String(req.body?.mimeType || "image/jpeg");

    res.status(200);
    res.setHeader("Content-Type", "application/x-ndjson; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders?.();
    streamStarted = true;

    const sendProgress = (stage, status, progress, message) => {
      res.write(`${JSON.stringify({ type: "progress", stage, status, progress, message })}\n`);
    };

    let parsed;
    let provider;
    let lastError;

    if (groqApiKey && groqModel) {
      sendProgress("groq", "processing", 0.4, "Processing with Groq");
      try {
        const timeoutMs = Math.min(GROQ_RECEIPT_TIMEOUT_MS, remainingTime());
        parsed = await withReceiptTimeout(
          () => groqParseReceipt(imageBase64, mimeType, timeoutMs),
          timeoutMs,
          "Groq receipt parsing timed out"
        );
        provider = "groq";
      } catch (error) {
        lastError = error;
        sendProgress("groq", "failed", 0.46, `Groq failed: ${error.message}`);
        console.warn(`[ReceiptParser] Groq failed (${error.status || error.message}), trying Azure...`);
      }
    } else {
      sendProgress("groq", "skipped", 0.36, "Groq skipped: API key or model is not configured");
    }

    if (!parsed && isAzureConfigured() && shouldUseReceiptFallback(lastError)) {
      sendProgress("azure", "processing", 0.68, "Processing with Azure Document Intelligence");
      try {
        parsed = await withReceiptTimeout(
          () => parseReceipt(imageBase64),
          remainingTime(),
          "Receipt parsing exceeded the 8-second time limit"
        );
        provider = "azure";
      } catch (error) {
        lastError = error;
        sendProgress("azure", "failed", 0.86, `Azure failed: ${error.message}`);
      }
    } else if (!parsed) {
      sendProgress("azure", "skipped", 0.66, "Azure skipped: credentials are not configured or fallback is not eligible");
    }

    if (!parsed) {
      throw lastError || new ReceiptProviderError("Receipt parser failed");
    }

    const items = Array.isArray(parsed?.items) ? parsed.items.map(normalizeReceiptItem) : [];
    if (items.length === 0) {
      throw new ReceiptProviderError("No items were detected on the receipt", 422);
    }

    res.write(`${JSON.stringify({
      type: "result",
      date: normalizeReceiptDate(parsed?.date),
      items,
      provider,
    })}\n`);
    return res.end();
  } catch (err) {
    const message = `Could not parse receipt: ${err.message}`;
    if (streamStarted) {
      res.write(`${JSON.stringify({ type: "error", message })}\n`);
      return res.end();
    }
    return res.status(err.status >= 400 ? err.status : 502).json({ error: message });
  }
}

module.exports = { parseReceiptRoute };
