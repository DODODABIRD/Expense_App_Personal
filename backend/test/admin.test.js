const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { setPool } = require("../api/db");

const assetRoot = fs.mkdtempSync(path.join(os.tmpdir(), "unmurce-assets-"));
const backupRoot = fs.mkdtempSync(path.join(os.tmpdir(), "unmurce-backups-"));

process.env.ADMIN_SECRET = "test-secret";
process.env.ADMIN_FIREBASE_UIDS = "";
process.env.ADMIN_ASSET_ROOT = assetRoot;
process.env.ADMIN_BACKUP_ROOT = backupRoot;

const { createApp } = require("../api/index");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function cookieFrom(res) {
  const raw = res.headers.getSetCookie
    ? res.headers.getSetCookie()
    : [res.headers.get("set-cookie")];
  return raw
    .filter(Boolean)
    .map((value) => value.split(";")[0])
    .find((value) => value.startsWith("dodo_session="));
}

test("Admin panel: auth, asset CRUD, data endpoints", async (t) => {
  const auditRows = [];
  const mockPool = {
    async query(sql, params = []) {
      const trimmed = sql.trim();

      if (trimmed.startsWith("CREATE") || trimmed.startsWith("ALTER")) {
        return { rows: [] };
      }

      if (trimmed.startsWith("INSERT INTO admin_audit_log")) {
        auditRows.push({
          id: auditRows.length + 1,
          actor: params[0],
          action: params[1],
          target: params[2],
          detail: JSON.parse(params[3]),
          ip: params[4],
          created_at: new Date(),
        });
        return { rows: [] };
      }

      if (trimmed.startsWith("SELECT * FROM admin_audit_log")) {
        return { rows: auditRows.slice().reverse().slice(0, params[0]) };
      }

      if (trimmed.includes("COUNT(DISTINCT owner_id)")) {
        return {
          rows: [
            {
              owners: 2,
              expenses: 3,
              total_amount: "150000",
              total_amount_30d: "50000",
              last_expense_date: "2026-11-01",
            },
          ],
        };
      }

      if (trimmed.startsWith("SELECT category")) {
        return { rows: [{ category: "makanan", count: 2, total: "100000" }] };
      }

      if (trimmed.startsWith("SELECT date")) {
        return { rows: [{ date: "2026-11-01", count: 1, total: "50000" }] };
      }

      if (trimmed.startsWith("SELECT *, COUNT(*) OVER()")) {
        return {
          rows: [
            {
              owner_id: "owner-1",
              local_id: "loc-1",
              name: "Kopi",
              amount: 15000,
              category: "makanan",
              type: "expected",
              date: "2026-11-01",
              created_at: new Date("2026-11-01T10:00:00Z"),
              updated_at: new Date("2026-11-01T10:00:00Z"),
              total_count: 1,
            },
          ],
        };
      }

      return { rows: [] };
    },
  };

  setPool(mockPool);

  fs.writeFileSync(path.join(assetRoot, "logo.png"), Buffer.from("original-logo"));
  fs.mkdirSync(path.join(assetRoot, "nested"), { recursive: true });
  fs.writeFileSync(path.join(assetRoot, "nested", "docs.md"), Buffer.from("# docs"));

  let server;
  let baseUrl;

  await new Promise((resolve) => {
    server = createApp().listen(0, () => {
      baseUrl = `http://127.0.0.1:${server.address().port}`;
      resolve();
    });
  });

  t.after(() => {
    server.close();
    fs.rmSync(assetRoot, { recursive: true, force: true });
    fs.rmSync(backupRoot, { recursive: true, force: true });
  });

  await t.test("redirects unauthenticated page requests to the login page", async () => {
    const res = await fetch(`${baseUrl}/dodo`, { redirect: "manual" });
    assert.equal(res.status, 302);
    assert.equal(res.headers.get("location"), "/dodo/login");
  });

  await t.test("rejects unauthenticated API calls", async () => {
    const res = await fetch(`${baseUrl}/dodo/api/assets`);
    assert.equal(res.status, 401);
    const data = await res.json();
    assert.equal(data.error, "Not authenticated");
  });

  await t.test("serves the login page and static assets without a session", async () => {
    const page = await fetch(`${baseUrl}/dodo/login`);
    assert.equal(page.status, 200);
    const html = await page.text();
    assert.ok(html.includes("Unmurce Admin"));

    const css = await fetch(`${baseUrl}/dodo/static/admin.css`);
    assert.equal(css.status, 200);
  });

  await t.test("rejects a wrong secret", async () => {
    const res = await fetch(`${baseUrl}/dodo/api/login-secret`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ secret: "wrong" }),
    });
    assert.equal(res.status, 401);
    const data = await res.json();
    assert.equal(data.success, false);
  });

  let sessionCookie;

  await t.test("accepts the configured secret and sets a session cookie", async () => {
    const res = await fetch(`${baseUrl}/dodo/api/login-secret`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ secret: "test-secret" }),
    });
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.success, true);
    sessionCookie = cookieFrom(res);
    assert.ok(sessionCookie, "expected a dodo_session cookie");
  });

  await t.test("lists assets recursively once authenticated", async () => {
    const res = await fetch(`${baseUrl}/dodo/api/assets`, {
      headers: { Cookie: sessionCookie },
    });
    assert.equal(res.status, 200);
    const data = await res.json();
    const paths = data.assets.map((asset) => asset.path).sort();
    assert.deepEqual(paths, ["logo.png", "nested/docs.md"]);
    const logo = data.assets.find((asset) => asset.path === "logo.png");
    assert.equal(logo.preview, true);
    assert.equal(logo.replaceable, true);
  });

  await t.test("uploads a new asset", async () => {
    const res = await fetch(
      `${baseUrl}/dodo/api/assets/upload?file=${encodeURIComponent("nested/new.json")}`,
      {
        method: "POST",
        headers: { Cookie: sessionCookie, "Content-Type": "application/octet-stream" },
        body: Buffer.from('{"ok":true}'),
      }
    );
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.success, true);
    assert.equal(fs.readFileSync(path.join(assetRoot, "nested", "new.json"), "utf8"), '{"ok":true}');
  });

  await t.test("refuses to overwrite an existing asset through upload", async () => {
    const res = await fetch(
      `${baseUrl}/dodo/api/assets/upload?file=${encodeURIComponent("nested/new.json")}`,
      {
        method: "POST",
        headers: { Cookie: sessionCookie, "Content-Type": "application/octet-stream" },
        body: Buffer.from("{}"),
      }
    );
    assert.equal(res.status, 409);
  });

  await t.test("blocks path traversal and unsupported extensions", async () => {
    const traversal = await fetch(
      `${baseUrl}/dodo/api/assets/upload?file=${encodeURIComponent("../escape.png")}`,
      {
        method: "POST",
        headers: { Cookie: sessionCookie, "Content-Type": "application/octet-stream" },
        body: Buffer.from("x"),
      }
    );
    assert.equal(traversal.status, 400);

    const unsupported = await fetch(
      `${baseUrl}/dodo/api/assets/upload?file=${encodeURIComponent("script.sh")}`,
      {
        method: "POST",
        headers: { Cookie: sessionCookie, "Content-Type": "application/octet-stream" },
        body: Buffer.from("x"),
      }
    );
    assert.equal(unsupported.status, 400);

    const hidden = await fetch(
      `${baseUrl}/dodo/api/assets/upload?file=${encodeURIComponent(".hidden.png")}`,
      {
        method: "POST",
        headers: { Cookie: sessionCookie, "Content-Type": "application/octet-stream" },
        body: Buffer.from("x"),
      }
    );
    assert.equal(hidden.status, 400);
  });

  await t.test("creates a backup when replacing and can restore it", async () => {
    const replace = await fetch(
      `${baseUrl}/dodo/api/assets/replace?file=${encodeURIComponent("logo.png")}`,
      {
        method: "POST",
        headers: { Cookie: sessionCookie, "Content-Type": "application/octet-stream" },
        body: Buffer.from("updated-logo"),
      }
    );
    assert.equal(replace.status, 200);
    assert.equal(fs.readFileSync(path.join(assetRoot, "logo.png"), "utf8"), "updated-logo");

    const backupsRes = await fetch(
      `${baseUrl}/dodo/api/assets/backups?file=${encodeURIComponent("logo.png")}`,
      { headers: { Cookie: sessionCookie } }
    );
    assert.equal(backupsRes.status, 200);
    const backups = (await backupsRes.json()).backups;
    assert.equal(backups.length, 1);

    const restore = await fetch(`${baseUrl}/dodo/api/assets/restore`, {
      method: "POST",
      headers: { Cookie: sessionCookie, "Content-Type": "application/json" },
      body: JSON.stringify({ file: "logo.png", backup: backups[0].id }),
    });
    assert.equal(restore.status, 200);
    assert.equal(fs.readFileSync(path.join(assetRoot, "logo.png"), "utf8"), "original-logo");
  });

  await t.test("deletes an asset and keeps a backup for restore", async () => {
    const del = await fetch(
      `${baseUrl}/dodo/api/assets?file=${encodeURIComponent("nested/docs.md")}`,
      { method: "DELETE", headers: { Cookie: sessionCookie } }
    );
    assert.equal(del.status, 200);
    assert.equal(fs.existsSync(path.join(assetRoot, "nested", "docs.md")), false);

    const backupsRes = await fetch(
      `${baseUrl}/dodo/api/assets/backups?file=${encodeURIComponent("nested/docs.md")}`,
      { headers: { Cookie: sessionCookie } }
    );
    const backups = (await backupsRes.json()).backups;
    assert.equal(backups.length, 1);

    const restore = await fetch(`${baseUrl}/dodo/api/assets/restore`, {
      method: "POST",
      headers: { Cookie: sessionCookie, "Content-Type": "application/json" },
      body: JSON.stringify({ file: "nested/docs.md", backup: backups[0].id }),
    });
    assert.equal(restore.status, 200);
    assert.equal(fs.readFileSync(path.join(assetRoot, "nested", "docs.md"), "utf8"), "# docs");
  });

  await t.test("keeps five backups per asset without touching other assets", async () => {
    const replace = async (file, body) => {
      const res = await fetch(
        `${baseUrl}/dodo/api/assets/replace?file=${encodeURIComponent(file)}`,
        {
          method: "POST",
          headers: { Cookie: sessionCookie, "Content-Type": "application/octet-stream" },
          body: Buffer.from(body),
        }
      );
      assert.equal(res.status, 200);
    };

    const backupsFor = async (file) => {
      const res = await fetch(
        `${baseUrl}/dodo/api/assets/backups?file=${encodeURIComponent(file)}`,
        { headers: { Cookie: sessionCookie } }
      );
      assert.equal(res.status, 200);
      return (await res.json()).backups;
    };

    await replace("nested/new.json", '{"version":1}');
    assert.equal((await backupsFor("nested/new.json")).length, 1);

    for (let i = 0; i < 6; i += 1) {
      await replace("logo.png", `logo-v${i}`);
    }

    const logoBackups = await backupsFor("logo.png");
    assert.equal(logoBackups.length, 5);
    assert.equal(new Set(logoBackups.map((backup) => backup.id)).size, 5);

    const otherBackups = await backupsFor("nested/new.json");
    assert.equal(otherBackups.length, 1);

    assert.equal(fs.statSync(path.join(backupRoot, "logo.png")).isDirectory(), true);
    assert.equal(fs.readdirSync(path.join(backupRoot, "logo.png")).length, 5);
  });

  await t.test("reports aggregate overview data", async () => {
    const res = await fetch(`${baseUrl}/dodo/api/overview`, {
      headers: { Cookie: sessionCookie },
    });
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.totals.totalAmount, 150000);
    assert.equal(data.totals.owners, 2);
    assert.equal(data.categories[0].category, "makanan");
  });

  await t.test("browses expenses and exports CSV", async () => {
    const res = await fetch(`${baseUrl}/dodo/api/expenses?page=1&pageSize=50`, {
      headers: { Cookie: sessionCookie },
    });
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.total, 1);
    assert.equal(data.expenses[0].name, "Kopi");

    const csv = await fetch(`${baseUrl}/dodo/api/expenses/export.csv`, {
      headers: { Cookie: sessionCookie },
    });
    assert.equal(csv.status, 200);
    assert.match(csv.headers.get("content-type"), /text\/csv/);
    const body = await csv.text();
    assert.ok(body.startsWith("owner_id,local_id,name,amount,category,type,date"));
    assert.ok(body.includes("Kopi"));
  });

  await t.test("writes an audit entry for each asset mutation", async () => {
    let logs = [];
    for (let attempt = 0; attempt < 20; attempt += 1) {
      const res = await fetch(`${baseUrl}/dodo/api/audit`, {
        headers: { Cookie: sessionCookie },
      });
      assert.equal(res.status, 200);
      logs = (await res.json()).logs;
      if (logs.some((log) => log.action === "asset_uploaded")) break;
      await sleep(25);
    }

    const actions = logs.map((log) => log.action);
    assert.ok(actions.includes("login_success"));
    assert.ok(actions.includes("asset_uploaded"));
    assert.ok(actions.includes("asset_replaced"));
    assert.ok(actions.includes("asset_deleted"));
    assert.ok(actions.includes("asset_restored"));
  });

  await t.test("invalidates the session on logout", async () => {
    const logout = await fetch(`${baseUrl}/dodo/api/logout`, {
      method: "POST",
      headers: { Cookie: sessionCookie },
    });
    assert.equal(logout.status, 200);

    const res = await fetch(`${baseUrl}/dodo/api/assets`, {
      headers: { Cookie: sessionCookie },
    });
    assert.equal(res.status, 401);
  });
});

test("Secret login is disabled when ADMIN_SECRET is not configured", async (t) => {
  const previousSecret = process.env.ADMIN_SECRET;
  process.env.ADMIN_SECRET = "";

  // adminLogin reads ADMIN_SECRET at module load, so exercise the helper logic
  // through a fresh module instance.
  const modulePath = require.resolve("../api/routes/adminLogin");
  delete require.cache[modulePath];
  const { router } = require(modulePath);

  const express = require("express");
  const app = express();
  app.use(express.json());
  app.use("/dodo", router);

  const server = await new Promise((resolve) => {
    const instance = app.listen(0, () => resolve(instance));
  });
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  t.after(() => server.close());

  const res = await fetch(`${baseUrl}/dodo/api/login-secret`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ secret: "anything" }),
  });
  assert.equal(res.status, 503);
  const data = await res.json();
  assert.equal(data.success, false);

  process.env.ADMIN_SECRET = previousSecret;
});
