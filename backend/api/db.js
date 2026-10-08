const { Pool } = require("pg");

let pool = null;
let schemaReady = false;

function sslFromDatabaseUrl(databaseUrl) {
  if (!databaseUrl) return false;
  return /[?&]sslmode=require(?:&|$)/i.test(databaseUrl);
}

function getPool() {
  if (pool) return pool;
  if (!process.env.DATABASE_URL) {
    throw new Error("DATABASE_URL is missing");
  }
  pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: sslFromDatabaseUrl(process.env.DATABASE_URL)
      ? { rejectUnauthorized: false }
      : false,
  });
  return pool;
}

async function ensureSchema() {
  if (schemaReady) return;
  const db = getPool();
  await db.query(`
    CREATE TABLE IF NOT EXISTS expenses (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      owner_id TEXT NOT NULL,
      local_id TEXT NOT NULL,
      name TEXT NOT NULL,
      amount INTEGER NOT NULL,
      category TEXT NOT NULL,
      type TEXT NOT NULL,
      date TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (owner_id, local_id)
    );
    CREATE INDEX IF NOT EXISTS expenses_owner_id_idx ON expenses (owner_id);
    CREATE TABLE IF NOT EXISTS ai_notification_references (
      owner_id TEXT PRIMARY KEY,
      items JSONB NOT NULL DEFAULT '[]'::jsonb,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
  schemaReady = true;
}

async function connectDB() {
  getPool();
  await ensureSchema();
}

function toExpenseJson(row) {
  if (!row) return null;
  return {
    _id: String(row.id),
    ownerId: row.owner_id,
    localId: row.local_id,
    name: row.name,
    amount: Number(row.amount),
    category: row.category,
    type: row.type,
    date: row.date,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function upsertExpense(ownerId, fields) {
  const localId = String(fields.localId);
  const name = String(fields.name ?? "");
  const amount = Number.isFinite(Number(fields.amount))
    ? Math.round(Number(fields.amount))
    : 0;
  const category = String(fields.category ?? "lainnya");
  const type = String(fields.type ?? "unexpected");
  const date = String(fields.date ?? "");

  const result = await getPool().query(
    `INSERT INTO expenses (owner_id, local_id, name, amount, category, type, date)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (owner_id, local_id) DO UPDATE SET
       name = EXCLUDED.name,
       amount = EXCLUDED.amount,
       category = EXCLUDED.category,
       type = EXCLUDED.type,
       date = EXCLUDED.date,
       updated_at = now()
     RETURNING *`,
    [
      ownerId,
      localId,
      name,
      amount,
      category,
      type,
      date,
    ]
  );
  return toExpenseJson(result.rows[0]);
}

async function listExpenses(ownerId) {
  const result = await getPool().query(
    `SELECT * FROM expenses WHERE owner_id = $1 ORDER BY date DESC, created_at DESC`,
    [ownerId]
  );
  return result.rows.map(toExpenseJson);
}

async function getExpenseById(ownerId, id) {
  const result = await getPool().query(
    `SELECT * FROM expenses WHERE id = $1 AND owner_id = $2`,
    [id, ownerId]
  );
  return toExpenseJson(result.rows[0]);
}

async function getExpenseByLocalId(ownerId, localId) {
  const result = await getPool().query(
    `SELECT * FROM expenses WHERE local_id = $1 AND owner_id = $2`,
    [String(localId), ownerId]
  );
  return toExpenseJson(result.rows[0]);
}

async function updateExpenseById(ownerId, id, fields) {
  const existing = await getExpenseById(ownerId, id);
  if (!existing) return null;

  const name = fields.name !== undefined ? String(fields.name) : existing.name;
  const amount =
    fields.amount !== undefined && Number.isFinite(Number(fields.amount))
      ? Math.round(Number(fields.amount))
      : existing.amount;
  const category =
    fields.category !== undefined ? String(fields.category) : existing.category;
  const type = fields.type !== undefined ? String(fields.type) : existing.type;
  const date = fields.date !== undefined ? String(fields.date) : existing.date;

  const result = await getPool().query(
    `UPDATE expenses
     SET name = $3,
         amount = $4,
         category = $5,
         type = $6,
         date = $7,
         updated_at = now()
     WHERE id = $1 AND owner_id = $2
     RETURNING *`,
    [
      id,
      ownerId,
      name,
      amount,
      category,
      type,
      date,
    ]
  );
  return toExpenseJson(result.rows[0]);
}

async function deleteExpenseById(ownerId, id) {
  await getPool().query(
    `DELETE FROM expenses WHERE id = $1 AND owner_id = $2`,
    [id, ownerId]
  );
}

async function deleteAllExpenses(ownerId) {
  const result = await getPool().query(
    `DELETE FROM expenses WHERE owner_id = $1`,
    [ownerId]
  );
  return result.rowCount;
}

async function listRecentExpensesForContext(ownerId, limit) {
  const result = await getPool().query(
    `SELECT name, amount, category, type, date, created_at
     FROM expenses
     WHERE owner_id = $1
     ORDER BY date DESC, created_at DESC
     LIMIT $2`,
    [ownerId, limit]
  );
  return result.rows;
}

async function upsertNotificationReference(ownerId, items) {
  const result = await getPool().query(
    `INSERT INTO ai_notification_references (owner_id, items, updated_at)
     VALUES ($1, $2::jsonb, now())
     ON CONFLICT (owner_id) DO UPDATE SET
       items = EXCLUDED.items,
       updated_at = now()
     RETURNING items`,
    [ownerId, JSON.stringify(items)]
  );
  return result.rows[0]?.items || [];
}

async function loadNotificationReferenceItems(ownerId) {
  const result = await getPool().query(
    `SELECT items FROM ai_notification_references WHERE owner_id = $1`,
    [ownerId]
  );
  return result.rows[0]?.items || [];
}

function isInvalidUuidError(err) {
  return err?.code === "22P02";
}

function setPool(customPool) {
  pool = customPool;
  schemaReady = false;
}

module.exports = {
  connectDB,
  deleteAllExpenses,
  deleteExpenseById,
  ensureSchema,
  getExpenseById,
  getExpenseByLocalId,
  getPool,
  isInvalidUuidError,
  listExpenses,
  listRecentExpensesForContext,
  loadNotificationReferenceItems,
  setPool,
  sslFromDatabaseUrl,
  toExpenseJson,
  updateExpenseById,
  upsertExpense,
  upsertNotificationReference,
};
