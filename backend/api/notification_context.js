const MAX_NOTIFICATION_CONTEXT_ITEMS = 100;
const EXPENSE_CONTEXT_PROJECTION = "name amount category type date createdAt";

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

async function refreshNotificationContext({ Expense, Reference, ownerId }) {
  const expenses = await Expense.find({ ownerId })
    .select(EXPENSE_CONTEXT_PROJECTION)
    .sort({ date: -1, createdAt: -1 })
    .limit(MAX_NOTIFICATION_CONTEXT_ITEMS)
    .lean();

  const items = (Array.isArray(expenses) ? expenses : [])
    .slice(0, MAX_NOTIFICATION_CONTEXT_ITEMS)
    .map((expense) => ({
      expenseitem: expense.name,
      expenseprice: expense.amount,
      category: expense.category,
      type: expense.type,
      date: expense.date,
    }));

  await Reference.findOneAndUpdate(
    { ownerId },
    { $set: { ownerId, items } },
    { new: true, upsert: true, runValidators: true }
  );

  return items.length;
}

async function loadNotificationContext({ Reference, ownerId }) {
  const reference = await Reference.findOne({ ownerId })
    .select("items")
    .lean();

  return (Array.isArray(reference?.items) ? reference.items : [])
    .slice(0, MAX_NOTIFICATION_CONTEXT_ITEMS)
    .map(toPromptItem);
}

module.exports = {
  EXPENSE_CONTEXT_PROJECTION,
  MAX_NOTIFICATION_CONTEXT_ITEMS,
  loadNotificationContext,
  refreshNotificationContext,
};