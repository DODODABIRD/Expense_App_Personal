const { fetchWithTimeout } = require("../lib/fetchWithTimeout");
const { isAzureConfigured, getAzureEndpoint } = require("../config/providers");
const { RECEIPT_CATEGORIES } = require("../config/categories");

class ReceiptProviderError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

function parseAzureAmount(field) {
  if (!field) return 0;

  const content = String(
    field?.content ??
    field?.valueString ??
    ""
  ).trim();

  const rawValueNumber =
    field?.valueNumber ??
    field?.valueInteger ??
    field?.valueCurrency?.amount ??
    (typeof field?.value === "number" ? field.value : null);
  const valueNumber =
    typeof rawValueNumber === "string" ? Number(rawValueNumber) : rawValueNumber;

  if (content) {
    let text = content
      .replace(/^(?:Rp|IDR|RP|idr|\$|\€|\£)\.?\s*/i, "")
      .replace(/\s*(?:,\-|\.\-|\-)$/, "")
      .replace(/[\*\#\@]/g, "")
      .trim();

    text = text.replace(/\s+[A-Za-z]$/, "").trim();

    const kMatch = text.match(/^(\d+(?:[.,]\d+)?)\s*[kK]$/);
    if (kMatch) {
      const val = parseFloat(kMatch[1].replace(/,/g, "."));
      if (!Number.isNaN(val)) return Math.round(val * 1000);
    }

    if (/^\d{1,3}(?:\.\d{3})+(?:,\d+)?$/.test(cleanText(text))) {
      const integerPart = cleanText(text).replace(/\./g, "").replace(/,.*/, "");
      const num = parseInt(integerPart, 10);
      if (!Number.isNaN(num)) return num;
    }

    if (/^\d{1,3}(?:\.\d{3})+\.\d{2}$/.test(text)) {
      const parts = text.split(".");
      parts.pop();
      const num = parseInt(parts.join(""), 10);
      if (!Number.isNaN(num)) return num;
    }

    if (/^\d{1,3}(?:,\d{3})+(?:\.\d+)?$/.test(cleanText(text))) {
      const integerPart = cleanText(text).replace(/,/g, "").replace(/\..*/, "");
      const num = parseInt(integerPart, 10);
      if (!Number.isNaN(num)) return num;
    }

    const singleDotThree = text.match(/^(\d+)\.(\d{3})$/);
    if (singleDotThree) {
      return parseInt(singleDotThree[1] + singleDotThree[2], 10);
    }

    if (/^\d{1,3}(?:\s\d{3})+$/.test(text)) {
      const num = parseInt(text.replace(/\s+/g, ""), 10);
      if (!Number.isNaN(num)) return num;
    }

    if (/^\d+$/.test(text)) {
      const num = parseInt(text, 10);
      if (!Number.isNaN(num)) return num;
    }

    if (/^\d+,\d+$/.test(text)) {
      const num = parseInt(text.replace(/,.*/, ""), 10);
      if (!Number.isNaN(num)) return num;
    }

    const embedded = text.match(/\d{1,3}(?:\.\d{3})+/);
    if (embedded) {
      const num = parseInt(embedded[0].replace(/\./g, ""), 10);
      if (!Number.isNaN(num)) return num;
    }
  }

  if (typeof valueNumber === "number" && !Number.isNaN(valueNumber)) {
    const strVal = valueNumber.toString();
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

function azureFieldAmount(fields, names) {
  const wanted = new Set(
    names.map((name) => String(name).replace(/[^a-z0-9]/gi, "").toLowerCase())
  );
  for (const [key, field] of Object.entries(fields || {})) {
    const normalizedKey = key.replace(/[^a-z0-9]/gi, "").toLowerCase();
    if (wanted.has(normalizedKey)) {
      const amount = parseAzureAmount(field);
      if (amount > 0) return amount;
    }
  }
  return 0;
}

function collectAzureOcrText(result, document) {
  const pageLines = (result?.pages || []).flatMap((page) =>
    (page.lines || []).map((line) => line.content)
  );
  const tableCells = (result?.tables || []).flatMap((table) =>
    (table.cells || []).map((cell) => cell.content)
  );
  return [result?.content, document?.content, ...pageLines, ...tableCells]
    .filter((value) => value !== undefined && value !== null && String(value).trim())
    .map((value) => String(value).trim())
    .join("\n");
}

function azureTextAmountsAfterLabel(text, labelPattern) {
  const amounts = [];
  const lines = String(text || "").split(/\r?\n/);
  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex];
    const match = line.match(labelPattern);
    if (!match) continue;
    const afterLabel = line.slice((match.index || 0) + match[0].length);
    const nextLine = lines[lineIndex + 1] || "";
    const valueText = /\d/.test(afterLabel)
      ? afterLabel
      : `${afterLabel} ${nextLine}`;
    const tokens = valueText.match(/(?:Rp|IDR|RP|\$|€|£)?\s*\d[\d.,\s]*(?:\s*[kK])?/g) || [];
    for (const token of tokens) {
      const amount = parseAzureAmount({ content: token });
      if (amount > 0) amounts.push(amount);
    }
  }
  return amounts;
}

function uniqueAzureAmounts(amounts) {
  return [...new Set(amounts.filter((amount) => Number.isFinite(amount) && amount > 0))];
}

function azurePlainTotalFromOcr(text) {
  for (const line of String(text || "").split(/\r?\n/)) {
    if (!/^\s*total\b/i.test(line)) continue;
    if (/\b(?:items?|tax|subtotal|discount|qty|quantity)\b/i.test(line)) continue;
    const amounts = azureTextAmountsAfterLabel(line, /^\s*total\b/i);
    if (amounts.length > 0) return amounts[0];
  }
  return 0;
}

function resolveAzureReceiptTotals(result, document, fields) {
  const ocrText = collectAzureOcrText(result, document);
  const subtotal =
    azureTextAmountsAfterLabel(ocrText, /\bsub\s*total\b/i)[0] ||
    azureFieldAmount(fields, ["Subtotal"]);

  const grandTotalFromOcr =
    azureTextAmountsAfterLabel(
      ocrText,
      /\b(?:grand\s*total|total\s*due|amount\s*due|balance\s*due|net\s*total)\b/i
    )[0] ||
    azurePlainTotalFromOcr(ocrText);
  const grandTotalFromFields = azureFieldAmount(fields, [
    "GrandTotal",
    "TotalDue",
    "AmountDue",
    "BalanceDue",
  ]);
  const structuredTotal = parseAzureAmount(fields?.Total);

  const explicitTax = uniqueAzureAmounts(
    azureTextAmountsAfterLabel(ocrText, /\b(?:ppn|pb1|vat|gst)\b/i)
  );
  const genericTax = uniqueAzureAmounts(
    azureTextAmountsAfterLabel(ocrText, /\b(?:tax|pajak)\b/i)
  );
  const tax = explicitTax.length > 0
    ? explicitTax.reduce((sum, amount) => sum + amount, 0)
    : genericTax.length > 0
      ? genericTax.reduce((sum, amount) => sum + amount, 0)
      : azureFieldAmount(fields, ["TotalTax", "Tax", "Pajak"]);

  const serviceChargeFromOcr = uniqueAzureAmounts(
    azureTextAmountsAfterLabel(ocrText, /\b(?:service\s*charge|service|sc|tip)\b/i)
  );
  const serviceCharge = serviceChargeFromOcr.length > 0
    ? serviceChargeFromOcr.reduce((sum, amount) => sum + amount, 0)
    : azureFieldAmount(fields, ["ServiceCharge", "Tip"]);
  const breakdownTotal = subtotal > 0 ? subtotal + tax + serviceCharge : 0;

  let total = grandTotalFromOcr || grandTotalFromFields;
  if (!total) {
    const hasChargeEvidence = tax > 0 || serviceCharge > 0;
    if (breakdownTotal > 0 && structuredTotal > 0 && hasChargeEvidence) {
      const difference = Math.abs(breakdownTotal - structuredTotal);
      const roundingTolerance = Math.max(100, Math.round(breakdownTotal * 0.001));
      total = difference <= roundingTolerance ? structuredTotal : breakdownTotal;
    } else {
      total = structuredTotal || breakdownTotal || subtotal;
    }
  }

  return { subtotal, tax, serviceCharge, breakdownTotal, total };
}

function reconcileAzureItemsToTotal(items, total) {
  const targetTotal = Math.max(0, Math.round(Number(total) || 0));
  const lineTotal = items.reduce(
    (sum, item) => sum + Math.max(0, Math.round(Number(item.amount) || 0)),
    0
  );
  if (!targetTotal || !lineTotal || targetTotal === lineTotal) return items;

  const allocations = items.map((item, index) => {
    const amount = Math.max(0, Math.round(Number(item.amount) || 0));
    const exact = (amount * targetTotal) / lineTotal;
    return {
      index,
      amount: Math.floor(exact),
      remainder: exact - Math.floor(exact),
    };
  });

  let allocatedTotal = allocations.reduce((sum, item) => sum + item.amount, 0);
  const byRemainder = [...allocations].sort(
    (left, right) => right.remainder - left.remainder || left.index - right.index
  );
  let cursor = 0;
  while (allocatedTotal < targetTotal && byRemainder.length > 0) {
    byRemainder[cursor % byRemainder.length].amount += 1;
    allocatedTotal += 1;
    cursor += 1;
  }

  return items.map((item, index) => ({
    ...item,
    amount: allocations[index].amount,
  }));
}

async function parseReceipt(imageBase64) {
  if (!isAzureConfigured()) {
    throw new ReceiptProviderError("Azure is not configured", 503);
  }

  const analyzeUrl =
    `${getAzureEndpoint()}/documentintelligence/documentModels/prebuilt-receipt:analyze` +
    "?api-version=2024-11-30";
  const response = await fetchWithTimeout(
    analyzeUrl,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Ocp-Apim-Subscription-Key": process.env.AZURE_DOCUMENT_INTELLIGENCE_KEY,
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
      { headers: { "Ocp-Apim-Subscription-Key": process.env.AZURE_DOCUMENT_INTELLIGENCE_KEY } },
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

  const totals = resolveAzureReceiptTotals(result, document, fields);
  let total = totals.total;
  const subtotal = totals.subtotal;

  // IDR scaling sanity check
  const rawLineTotal = items.reduce((sum, item) => sum + item.amount, 0);
  const scaleReference = subtotal || total;
  if (scaleReference >= 10000 && rawLineTotal > 0 && rawLineTotal < 1000) {
    for (const item of items) {
      item.amount *= 1000;
    }
  } else if (scaleReference > 0 && scaleReference < 1000 && rawLineTotal > 0 && rawLineTotal < 1000) {
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
    items: reconcileAzureItemsToTotal(items, total),
  };
}

module.exports = {
  parseReceipt,
  ReceiptProviderError,
  parseAzureAmount,
  guessReceiptCategory,
};
