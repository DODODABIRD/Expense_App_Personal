const MAX_NOTIFICATION_CONTEXT_ITEMS = 100;

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

  await query.upsertReference(ownerId, items);
  return items.length;
}

async function loadNotificationContext({ query, ownerId }) {
  const items = await query.loadReferenceItems(ownerId);
  return (Array.isArray(items) ? items : [])
    .slice(0, MAX_NOTIFICATION_CONTEXT_ITEMS)
    .map(toPromptItem);
}

module.exports = {
  MAX_NOTIFICATION_CONTEXT_ITEMS,
  loadNotificationContext,
  refreshNotificationContext,
};
