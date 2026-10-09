const { AI_PROVIDER_TIMEOUT_MS } = require("../config/providers");
const { fetchWithTimeout } = require("../lib/fetchWithTimeout");

const groqApiKey = process.env.GROQ_API_KEY || "";
const groqModel = process.env.GROQ_MODEL || "";

class GroqError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

async function chatCompletion(messages, model, options = {}) {
  if (!groqApiKey) {
    throw new GroqError("Groq API key is not configured", 503);
  }

  const response = await fetchWithTimeout(
    "https://api.groq.com/openai/v1/chat/completions",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${groqApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: model || groqModel || "llama-3.3-70b-versatile",
        messages,
        response_format: { type: "json_object" },
        temperature: options.temperature ?? 0.7,
        max_tokens: options.maxTokens ?? 300,
      }),
    },
    AI_PROVIDER_TIMEOUT_MS
  );

  const body = await response.json();
  if (!response.ok) {
    throw new GroqError(body.error?.message || "Groq request failed", response.status);
  }

  const content = body.choices?.[0]?.message?.content;
  return parseContent(content);
}

function parseContent(content) {
  const text = Array.isArray(content)
    ? content
        .map((part) => (typeof part === "string" ? part : part?.text || ""))
        .join("")
        .trim()
    : String(content || "").trim();
  return text.replace(/^```(?:json)?\s*|\s*```$/gi, "").trim();
}

async function parseReceipt(imageBase64, mimeType, timeoutMs) {
  const receiptPrompt = `You extract itemized purchases from a photo of a store or
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
included), category (one of makanan, school supply, baju, elektronik, transportasi, kesehatan, hiburan), and type (one
of expected, unexpected, others). The top-level "date" must be the purchase
date in YYYY-MM-DD format, or null if it cannot be read. Do not include markdown.`;

  const text = await chatCompletion(
    [
      {
        role: "user",
        content: [
          { type: "text", text: receiptPrompt },
          {
            type: "image_url",
            image_url: {
              url: `data:${mimeType};base64,${imageBase64}`,
            },
          },
        ],
      },
    ],
    groqModel,
    { temperature: 0, maxTokens: 1024 }
  );

  if (!text) throw new GroqError("Groq returned no parsed receipt", 502);

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (_) {
    throw new GroqError("Groq returned invalid receipt JSON", 502);
  }
  if (!Array.isArray(parsed?.items) || parsed.items.length === 0) {
    throw new GroqError("Groq returned no receipt items", 422);
  }
  return parsed;
}

module.exports = { chatCompletion, parseReceipt, GroqError };
