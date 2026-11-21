const assert = require("node:assert/strict");
const { test } = require("node:test");
const { compareVersions, setPool } = require("../api/db");

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
        return {
          rows: store.releases
            .slice()
            .sort((left, right) => left.id - right.id)
            .map((release) => ({ ...release })),
        };
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
        return { rows: [{ ...release }] };
      }

      if (text.startsWith("DELETE FROM download_releases")) {
        const index = store.releases.findIndex((item) => item.id === Number(params[0]));
        if (index === -1) return { rows: [] };
        const [release] = store.releases.splice(index, 1);
        return { rows: [{ app_slug: release.app_slug }] };
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

  process.env.ADMIN_SECRET = "downloads-secret";
  process.env.ADMIN_FIREBASE_UIDS = "";
  process.env.GROQ_API_KEY = "";

  const { createApp } = require("../api/index");

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
});
