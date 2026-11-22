const assert = require("node:assert/strict");
const { test } = require("node:test");
const { compareVersions, setPool } = require("../api/db");
const r2 = require("../api/services/r2Service");

const R2_ENV_KEYS = [
  "R2_ENDPOINT",
  "R2_BUCKET",
  "R2_ACCESS_KEY_ID",
  "R2_SECRET_ACCESS_KEY",
  "R2_PUBLIC_BASE_URL",
];

function normalize(sql) {
  return String(sql || "").trim().replace(/\s+/g, " ");
}

function createStore() {
  return {
    portfolio: {
      featured: {
        name: "Unmurce Expense Tracker",
        description: "Private personal finance application.",
      },
      apk: {
        version: "1.7.5",
        size_bytes: 26052981,
        url: "/asset/appdownload/app-arm64-v8a-release.apk",
        released_at: "2026-10-08",
        notes: "arm64-v8a release",
      },
    },
    apps: [],
    releases: [],
    nextReleaseId: 1,
  };
}

function createPool(store) {
  return {
    async query(sql, params = []) {
      const text = normalize(sql);

      if (text.startsWith("CREATE") || text.startsWith("ALTER")) {
        return { rows: [] };
      }
      if (text.startsWith("INSERT INTO admin_audit_log")) {
        return { rows: [] };
      }
      if (text.startsWith("SELECT data FROM portfolio_content")) {
        return { rows: [{ data: store.portfolio }] };
      }
      if (text.startsWith("INSERT INTO portfolio_content")) {
        return { rows: [] };
      }

      if (text === "SELECT slug FROM download_apps LIMIT 1") {
        return { rows: store.apps.slice(0, 1).map((app) => ({ slug: app.slug })) };
      }

      if (text.startsWith("INSERT INTO download_apps") && text.includes("ON CONFLICT")) {
        const slug = "unmurce";
        if (!store.apps.some((app) => app.slug === slug)) {
          store.apps.push({
            slug,
            name: params[0],
            tagline: params[1] || "",
            description: "",
            icon_url: "/asset/unmurce/unmurce-app-icon.png",
            accent: "yellow",
            sort_order: 0,
            active: true,
          });
        }
        return { rows: [] };
      }

      if (text.startsWith("INSERT INTO download_releases") && text.includes("ON CONFLICT")) {
        const version = params[0];
        if (!store.releases.some((release) => release.version === version)) {
          store.releases.push({
            id: store.nextReleaseId++,
            app_slug: "unmurce",
            version,
            url: params[1],
            size_bytes: Number(params[2]) || 0,
            released_at: params[3] || null,
            notes: params[4] || "",
            r2_key: null,
          });
        }
        return { rows: [] };
      }

      if (text.startsWith("SELECT * FROM download_apps")) {
        let rows = store.apps.slice();
        if (text.includes("WHERE active = true")) {
          rows = rows.filter((app) => app.active);
        }
        rows.sort((left, right) => left.sort_order - right.sort_order || left.name.localeCompare(right.name));
        return { rows };
      }

      if (text.startsWith("SELECT id, app_slug, version")) {
        if (text.includes("WHERE id = $1")) {
          const found = store.releases.find((item) => item.id === Number(params[0]));
          return { rows: found ? [{ ...found }] : [] };
        }
        return {
          rows: store.releases
            .slice()
            .sort((left, right) => left.id - right.id)
            .map((release) => ({ ...release })),
        };
      }

      if (text.startsWith("SELECT 1 FROM download_releases")) {
        const hasMatch = store.releases.some(
          (item) =>
            item.app_slug === params[0] &&
            item.version === params[1] &&
            (params.length < 3 || item.id !== Number(params[2]))
        );
        return { rows: hasMatch ? [{ ok: 1 }] : [] };
      }

      if (text.startsWith("SELECT COUNT(*)::int AS count FROM download_releases")) {
        const count = store.releases.filter(
          (item) =>
            item.r2_key === params[0] &&
            (params.length < 2 || item.id !== Number(params[1]))
        ).length;
        return { rows: [{ count }] };
      }

      if (text.startsWith("SELECT DISTINCT r2_key FROM download_releases")) {
        const keys = Array.from(
          new Set(
            store.releases
              .filter((item) => item.app_slug === params[0] && item.r2_key)
              .map((item) => item.r2_key)
          )
        );
        return { rows: keys.map((r2_key) => ({ r2_key })) };
      }

      if (text.startsWith("INSERT INTO download_apps")) {
        const app = {
          slug: params[0],
          name: params[1],
          tagline: params[2],
          description: params[3],
          icon_url: params[4],
          accent: params[5],
          sort_order: Number(params[6]) || 0,
          active: params[7] !== false,
        };
        if (store.apps.some((item) => item.slug === app.slug)) {
          const error = new Error("duplicate key");
          error.code = "23505";
          throw error;
        }
        store.apps.push(app);
        return { rows: [{ ...app }] };
      }

      if (text.startsWith("UPDATE download_apps")) {
        const app = store.apps.find((item) => item.slug === params[0]);
        if (!app) return { rows: [] };
        app.name = params[1];
        app.tagline = params[2];
        app.description = params[3];
        app.icon_url = params[4];
        app.accent = params[5];
        app.sort_order = Number(params[6]) || 0;
        app.active = params[7] !== false;
        return { rows: [{ ...app }] };
      }

      if (text.startsWith("DELETE FROM download_apps")) {
        const index = store.apps.findIndex((item) => item.slug === params[0]);
        if (index === -1) return { rows: [] };
        const [app] = store.apps.splice(index, 1);
        store.releases = store.releases.filter((release) => release.app_slug !== app.slug);
        return { rows: [{ slug: app.slug }] };
      }

      if (text.startsWith("INSERT INTO download_releases")) {
        const app = store.apps.find((item) => item.slug === params[0]);
        if (!app) {
          const error = new Error("foreign key");
          error.code = "23503";
          throw error;
        }
        if (
          store.releases.some(
            (release) => release.app_slug === params[0] && release.version === params[1]
          )
        ) {
          const error = new Error("duplicate key");
          error.code = "23505";
          throw error;
        }
        const release = {
          id: store.nextReleaseId++,
          app_slug: params[0],
          version: params[1],
          url: params[2],
          size_bytes: Number(params[3]) || 0,
          released_at: params[4] || null,
          notes: params[5] || "",
          r2_key: params[6] || null,
        };
        store.releases.push(release);
        return { rows: [{ ...release }] };
      }

      if (text.startsWith("UPDATE download_releases")) {
        const release = store.releases.find((item) => item.id === Number(params[0]));
        if (!release) return { rows: [] };
        if (
          store.releases.some(
            (item) =>
              item.id !== release.id &&
              item.app_slug === release.app_slug &&
              item.version === params[1]
          )
        ) {
          const error = new Error("duplicate key");
          error.code = "23505";
          throw error;
        }
        release.version = params[1];
        release.url = params[2];
        release.size_bytes = Number(params[3]) || 0;
        release.released_at = params[4] || null;
        release.notes = params[5] || "";
        release.r2_key = params[6] || null;
        return { rows: [{ ...release }] };
      }

      if (text.startsWith("DELETE FROM download_releases")) {
        const index = store.releases.findIndex((item) => item.id === Number(params[0]));
        if (index === -1) return { rows: [] };
        const [release] = store.releases.splice(index, 1);
        return {
          rows: [
            {
              app_slug: release.app_slug,
              version: release.version,
              r2_key: release.r2_key || null,
            },
          ],
        };
      }

      return { rows: [] };
    },
  };
}

test("compareVersions ranks numeric versions correctly", () => {
  assert.ok(compareVersions("1.10.0", "1.9.0") > 0);
  assert.ok(compareVersions("2.0", "1.99.99") > 0);
  assert.equal(compareVersions("1.8.0", "v1.8.0"), 0);
  assert.ok(compareVersions("1.8.0", "1.8.0-beta") > 0);
  assert.ok(compareVersions("1.8.0-beta", "1.8.0") < 0);
  assert.equal(compareVersions("build-a", "build-b"), 0);
});

test("Downloads seed, admin CRUD and latest-version selection", async (t) => {
  const store = createStore();
  setPool(createPool(store));

  const savedR2Env = {};
  for (const key of R2_ENV_KEYS) {
    savedR2Env[key] = process.env[key];
    process.env[key] = "";
  }

  process.env.ADMIN_SECRET = "downloads-secret";
  process.env.ADMIN_FIREBASE_UIDS = "";
  process.env.GROQ_API_KEY = "";

  const { createApp } = require("../api/index");
  for (const key of R2_ENV_KEYS) {
    process.env[key] = "";
  }

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
    r2.setR2Client(null);
    for (const key of R2_ENV_KEYS) {
      if (savedR2Env[key] === undefined) delete process.env[key];
      else process.env[key] = savedR2Env[key];
    }
  });

  const login = await fetch(`${baseUrl}/dodo/api/login-secret`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ secret: "downloads-secret" }),
  });
  assert.equal(login.status, 200);
  const rawCookies = login.headers.getSetCookie
    ? login.headers.getSetCookie()
    : [login.headers.get("set-cookie")];
  const cookie = rawCookies
    .filter(Boolean)
    .map((value) => value.split(";")[0])
    .find((value) => value.startsWith("dodo_session="));
  assert.ok(cookie);

  const admin = (url, options = {}) =>
    fetch(`${baseUrl}${url}`, {
      ...options,
      headers: { Cookie: cookie, ...(options.headers || {}) },
    });

  await t.test("seeds Unmurce from the legacy portfolio APK", async () => {
    const res = await fetch(`${baseUrl}/api/downloads`);
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.apps.length, 1);
    assert.equal(data.apps[0].slug, "unmurce");
    assert.equal(data.apps[0].latest.version, "1.7.5");
    assert.equal(data.apps[0].releases.length, 1);
  });

  await t.test("latest is the highest version, not the newest row", async () => {
    const older = await admin("/dodo/api/downloads/apps/unmurce/releases", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        release: {
          version: "1.9.0",
          url: "https://cdn.example.com/unmurce-1.9.0.apk",
          size_bytes: 100,
          released_at: "2026-11-17",
        },
      }),
    });
    assert.equal(older.status, 201);

    const newest = await admin("/dodo/api/downloads/apps/unmurce/releases", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        release: {
          version: "1.10.0",
          url: "https://cdn.example.com/unmurce-1.10.0.apk",
          size_bytes: 200,
          released_at: "2026-11-01",
        },
      }),
    });
    assert.equal(newest.status, 201);

    const catalog = await (await fetch(`${baseUrl}/api/downloads`)).json();
    assert.equal(catalog.apps[0].latest.version, "1.10.0");
    assert.equal(catalog.apps[0].latest.url, "https://cdn.example.com/unmurce-1.10.0.apk");
  });

  await t.test("deleting the latest release promotes the next version", async () => {
    const catalog = await (await admin("/dodo/api/downloads")).json();
    const latest = catalog.apps[0].latest;
    assert.equal(latest.version, "1.10.0");

    const res = await admin(`/dodo/api/downloads/releases/${latest.id}`, {
      method: "DELETE",
    });
    assert.equal(res.status, 200);

    const after = await (await fetch(`${baseUrl}/api/downloads`)).json();
    assert.equal(after.apps[0].latest.version, "1.9.0");
  });

  await t.test("creates a second app with no releases", async () => {
    const res = await admin("/dodo/api/downloads/apps", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        app: {
          slug: "notes-app",
          name: "Notes App",
          tagline: "A small notes app.",
        },
      }),
    });
    assert.equal(res.status, 201);

    const catalog = await (await fetch(`${baseUrl}/api/downloads`)).json();
    assert.equal(catalog.apps.length, 2);
    const notes = catalog.apps.find((app) => app.slug === "notes-app");
    assert.equal(notes.latest, null);
    assert.deepEqual(notes.releases, []);
  });

  await t.test("updates app metadata and rejects unsafe URLs", async () => {
    const update = await admin("/dodo/api/downloads/apps/notes-app", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        app: { name: "Notes App Pro", tagline: "Updated.", active: false },
      }),
    });
    assert.equal(update.status, 200);
    const updated = await update.json();
    assert.equal(updated.app.name, "Notes App Pro");

    const publicCatalog = await (await fetch(`${baseUrl}/api/downloads`)).json();
    assert.equal(publicCatalog.apps.some((app) => app.slug === "notes-app"), false);

    const bad = await admin("/dodo/api/downloads/apps/notes-app/releases", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        release: { version: "1.0.0", url: "javascript:alert(1)" },
      }),
    });
    assert.equal(bad.status, 400);
  });

  await t.test("rejects duplicate versions for the same app", async () => {
    const res = await admin("/dodo/api/downloads/apps/unmurce/releases", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        release: {
          version: "1.9.0",
          url: "https://cdn.example.com/duplicate.apk",
        },
      }),
    });
    assert.equal(res.status, 409);
  });

  await t.test("deletes an app and its releases", async () => {
    const res = await admin("/dodo/api/downloads/apps/notes-app", {
      method: "DELETE",
    });
    assert.equal(res.status, 200);

    const catalog = await (await fetch(`${baseUrl}/api/downloads`)).json();
    assert.equal(catalog.apps.some((app) => app.slug === "notes-app"), false);
  });

  await t.test("reports r2Configured=false and presign returns 503 when R2 is unset", async () => {
    const adminCatalog = await (await admin("/dodo/api/downloads")).json();
    assert.equal(adminCatalog.r2Configured, false);

    const res = await admin("/dodo/api/downloads/apps/unmurce/releases/presign", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        version: "2.0.0",
        filename: "unmurce.apk",
        size_bytes: 123456,
      }),
    });
    assert.equal(res.status, 503);
  });

  await t.test("R2 presign, release create, edit cleanup, release delete and app delete", async () => {
    process.env.R2_ENDPOINT = "https://acc.r2.cloudflarestorage.com";
    process.env.R2_BUCKET = "releases-bucket";
    process.env.R2_ACCESS_KEY_ID = "key-id";
    process.env.R2_SECRET_ACCESS_KEY = "secret-key";
    process.env.R2_PUBLIC_BASE_URL = "https://cdn.example.com";

    const objects = new Map();
    const deletedKeys = [];

    r2.setR2Client(
      {
        async send(command) {
          const name = command.constructor.name;
          if (name === "HeadObjectCommand") {
            const obj = objects.get(command.input.Key);
            if (!obj) {
              const err = new Error("Not found");
              err.name = "NotFound";
              err.$metadata = { httpStatusCode: 404 };
              throw err;
            }
            return {
              ContentLength: obj.size,
              ContentType: obj.contentType,
              ETag: '"mock-etag"',
            };
          }
          if (name === "DeleteObjectCommand") {
            deletedKeys.push(command.input.Key);
            objects.delete(command.input.Key);
            return {};
          }
          return {};
        },
      },
      async (_client, command) => `https://signed.example.com/${encodeURIComponent(command.input.Key)}`
    );

    const adminCatalog = await (await admin("/dodo/api/downloads")).json();
    assert.equal(adminCatalog.r2Configured, true);

    const dupPresign = await admin("/dodo/api/downloads/apps/unmurce/releases/presign", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        version: "1.9.0",
        filename: "unmurce.apk",
        size_bytes: 12345,
      }),
    });
    assert.equal(dupPresign.status, 409);

    const badExt = await admin("/dodo/api/downloads/apps/unmurce/releases/presign", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        version: "2.0.0",
        filename: "malware.sh",
        size_bytes: 12345,
      }),
    });
    assert.equal(badExt.status, 400);

    const presignRes = await admin("/dodo/api/downloads/apps/unmurce/releases/presign", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        version: "2.0.0",
        filename: "unmurce-v2.0.0.apk",
        size_bytes: 543210,
      }),
    });
    assert.equal(presignRes.status, 200);
    const presign = await presignRes.json();
    assert.ok(presign.uploadUrl.startsWith("https://signed.example.com/"));
    assert.match(presign.r2Key, /^releases\/unmurce\/v2\.0\.0\//);
    assert.equal(presign.publicUrl, `https://cdn.example.com/${presign.r2Key}`);
    assert.equal(presign.headers["Content-Type"], "application/vnd.android.package-archive");

    // Creating before the object exists in R2 must fail with 400.
    const missingObjRes = await admin("/dodo/api/downloads/apps/unmurce/releases", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        release: {
          version: "2.0.0",
          r2_key: presign.r2Key,
          released_at: "2026-11-22",
        },
      }),
    });
    assert.equal(missingObjRes.status, 400);

    // Simulate direct browser PUT upload to R2.
    objects.set(presign.r2Key, {
      size: 543210,
      contentType: "application/vnd.android.package-archive",
    });

    const createRes = await admin("/dodo/api/downloads/apps/unmurce/releases", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        release: {
          version: "2.0.0",
          r2_key: presign.r2Key,
          released_at: "2026-11-22",
          notes: "R2 release",
        },
      }),
    });
    assert.equal(createRes.status, 201);
    const created = await createRes.json();
    assert.equal(created.release.url, presign.publicUrl);
    assert.equal(created.release.size_bytes, 543210);
    assert.equal(created.release.r2_key, presign.r2Key);

    // Public downloads endpoint must not leak r2_key.
    const publicCatalog = await (await fetch(`${baseUrl}/api/downloads`)).json();
    assert.equal(publicCatalog.apps[0].latest.version, "2.0.0");
    assert.equal("r2_key" in publicCatalog.apps[0].latest, false);

    // Admin downloads endpoint includes r2_key.
    const adminAfterCreate = await (await admin("/dodo/api/downloads")).json();
    assert.equal(adminAfterCreate.apps[0].latest.r2_key, presign.r2Key);

    // Editing notes without changing the file preserves r2_key and does not delete R2 object.
    const editNotesRes = await admin(`/dodo/api/downloads/releases/${created.release.id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        release: {
          version: "2.0.0",
          url: created.release.url,
          size_bytes: created.release.size_bytes,
          released_at: "2026-11-22",
          notes: "Updated notes",
        },
      }),
    });
    assert.equal(editNotesRes.status, 200);
    const editedNotes = await editNotesRes.json();
    assert.equal(editedNotes.release.r2_key, presign.r2Key);
    assert.equal(editedNotes.release.notes, "Updated notes");
    assert.deepEqual(deletedKeys, []);

    // Replacing with a new R2 upload deletes the old R2 object automatically.
    const replacePresignRes = await admin("/dodo/api/downloads/apps/unmurce/releases/presign", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        version: "2.0.0",
        filename: "unmurce-v2.0.0-r2.apk",
        size_bytes: 600000,
        releaseId: created.release.id,
      }),
    });
    assert.equal(replacePresignRes.status, 200);
    const replacePresign = await replacePresignRes.json();
    objects.set(replacePresign.r2Key, {
      size: 600000,
      contentType: "application/vnd.android.package-archive",
    });

    const replaceRes = await admin(`/dodo/api/downloads/releases/${created.release.id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        release: {
          version: "2.0.0",
          r2_key: replacePresign.r2Key,
          released_at: "2026-11-22",
          notes: "Hotfix build",
        },
      }),
    });
    assert.equal(replaceRes.status, 200);
    const replaced = await replaceRes.json();
    assert.equal(replaced.release.r2_key, replacePresign.r2Key);
    assert.equal(replaced.release.size_bytes, 600000);
    assert.deepEqual(deletedKeys, [presign.r2Key]);

    // Deleting the release automatically removes the current R2 object.
    const delReleaseRes = await admin(`/dodo/api/downloads/releases/${created.release.id}`, {
      method: "DELETE",
    });
    assert.equal(delReleaseRes.status, 200);
    const delRelease = await delReleaseRes.json();
    assert.equal(delRelease.r2Deleted, true);
    assert.deepEqual(deletedKeys, [presign.r2Key, replacePresign.r2Key]);

    // Deleting an app automatically removes all R2-backed releases for that app.
    const appRes = await admin("/dodo/api/downloads/apps", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        app: { slug: "tool-app", name: "Tool App" },
      }),
    });
    assert.equal(appRes.status, 201);

    const toolPresignRes = await admin("/dodo/api/downloads/apps/tool-app/releases/presign", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        version: "1.0.0",
        filename: "tool.zip",
        size_bytes: 1024,
      }),
    });
    const toolPresign = await toolPresignRes.json();
    objects.set(toolPresign.r2Key, { size: 1024, contentType: "application/zip" });

    const toolRelRes = await admin("/dodo/api/downloads/apps/tool-app/releases", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        release: { version: "1.0.0", r2_key: toolPresign.r2Key },
      }),
    });
    assert.equal(toolRelRes.status, 201);

    const delAppRes = await admin("/dodo/api/downloads/apps/tool-app", {
      method: "DELETE",
    });
    assert.equal(delAppRes.status, 200);
    const delApp = await delAppRes.json();
    assert.equal(delApp.deletedR2Files, 1);
    assert.ok(deletedKeys.includes(toolPresign.r2Key));
  });
});
