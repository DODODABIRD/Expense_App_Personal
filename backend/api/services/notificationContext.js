const MAX_NOTIFICATION_CONTEXT_ITEMS = 100;
const MAX_TEMPLATE_COMMON_ITEMS = 5;
const NOTIFICATION_TEMPLATE_VERSION = 1;

function toPromptItem(item) {
  const promptItem = {
    expenseitem: item.expenseitem,
    expenseprice: item.expenseprice,
  };

  for (const field of ["category", "type", "date"]) {
    if (item[field] != null) promptItem[field] = item[field];
  }

  return promptItem;
}

function normalizeTemplateItem(item) {
  const name = String(item?.expenseitem ?? "").trim();
  const amount = Number(item?.expenseprice);
  if (!name || !Number.isFinite(amount) || amount <= 0) return null;
  return {
    name,
    amount: Math.round(amount),
    category: String(item?.category ?? "").trim().toLowerCase() || "lainnya",
    type: String(item?.type ?? "").trim().toLowerCase(),
  };
}

// Builds a compact per-user summary of past expenses so the notification
// prompt can describe spending habits without sending every raw item.
function buildNotificationTemplate(items) {
  const entries = [];
  for (const item of Array.isArray(items) ? items : []) {
    const normalized = normalizeTemplateItem(item);
    if (normalized) entries.push(normalized);
  }

  const groups = new Map();
  for (const entry of entries) {
    let group = groups.get(entry.category);
    if (!group) {
      group = { amounts: [], names: new Map(), types: new Set() };
      groups.set(entry.category, group);
    }
    group.amounts.push(entry.amount);
    const nameKey = entry.name.toLowerCase();
    const nameStat = group.names.get(nameKey);
    if (nameStat) nameStat.count += 1;
    else group.names.set(nameKey, { name: entry.name, count: 1 });
    if (entry.type) group.types.add(entry.type);
  }

  const categories = Array.from(groups.entries())
    .map(([category, group]) => ({
      category,
      count: group.amounts.length,
      priceRange: {
        min: Math.min(...group.amounts),
        max: Math.max(...group.amounts),
      },
      averagePrice: Math.round(
        group.amounts.reduce((sum, amount) => sum + amount, 0) /
          group.amounts.length
      ),
      commonItems: Array.from(group.names.values())
        .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name))
        .slice(0, MAX_TEMPLATE_COMMON_ITEMS)
        .map((stat) => stat.name),
      types: Array.from(group.types).sort(),
    }))
    .sort((a, b) => b.count - a.count || a.category.localeCompare(b.category));

  const amounts = entries.map((entry) => entry.amount);
  return {
    version: NOTIFICATION_TEMPLATE_VERSION,
    sampleSize: entries.length,
    priceRange: amounts.length
      ? { min: Math.min(...amounts), max: Math.max(...amounts) }
      : null,
    categories,
  };
}

function isNotificationTemplate(value) {
  return (
    value != null &&
    typeof value === "object" &&
    value.version === NOTIFICATION_TEMPLATE_VERSION &&
    Array.isArray(value.categories)
  );
}

async function refreshNotificationContext({ query, ownerId }) {
  const expenses = await query.listRecentExpenses(ownerId, MAX_NOTIFICATION_CONTEXT_ITEMS);

  const items = (Array.isArray(expenses) ? expenses : [])
    .slice(0, MAX_NOTIFICATION_CONTEXT_ITEMS)
    .map((expense) => ({
      expenseitem: expense.name,
      expenseprice: expense.amount,
      category: expense.category,
      type: expense.type,
      date: expense.date,
    }));

  const template = buildNotificationTemplate(items);
  await query.upsertReference(ownerId, items, template);
  return items.length;
}

async function loadNotificationContext({ query, ownerId }) {
  const items = await query.loadReferenceItems(ownerId);
  return (Array.isArray(items) ? items : [])
    .slice(0, MAX_NOTIFICATION_CONTEXT_ITEMS)
    .map(toPromptItem);
}

async function loadNotificationTemplate({ query, ownerId }) {
  const stored = await query.loadTemplate(ownerId);
  if (isNotificationTemplate(stored)) return stored;

  // Legacy rows saved before templates existed: derive one from the raw items.
  return buildNotificationTemplate(await query.loadReferenceItems(ownerId));
}

module.exports = {
  MAX_NOTIFICATION_CONTEXT_ITEMS,
  buildNotificationTemplate,
  loadNotificationContext,
  loadNotificationTemplate,
  refreshNotificationContext,
};
