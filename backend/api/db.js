const { Pool } = require("pg");

// Static requires keep the seeds inside the serverless bundle. The database is
// the source of truth after the first read; these files are only the seed.
const PORTFOLIO_SEED = require("../content/portfolio.json");
const RAG_KNOWLEDGE_SEED = require("../public/asset/rag_knowledge.json");

let pool = null;
let schemaReady = false;
let downloadsSeeded = false;

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
    CREATE TABLE IF NOT EXISTS portfolio_content (
      key TEXT PRIMARY KEY,
      data JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS rag_knowledge (
      key TEXT PRIMARY KEY,
      data JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS rag_chat_events (
      id BIGSERIAL PRIMARY KEY,
      question TEXT NOT NULL,
      answer TEXT,
      provider TEXT NOT NULL,
      latency_ms INTEGER,
      interested BOOLEAN NOT NULL DEFAULT false,
      answered BOOLEAN NOT NULL DEFAULT false,
      feedback TEXT,
      feedback_at TIMESTAMPTZ,
      resolved_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS rag_chat_events_created_at_idx
      ON rag_chat_events (created_at DESC);
    CREATE INDEX IF NOT EXISTS rag_chat_events_feedback_idx
      ON rag_chat_events (feedback);
    CREATE TABLE IF NOT EXISTS device_syncs (
      owner_id TEXT NOT NULL,
      device_id TEXT NOT NULL,
      device_name TEXT,
      platform TEXT,
      app_version TEXT,
      expense_count INTEGER,
      last_sync_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (owner_id, device_id)
    );
    CREATE INDEX IF NOT EXISTS device_syncs_last_sync_idx
      ON device_syncs (last_sync_at DESC);
    CREATE TABLE IF NOT EXISTS download_apps (
      slug TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      tagline TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL DEFAULT '',
      icon_url TEXT NOT NULL DEFAULT '',
      accent TEXT NOT NULL DEFAULT '',
      sort_order INTEGER NOT NULL DEFAULT 0,
      active BOOLEAN NOT NULL DEFAULT true,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS download_releases (
      id BIGSERIAL PRIMARY KEY,
      app_slug TEXT NOT NULL REFERENCES download_apps (slug) ON DELETE CASCADE,
      version TEXT NOT NULL,
      url TEXT NOT NULL,
      size_bytes BIGINT NOT NULL DEFAULT 0,
      released_at DATE,
      notes TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (app_slug, version)
    );
    CREATE INDEX IF NOT EXISTS download_releases_app_idx
      ON download_releases (app_slug, released_at DESC, id DESC);
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

async function loadNotificationReference(ownerId) {
  const result = await getPool().query(
    `SELECT items, summary, updated_at FROM ai_notification_references WHERE owner_id = $1`,
    [ownerId]
  );
  return result.rows[0] || null;
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
  downloadsSeeded = false;
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
  const monthly = await db.query(
    `SELECT substring(date, 1, 7) AS month,
            COUNT(*)::int AS count,
            COALESCE(SUM(amount), 0)::bigint AS total
     FROM expenses
     WHERE substring(date, 1, 7) >= to_char(now() - interval '12 months', 'YYYY-MM')
     GROUP BY month
     ORDER BY month ASC`
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
    monthly: monthly.rows.map((row) => ({
      month: row.month,
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

async function getPortfolioContent() {
  await ensureSchema();
  const result = await getPool().query(
    `SELECT data FROM portfolio_content WHERE key = 'main'`
  );
  if (result.rows[0]?.data) return result.rows[0].data;

  await savePortfolioContent(PORTFOLIO_SEED);
  return PORTFOLIO_SEED;
}

async function savePortfolioContent(data) {
  await ensureSchema();
  await getPool().query(
    `INSERT INTO portfolio_content (key, data, updated_at)
     VALUES ('main', $1::jsonb, now())
     ON CONFLICT (key) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
    [JSON.stringify(data)]
  );
  return data;
}

async function getRagKnowledge() {
  await ensureSchema();
  const result = await getPool().query(
    `SELECT data FROM rag_knowledge WHERE key = 'main'`
  );
  if (result.rows[0]?.data) return result.rows[0].data;

  await saveRagKnowledge(RAG_KNOWLEDGE_SEED);
  return RAG_KNOWLEDGE_SEED;
}

async function saveRagKnowledge(data) {
  await ensureSchema();
  await getPool().query(
    `INSERT INTO rag_knowledge (key, data, updated_at)
     VALUES ('main', $1::jsonb, now())
     ON CONFLICT (key) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
    [JSON.stringify(data)]
  );
  return data;
}

async function recordRagChatEvent({
  question,
  answer,
  provider,
  latencyMs,
  interested,
  answered,
}) {
  await ensureSchema();
  const result = await getPool().query(
    `INSERT INTO rag_chat_events
       (question, answer, provider, latency_ms, interested, answered)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id`,
    [
      String(question).slice(0, 1000),
      answer ? String(answer).slice(0, 4000) : null,
      String(provider || "local"),
      Number.isFinite(Number(latencyMs)) ? Math.round(Number(latencyMs)) : null,
      Boolean(interested),
      Boolean(answered),
    ]
  );
  return Number(result.rows[0]?.id) || null;
}

async function updateRagFeedback(id, vote) {
  await ensureSchema();
  const result = await getPool().query(
    `UPDATE rag_chat_events
     SET feedback = $2, feedback_at = now()
     WHERE id = $1
     RETURNING id, feedback`,
    [Number(id), String(vote)]
  );
  return result.rows[0] || null;
}

function toRagEventJson(row) {
  return {
    id: Number(row.id),
    question: row.question,
    answer: row.answer,
    provider: row.provider,
    latencyMs: row.latency_ms === null ? null : Number(row.latency_ms),
    interested: Boolean(row.interested),
    answered: Boolean(row.answered),
    feedback: row.feedback || null,
    resolvedAt: row.resolved_at,
    createdAt: row.created_at,
  };
}

async function listRagEvents({ limit, feedback, unanswered } = {}) {
  await ensureSchema();
  const clauses = [];
  const params = [];

  if (feedback) {
    params.push(String(feedback));
    clauses.push(`feedback = $${params.length}`);
  }
  if (unanswered) {
    clauses.push(`(answered = false OR feedback = 'down') AND resolved_at IS NULL`);
  }

  params.push(Math.min(500, Math.max(1, Number(limit) || 100)));
  const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
  const result = await getPool().query(
    `SELECT id, question, answer, provider, latency_ms, interested, answered,
            feedback, resolved_at, created_at
     FROM rag_chat_events
     ${where}
     ORDER BY created_at DESC, id DESC
     LIMIT $${params.length}`,
    params
  );
  return result.rows.map(toRagEventJson);
}

async function getRagStats() {
  await ensureSchema();
  const stats = await getPool().query(
    `SELECT COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE created_at >= now() - interval '7 days')::int AS total_7d,
            COUNT(*) FILTER (WHERE feedback = 'up')::int AS up,
            COUNT(*) FILTER (WHERE feedback = 'down')::int AS down,
            COUNT(*) FILTER (
              WHERE (answered = false OR feedback = 'down') AND resolved_at IS NULL
            )::int AS unanswered,
            ROUND(AVG(latency_ms))::int AS avg_latency_ms
     FROM rag_chat_events`
  );
  const providers = await getPool().query(
    `SELECT provider,
            COUNT(*)::int AS count,
            ROUND(AVG(latency_ms))::int AS avg_latency_ms
     FROM rag_chat_events
     GROUP BY provider
     ORDER BY count DESC`
  );

  const row = stats.rows[0] || {};
  return {
    totals: {
      total: Number(row.total || 0),
      total7d: Number(row.total_7d || 0),
      up: Number(row.up || 0),
      down: Number(row.down || 0),
      unanswered: Number(row.unanswered || 0),
      avgLatencyMs: row.avg_latency_ms === null ? null : Number(row.avg_latency_ms),
    },
    providers: providers.rows.map((item) => ({
      provider: item.provider,
      count: Number(item.count),
      avgLatencyMs:
        item.avg_latency_ms === null ? null : Number(item.avg_latency_ms),
    })),
  };
}

async function resolveRagEvent(id) {
  await ensureSchema();
  const result = await getPool().query(
    `UPDATE rag_chat_events
     SET resolved_at = now()
     WHERE id = $1
     RETURNING id`,
    [Number(id)]
  );
  return Boolean(result.rows[0]);
}

async function getMonthlyTrend() {
  const result = await getPool().query(
    `SELECT substring(date, 1, 7) AS month,
            COUNT(*)::int AS count,
            COALESCE(SUM(amount), 0)::bigint AS total
     FROM expenses
     WHERE substring(date, 1, 7) >= to_char(now() - interval '12 months', 'YYYY-MM')
     GROUP BY month
     ORDER BY month ASC`
  );
  return result.rows.map((row) => ({
    month: row.month,
    count: Number(row.count),
    total: Number(row.total),
  }));
}

async function upsertDeviceSync(ownerId, {
  deviceId,
  deviceName,
  platform,
  appVersion,
  expenseCount,
} = {}) {
  await ensureSchema();
  const result = await getPool().query(
    `INSERT INTO device_syncs
       (owner_id, device_id, device_name, platform, app_version, expense_count, last_sync_at)
     VALUES ($1, $2, $3, $4, $5, $6, now())
     ON CONFLICT (owner_id, device_id) DO UPDATE SET
       device_name = COALESCE(EXCLUDED.device_name, device_syncs.device_name),
       platform = COALESCE(EXCLUDED.platform, device_syncs.platform),
       app_version = COALESCE(EXCLUDED.app_version, device_syncs.app_version),
       expense_count = COALESCE(EXCLUDED.expense_count, device_syncs.expense_count),
       last_sync_at = now()
     RETURNING *`,
    [
      String(ownerId),
      String(deviceId),
      deviceName ? String(deviceName).slice(0, 200) : null,
      platform ? String(platform).slice(0, 100) : null,
      appVersion ? String(appVersion).slice(0, 50) : null,
      Number.isFinite(Number(expenseCount)) ? Math.round(Number(expenseCount)) : null,
    ]
  );
  return result.rows[0] || null;
}

async function listDeviceSyncs(ownerId) {
  await ensureSchema();
  const params = [];
  let where = "";
  if (ownerId) {
    params.push(String(ownerId));
    where = `WHERE owner_id = $${params.length}`;
  }
  const result = await getPool().query(
    `SELECT * FROM device_syncs
     ${where}
     ORDER BY last_sync_at DESC
     LIMIT 500`,
    params
  );
  return result.rows.map((row) => ({
    ownerId: row.owner_id,
    deviceId: row.device_id,
    deviceName: row.device_name,
    platform: row.platform,
    appVersion: row.app_version,
    expenseCount: row.expense_count === null ? null : Number(row.expense_count),
    lastSyncAt: row.last_sync_at,
  }));
}

function parseVersion(version) {
  const raw = String(version || "").trim().replace(/^v/i, "");
  const match = raw.match(/^(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.-]+))?$/);
  if (!match) return null;
  return {
    numbers: match[1].split(".").map(Number),
    prerelease: match[2] || "",
  };
}

function compareVersions(left, right) {
  const a = parseVersion(left);
  const b = parseVersion(right);
  if (!a || !b) return 0;

  const length = Math.max(a.numbers.length, b.numbers.length);
  for (let index = 0; index < length; index += 1) {
    const diff = (a.numbers[index] || 0) - (b.numbers[index] || 0);
    if (diff !== 0) return diff;
  }

  if (a.prerelease === b.prerelease) return 0;
  if (!a.prerelease) return 1;
  if (!b.prerelease) return -1;
  return a.prerelease.localeCompare(b.prerelease);
}

function releaseTimestamp(release) {
  if (!release?.released_at) return 0;
  const parsed = Date.parse(release.released_at);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function sortReleasesDesc(releases) {
  return releases.slice().sort((left, right) => {
    const byVersion = compareVersions(right.version, left.version);
    if (byVersion !== 0) return byVersion;
    const byDate = releaseTimestamp(right) - releaseTimestamp(left);
    if (byDate !== 0) return byDate;
    return Number(right.id) - Number(left.id);
  });
}

function pickLatestRelease(releases) {
  if (!releases.length) return null;
  return releases.slice().sort((left, right) => {
    const byVersion = compareVersions(left.version, right.version);
    if (byVersion !== 0) return byVersion;
    const byDate = releaseTimestamp(left) - releaseTimestamp(right);
    if (byDate !== 0) return byDate;
    return Number(left.id) - Number(right.id);
  }).pop();
}

function toDownloadAppJson(row) {
  return {
    slug: row.slug,
    name: row.name,
    tagline: row.tagline || "",
    description: row.description || "",
    icon_url: row.icon_url || "",
    accent: row.accent || "",
    sort_order: Number(row.sort_order) || 0,
    active: row.active !== false,
  };
}

function toDownloadReleaseJson(row) {
  let releasedAt = row.released_at;
  if (releasedAt instanceof Date) {
    releasedAt = releasedAt.toISOString().slice(0, 10);
  } else if (releasedAt) {
    releasedAt = String(releasedAt).slice(0, 10);
  } else {
    releasedAt = null;
  }

  return {
    id: Number(row.id),
    app_slug: row.app_slug,
    version: row.version,
    url: row.url,
    size_bytes: row.size_bytes === null ? 0 : Number(row.size_bytes),
    released_at: releasedAt,
    notes: row.notes || "",
  };
}

async function ensureDownloadSeed() {
  if (downloadsSeeded) return;
  await ensureSchema();

  const existing = await getPool().query(
    `SELECT slug FROM download_apps LIMIT 1`
  );
  if (existing.rows.length === 0) {
    const content = await getPortfolioContent();
    const featured = content.featured || {};

    await getPool().query(
      `INSERT INTO download_apps (slug, name, tagline, icon_url, accent, sort_order)
       VALUES ('unmurce', $1, $2, '/asset/unmurce/unmurce-app-icon.png', 'yellow', 0)
       ON CONFLICT (slug) DO NOTHING`,
      [featured.name || "Unmurce Expense Tracker", featured.description || ""]
    );

    const apk = content.apk || {};
    if (apk.url) {
      await getPool().query(
        `INSERT INTO download_releases (app_slug, version, url, size_bytes, released_at, notes)
         VALUES ('unmurce', $1, $2, $3, $4, $5)
         ON CONFLICT (app_slug, version) DO NOTHING`,
        [
          String(apk.version || "1.0.0").replace(/^v/i, ""),
          apk.url,
          Number.isFinite(Number(apk.size_bytes)) ? Math.round(Number(apk.size_bytes)) : 0,
          apk.released_at || null,
          apk.notes || "",
        ]
      );
    }
  }

  downloadsSeeded = true;
}

async function listDownloadApps({ includeInactive = false } = {}) {
  await ensureDownloadSeed();

  const appResult = await getPool().query(
    `SELECT * FROM download_apps
     ${includeInactive ? "" : "WHERE active = true"}
     ORDER BY sort_order ASC, name ASC`
  );
  const releaseResult = await getPool().query(
    `SELECT id, app_slug, version, url, size_bytes,
            released_at::text AS released_at, notes, created_at, updated_at
     FROM download_releases
     ORDER BY id ASC`
  );

  const releasesByApp = new Map();
  for (const row of releaseResult.rows) {
    if (!releasesByApp.has(row.app_slug)) releasesByApp.set(row.app_slug, []);
    releasesByApp.get(row.app_slug).push(toDownloadReleaseJson(row));
  }

  return appResult.rows.map((row) => {
    const releases = sortReleasesDesc(releasesByApp.get(row.slug) || []);
    return {
      ...toDownloadAppJson(row),
      latest: pickLatestRelease(releases),
      releases,
    };
  });
}

async function getDownloadApp(slug, { includeInactive = false } = {}) {
  const apps = await listDownloadApps({ includeInactive });
  return apps.find((app) => app.slug === slug) || null;
}

async function createDownloadApp(fields) {
  await ensureSchema();
  const result = await getPool().query(
    `INSERT INTO download_apps
       (slug, name, tagline, description, icon_url, accent, sort_order, active)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING *`,
    [
      fields.slug,
      fields.name,
      fields.tagline || "",
      fields.description || "",
      fields.icon_url || "",
      fields.accent || "",
      Number(fields.sort_order) || 0,
      fields.active !== false,
    ]
  );
  return { ...toDownloadAppJson(result.rows[0]), latest: null, releases: [] };
}

async function updateDownloadApp(slug, fields) {
  await ensureSchema();
  const result = await getPool().query(
    `UPDATE download_apps
     SET name = $2,
         tagline = $3,
         description = $4,
         icon_url = $5,
         accent = $6,
         sort_order = $7,
         active = $8,
         updated_at = now()
     WHERE slug = $1
     RETURNING *`,
    [
      slug,
      fields.name,
      fields.tagline || "",
      fields.description || "",
      fields.icon_url || "",
      fields.accent || "",
      Number(fields.sort_order) || 0,
      fields.active !== false,
    ]
  );
  return result.rows[0] ? toDownloadAppJson(result.rows[0]) : null;
}

async function deleteDownloadApp(slug) {
  await ensureSchema();
  const result = await getPool().query(
    `DELETE FROM download_apps WHERE slug = $1 RETURNING slug`,
    [slug]
  );
  return Boolean(result.rows[0]);
}

async function createDownloadRelease(appSlug, fields) {
  await ensureSchema();
  const result = await getPool().query(
    `INSERT INTO download_releases
       (app_slug, version, url, size_bytes, released_at, notes)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, app_slug, version, url, size_bytes,
               released_at::text AS released_at, notes, created_at, updated_at`,
    [
      appSlug,
      fields.version,
      fields.url,
      Number(fields.size_bytes) || 0,
      fields.released_at || null,
      fields.notes || "",
    ]
  );
  return toDownloadReleaseJson(result.rows[0]);
}

async function updateDownloadRelease(id, fields) {
  await ensureSchema();
  const result = await getPool().query(
    `UPDATE download_releases
     SET version = $2,
         url = $3,
         size_bytes = $4,
         released_at = $5,
         notes = $6,
         updated_at = now()
     WHERE id = $1
     RETURNING id, app_slug, version, url, size_bytes,
               released_at::text AS released_at, notes, created_at, updated_at`,
    [
      Number(id),
      fields.version,
      fields.url,
      Number(fields.size_bytes) || 0,
      fields.released_at || null,
      fields.notes || "",
    ]
  );
  return result.rows[0] ? toDownloadReleaseJson(result.rows[0]) : null;
}

async function deleteDownloadRelease(id) {
  await ensureSchema();
  const result = await getPool().query(
    `DELETE FROM download_releases WHERE id = $1 RETURNING app_slug`,
    [Number(id)]
  );
  return result.rows[0]?.app_slug || null;
}

module.exports = {
  compareVersions,
  connectDB,
  createDownloadApp,
  createDownloadRelease,
  deleteAllExpenses,
  deleteDownloadApp,
  deleteDownloadRelease,
  deleteExpenseByLocalId,
  ensureSchema,
  getAdminOverview,
  getAiProviderStats,
  getDownloadApp,
  getExpenseByLocalId,
  getMonthlyTrend,
  getPool,
  getPortfolioContent,
  getRagKnowledge,
  getRagStats,
  insertAdminAudit,
  listAdminAuditLogs,
  listAdminExpenses,
  listDeviceSyncs,
  listDownloadApps,
  listExpenseOwners,
  listExpenses,
  listRagEvents,
  listRecentExpensesForContext,
  loadNotificationReference,
  loadNotificationReferenceItems,
  loadNotificationSummary,
  recordAiProviderEvent,
  recordRagChatEvent,
  resolveRagEvent,
  savePortfolioContent,
  saveRagKnowledge,
  setPool,
  sslFromDatabaseUrl,
  toExpenseJson,
  updateDownloadApp,
  updateDownloadRelease,
  updateExpenseByLocalId,
  updateRagFeedback,
  upsertDeviceSync,
  upsertExpense,
  upsertNotificationReference,
};

