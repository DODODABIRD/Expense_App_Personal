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
    ALTER TABLE expenses DROP COLUMN IF EXISTS id;
    CREATE TABLE IF NOT EXISTS ai_notification_references (
      owner_id TEXT PRIMARY KEY,
      items JSONB NOT NULL DEFAULT '[]'::jsonb,
      summary JSONB NOT NULL DEFAULT '{}'::jsonb,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    ALTER TABLE ai_notification_references
      ADD COLUMN IF NOT EXISTS summary JSONB NOT NULL DEFAULT '{}'::jsonb;
    CREATE TABLE IF NOT EXISTS admin_audit_log (
      id BIGSERIAL PRIMARY KEY,
      actor TEXT NOT NULL,
      action TEXT NOT NULL,
      target TEXT,
      detail JSONB NOT NULL DEFAULT '{}'::jsonb,
      ip TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS admin_audit_log_created_at_idx
      ON admin_audit_log (created_at DESC);
    CREATE TABLE IF NOT EXISTS ai_provider_events (
      id BIGSERIAL PRIMARY KEY,
      owner_id TEXT,
      provider TEXT NOT NULL,
      status TEXT NOT NULL,
      duration_ms INTEGER,
      error TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS ai_provider_events_created_at_idx
      ON ai_provider_events (created_at DESC);
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

async function getExpenseByLocalId(ownerId, localId) {
  const result = await getPool().query(
    `SELECT * FROM expenses WHERE local_id = $1 AND owner_id = $2`,
    [String(localId), ownerId]
  );
  return toExpenseJson(result.rows[0]);
}

async function updateExpenseByLocalId(ownerId, localId, fields) {
  const existing = await getExpenseByLocalId(ownerId, localId);
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
     WHERE local_id = $1 AND owner_id = $2
     RETURNING *`,
    [
      String(localId),
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

async function deleteExpenseByLocalId(ownerId, localId) {
  await getPool().query(
    `DELETE FROM expenses WHERE local_id = $1 AND owner_id = $2`,
    [String(localId), ownerId]
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

async function upsertNotificationReference(ownerId, items, summary = {}) {
  const result = await getPool().query(
    `INSERT INTO ai_notification_references (owner_id, items, summary, updated_at)
     VALUES ($1, $2::jsonb, $3::jsonb, now())
     ON CONFLICT (owner_id) DO UPDATE SET
       items = EXCLUDED.items,
       summary = EXCLUDED.summary,
       updated_at = now()
     RETURNING items`,
    [ownerId, JSON.stringify(items), JSON.stringify(summary)]
  );
  return result.rows[0]?.items || [];
}

async function loadNotificationSummary(ownerId) {
  const result = await getPool().query(
    `SELECT summary FROM ai_notification_references WHERE owner_id = $1`,
    [ownerId]
  );
  const summary = result.rows[0]?.summary;
  return summary && typeof summary === "object" ? summary : null;
}

async function loadNotificationReferenceItems(ownerId) {
  const result = await getPool().query(
    `SELECT items FROM ai_notification_references WHERE owner_id = $1`,
    [ownerId]
  );
  return result.rows[0]?.items || [];
}

function setPool(customPool) {
  pool = customPool;
  schemaReady = false;
}

async function insertAdminAudit({ actor, action, target, detail, ip }) {
  await getPool().query(
    `INSERT INTO admin_audit_log (actor, action, target, detail, ip)
     VALUES ($1, $2, $3, $4::jsonb, $5)`,
    [
      String(actor || "unknown"),
      String(action),
      target ? String(target) : null,
      JSON.stringify(detail || {}),
      ip ? String(ip) : null,
    ]
  );
}

async function listAdminAuditLogs(limit = 100) {
  const result = await getPool().query(
    `SELECT * FROM admin_audit_log ORDER BY created_at DESC, id DESC LIMIT $1`,
    [limit]
  );
  return result.rows.map((row) => ({
    id: Number(row.id),
    actor: row.actor,
    action: row.action,
    target: row.target,
    detail: row.detail || {},
    ip: row.ip,
    createdAt: row.created_at,
  }));
}

async function listExpenseOwners() {
  const result = await getPool().query(
    `SELECT owner_id,
            COUNT(*)::int AS expense_count,
            COALESCE(SUM(amount), 0)::bigint AS total_amount,
            MAX(date) AS last_expense_date,
            MAX(updated_at) AS last_updated_at
     FROM expenses
     GROUP BY owner_id
     ORDER BY total_amount DESC
     LIMIT 500`
  );
  return result.rows.map((row) => ({
    ownerId: row.owner_id,
    expenseCount: Number(row.expense_count),
    totalAmount: Number(row.total_amount),
    lastExpenseDate: row.last_expense_date,
    lastUpdatedAt: row.last_updated_at,
  }));
}

async function listAdminExpenses({ ownerId, search, from, to, page, pageSize } = {}) {
  const clauses = [];
  const params = [];

  if (ownerId) {
    params.push(String(ownerId));
    clauses.push(`owner_id = $${params.length}`);
  }
  if (search) {
    params.push(`%${String(search)}%`);
    clauses.push(
      `(name ILIKE $${params.length} OR category ILIKE $${params.length} OR local_id ILIKE $${params.length} OR owner_id ILIKE $${params.length})`
    );
  }
  if (from) {
    params.push(String(from));
    clauses.push(`date >= $${params.length}`);
  }
  if (to) {
    params.push(String(to));
    clauses.push(`date <= $${params.length}`);
  }

  const safePage = Math.max(1, Number(page) || 1);
  const safePageSize = Math.min(500, Math.max(1, Number(pageSize) || 50));
  const offset = (safePage - 1) * safePageSize;

  const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
  params.push(safePageSize, offset);

  const result = await getPool().query(
    `SELECT *, COUNT(*) OVER() AS total_count
     FROM expenses
     ${where}
     ORDER BY date DESC, created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return {
    expenses: result.rows.map(toExpenseJson),
    total: Number(result.rows[0]?.total_count || 0),
    page: safePage,
    pageSize: safePageSize,
  };
}

async function getAdminOverview() {
  const db = getPool();
  const totals = await db.query(
    `SELECT COUNT(DISTINCT owner_id)::int AS owners,
            COUNT(*)::int AS expenses,
            COALESCE(SUM(amount), 0)::bigint AS total_amount,
            COALESCE(SUM(amount) FILTER (WHERE created_at >= now() - interval '30 days'), 0)::bigint AS total_amount_30d,
            MAX(date) AS last_expense_date
     FROM expenses`
  );
  const categories = await db.query(
    `SELECT category,
            COUNT(*)::int AS count,
            COALESCE(SUM(amount), 0)::bigint AS total
     FROM expenses
     GROUP BY category
     ORDER BY total DESC`
  );
  const daily = await db.query(
    `SELECT date,
            COUNT(*)::int AS count,
            COALESCE(SUM(amount), 0)::bigint AS total
     FROM expenses
     WHERE date >= to_char(now() - interval '13 days', 'YYYY-MM-DD')
     GROUP BY date
     ORDER BY date ASC`
  );

  const totalsRow = totals.rows[0] || {};
  return {
    totals: {
      owners: Number(totalsRow.owners || 0),
      expenses: Number(totalsRow.expenses || 0),
      totalAmount: Number(totalsRow.total_amount || 0),
      totalAmount30d: Number(totalsRow.total_amount_30d || 0),
      lastExpenseDate: totalsRow.last_expense_date || null,
    },
    categories: categories.rows.map((row) => ({
      category: row.category,
      count: Number(row.count),
      total: Number(row.total),
    })),
    daily: daily.rows.map((row) => ({
      date: row.date,
      count: Number(row.count),
      total: Number(row.total),
    })),
  };
}

async function recordAiProviderEvent({ ownerId, provider, status, durationMs, error }) {
  await ensureSchema();
  await getPool().query(
    `INSERT INTO ai_provider_events (owner_id, provider, status, duration_ms, error)
     VALUES ($1, $2, $3, $4, $5)`,
    [
      ownerId ? String(ownerId) : null,
      String(provider),
      String(status),
      Number.isFinite(Number(durationMs)) ? Math.round(Number(durationMs)) : null,
      error ? String(error).slice(0, 500) : null,
    ]
  );
}

async function getAiProviderStats() {
  const db = getPool();
  const providers = await db.query(
    `SELECT provider,
            status,
            COUNT(*)::int AS count,
            ROUND(AVG(duration_ms))::int AS avg_duration_ms
     FROM ai_provider_events
     WHERE created_at >= now() - interval '7 days'
     GROUP BY provider, status
     ORDER BY provider ASC, status ASC`
  );
  const recent = await db.query(
    `SELECT provider, status, duration_ms, error, created_at
     FROM ai_provider_events
     ORDER BY created_at DESC
     LIMIT 25`
  );
  return { providers: providers.rows, recent: recent.rows };
}

module.exports = {
  connectDB,
  deleteAllExpenses,
  deleteExpenseByLocalId,
  ensureSchema,
  getAdminOverview,
  getAiProviderStats,
  getExpenseByLocalId,
  getPool,
  insertAdminAudit,
  listAdminAuditLogs,
  listAdminExpenses,
  listExpenseOwners,
  listExpenses,
  listRecentExpensesForContext,
  loadNotificationReferenceItems,
  loadNotificationSummary,
  recordAiProviderEvent,
  setPool,
  sslFromDatabaseUrl,
  toExpenseJson,
  updateExpenseByLocalId,
  upsertExpense,
  upsertNotificationReference,
};

