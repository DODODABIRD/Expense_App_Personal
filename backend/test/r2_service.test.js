const assert = require("node:assert/strict");
const { test } = require("node:test");
const r2 = require("../api/services/r2Service");

const R2_KEYS = [
  "R2_ENDPOINT",
  "R2_BUCKET",
  "R2_ACCESS_KEY_ID",
  "R2_SECRET_ACCESS_KEY",
  "R2_PUBLIC_BASE_URL",
];

function snapshotR2Env() {
  const saved = {};
  for (const key of R2_KEYS) {
    saved[key] = process.env[key];
  }
  return saved;
}

function restoreR2Env(saved) {
  for (const key of R2_KEYS) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
}

function setValidR2Env() {
  process.env.R2_ENDPOINT = "https://acc123.r2.cloudflarestorage.com/";
  process.env.R2_BUCKET = "unmurce-releases";
  process.env.R2_ACCESS_KEY_ID = "test-access-key";
  process.env.R2_SECRET_ACCESS_KEY = "test-secret-key";
  process.env.R2_PUBLIC_BASE_URL = "https://cdn.dododabird.us/";
}

function clearR2Env() {
  for (const key of R2_KEYS) {
    process.env[key] = "";
  }
}

test("r2Service configuration validation", (t) => {
  const saved = snapshotR2Env();
  t.after(() => {
    restoreR2Env(saved);
    r2.setR2Client(null);
  });

  clearR2Env();
  assert.equal(r2.isConfigured(), false);

  setValidR2Env();
  assert.equal(r2.isConfigured(), true);
  assert.deepEqual(r2.getConfig(), {
    endpoint: "https://acc123.r2.cloudflarestorage.com",
    bucket: "unmurce-releases",
    accessKeyId: "test-access-key",
    secretAccessKey: "test-secret-key",
    publicBaseUrl: "https://cdn.dododabird.us",
  });

  process.env.R2_PUBLIC_BASE_URL = "ftp://cdn.dododabird.us";
  assert.equal(r2.isConfigured(), false);

  setValidR2Env();
  process.env.R2_ENDPOINT = "not-a-url";
  assert.equal(r2.isConfigured(), false);
});

test("buildReleaseKey and isValidReleaseKeyForApp sanitize and validate keys", () => {
  const key = r2.buildReleaseKey("unmurce", "v1.8.0", "C:\\builds\\app arm64.apk");
  assert.match(key, /^releases\/unmurce\/v1\.8\.0\/[0-9a-f]{8}-app-arm64\.apk$/);
  assert.equal(r2.isValidReleaseKeyForApp("unmurce", key), true);

  const tarKey = r2.buildReleaseKey("unmurce", "2.0.0", "a".repeat(120) + ".tar.gz");
  assert.ok(tarKey.endsWith(".tar.gz"));
  const filePart = tarKey.split("/").pop();
  assert.ok(filePart.length <= 109); // 8 hex + '-' + <= 100 chars

  assert.equal(r2.isValidReleaseKeyForApp("other-app", key), false);
  assert.equal(r2.isValidReleaseKeyForApp("unmurce", ""), false);
  assert.equal(r2.isValidReleaseKeyForApp("unmurce", "releases/unmurce/"), false);
  assert.equal(
    r2.isValidReleaseKeyForApp("unmurce", "releases/unmurce/../secret.apk"),
    false
  );
  assert.equal(
    r2.isValidReleaseKeyForApp("unmurce", "releases/unmurce\\v1/file.apk"),
    false
  );
  assert.equal(
    r2.isValidReleaseKeyForApp("unmurce", "releases/unmurce//v1/file.apk"),
    false
  );
  assert.equal(
    r2.isValidReleaseKeyForApp("unmurce", " releases/unmurce/v1/file.apk"),
    false
  );
  assert.equal(
    r2.isValidReleaseKeyForApp("unmurce", "releases/unmurce/v1/file.apk\n"),
    false
  );
});

test("createReleaseUploadUrl validates input and signs upload URLs", async (t) => {
  const saved = snapshotR2Env();
  t.after(() => {
    restoreR2Env(saved);
    r2.setR2Client(null);
  });

  clearR2Env();
  await assert.rejects(
    () =>
      r2.createReleaseUploadUrl({
        slug: "unmurce",
        version: "1.8.0",
        filename: "app.apk",
        sizeBytes: 1024,
      }),
    (err) => err.status === 503
  );

  setValidR2Env();

  let signedCommand = null;
  let signedOptions = null;
  r2.setR2Client(
    { async send() {} },
    async (_client, command, options) => {
      signedCommand = command;
      signedOptions = options;
      return "https://signed.r2.example.com/upload";
    }
  );

  for (const badFile of ["index.html", "malware.js", "README"]) {
    await assert.rejects(
      () =>
        r2.createReleaseUploadUrl({
          slug: "unmurce",
          version: "1.8.0",
          filename: badFile,
          sizeBytes: 1024,
        }),
      (err) => err.status === 400
    );
  }

  for (const badSize of [0, -1, 12.5, "abc", null]) {
    await assert.rejects(
      () =>
        r2.createReleaseUploadUrl({
          slug: "unmurce",
          version: "1.8.0",
          filename: "app.apk",
          sizeBytes: badSize,
        }),
      (err) => err.status === 400
    );
  }

  await assert.rejects(
    () =>
      r2.createReleaseUploadUrl({
        slug: "unmurce",
        version: "1.8.0",
        filename: "app.apk",
        sizeBytes: r2.MAX_RELEASE_UPLOAD_BYTES + 1,
      }),
    (err) => err.status === 413
  );

  const apkPresign = await r2.createReleaseUploadUrl({
    slug: "unmurce",
    version: "v1.8.0",
    filename: "app-release.apk",
    sizeBytes: 26000000,
  });
  assert.equal(apkPresign.uploadUrl, "https://signed.r2.example.com/upload");
  assert.match(apkPresign.r2Key, /^releases\/unmurce\/v1\.8\.0\/[0-9a-f]{8}-app-release\.apk$/);
  assert.equal(
    apkPresign.publicUrl,
    `https://cdn.dododabird.us/${apkPresign.r2Key}`
  );
  assert.deepEqual(apkPresign.headers, {
    "Content-Type": "application/vnd.android.package-archive",
    "Content-Disposition": 'attachment; filename="unmurce-v1.8.0.apk"',
  });
  assert.equal(apkPresign.expiresIn, r2.PRESIGN_TTL_SECONDS);
  assert.equal(signedOptions.expiresIn, r2.PRESIGN_TTL_SECONDS);
  assert.equal(signedCommand.input.Bucket, "unmurce-releases");
  assert.equal(signedCommand.input.Key, apkPresign.r2Key);
  assert.equal(
    signedCommand.input.ContentType,
    "application/vnd.android.package-archive"
  );

  const tarPresign = await r2.createReleaseUploadUrl({
    slug: "cli",
    version: "0.2.0",
    filename: "cli-linux.tar.gz",
    sizeBytes: 5120,
  });
  assert.equal(tarPresign.headers["Content-Type"], "application/octet-stream");
  assert.equal(
    tarPresign.headers["Content-Disposition"],
    'attachment; filename="cli-v0.2.0.tar.gz"'
  );
});

test("headObject, deleteObject and checkBucket handle R2 responses", async (t) => {
  const saved = snapshotR2Env();
  t.after(() => {
    restoreR2Env(saved);
    r2.setR2Client(null);
  });

  clearR2Env();
  assert.deepEqual(await r2.checkBucket(), {
    configured: false,
    ok: false,
    bucket: null,
    latencyMs: null,
    error: null,
  });

  setValidR2Env();

  let mode = "ok";
  const commands = [];
  r2.setR2Client({
    async send(command) {
      commands.push(command);
      if (command.constructor.name === "HeadObjectCommand") {
        if (mode === "notfound") {
          const err = new Error("Not found");
          err.name = "NotFound";
          err.$metadata = { httpStatusCode: 404 };
          throw err;
        }
        if (mode === "boom") {
          throw new Error("S3 network error");
        }
        return {
          ContentLength: 26052981,
          ContentType: "application/vnd.android.package-archive",
          ETag: '"abc"',
        };
      }
      if (command.constructor.name === "HeadBucketCommand") {
        if (mode === "bucketfail") {
          throw new Error("Access Denied");
        }
        return {};
      }
      return {};
    },
  });

  const found = await r2.headObject("releases/unmurce/v1.8.0/test.apk");
  assert.deepEqual(found, {
    key: "releases/unmurce/v1.8.0/test.apk",
    sizeBytes: 26052981,
    contentType: "application/vnd.android.package-archive",
    etag: '"abc"',
  });

  mode = "notfound";
  assert.equal(await r2.headObject("releases/unmurce/v1.8.0/missing.apk"), null);

  mode = "boom";
  await assert.rejects(
    () => r2.headObject("releases/unmurce/v1.8.0/err.apk"),
    /S3 network error/
  );

  mode = "ok";
  assert.equal(await r2.deleteObject("releases/unmurce/v1.8.0/test.apk"), true);
  assert.equal(commands.at(-1).input.Key, "releases/unmurce/v1.8.0/test.apk");

  const healthy = await r2.checkBucket();
  assert.equal(healthy.configured, true);
  assert.equal(healthy.ok, true);
  assert.equal(healthy.bucket, "unmurce-releases");
  assert.equal(typeof healthy.latencyMs, "number");
  assert.equal(healthy.error, null);

  mode = "bucketfail";
  const unhealthy = await r2.checkBucket();
  assert.equal(unhealthy.configured, true);
  assert.equal(unhealthy.ok, false);
  assert.equal(unhealthy.bucket, "unmurce-releases");
  assert.equal(unhealthy.error, "Access Denied");
});
