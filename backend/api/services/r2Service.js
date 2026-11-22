const crypto = require("crypto");
const path = require("path");
const {
  S3Client,
  PutObjectCommand,
  HeadObjectCommand,
  DeleteObjectCommand,
  HeadBucketCommand,
} = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");

const MAX_RELEASE_UPLOAD_BYTES = 500 * 1024 * 1024;
const PRESIGN_TTL_SECONDS = 900;
const HEALTH_TIMEOUT_MS = 3000;
const ALLOWED_RELEASE_EXTENSIONS = new Set([
  ".apk",
  ".aab",
  ".zip",
  ".exe",
  ".msi",
  ".dmg",
  ".pkg",
  ".deb",
  ".appimage",
  ".ipa",
  ".tar.gz",
]);

let cachedClient = null;
let cachedClientKey = "";
let injectedClient = null;
let injectedPresigner = null;

class R2Error extends Error {
  constructor(message, status = 500) {
    super(message);
    this.name = "R2Error";
    this.status = status;
  }
}

function stripTrailingSlashes(value) {
  return String(value || "").trim().replace(/\/+$/, "");
}

function getConfig() {
  return {
    endpoint: stripTrailingSlashes(process.env.R2_ENDPOINT),
    bucket: String(process.env.R2_BUCKET || "").trim(),
    accessKeyId: String(process.env.R2_ACCESS_KEY_ID || "").trim(),
    secretAccessKey: String(process.env.R2_SECRET_ACCESS_KEY || "").trim(),
    publicBaseUrl: stripTrailingSlashes(process.env.R2_PUBLIC_BASE_URL),
  };
}

function isConfigured() {
  const cfg = getConfig();
  if (
    !cfg.endpoint ||
    !cfg.bucket ||
    !cfg.accessKeyId ||
    !cfg.secretAccessKey ||
    !cfg.publicBaseUrl
  ) {
    return false;
  }
  return /^https?:\/\//i.test(cfg.endpoint) && /^https?:\/\//i.test(cfg.publicBaseUrl);
}

/** Inject a mock S3 client (and optional presigner) for tests; pass null to reset. */
function setR2Client(client, presigner = null) {
  injectedClient = client || null;
  injectedPresigner = presigner || null;
}

function getClient() {
  if (injectedClient) return injectedClient;
  if (!isConfigured()) {
    throw new R2Error("Cloudflare R2 is not configured on this server", 503);
  }
  const cfg = getConfig();
  const cacheKey = `${cfg.endpoint}|${cfg.accessKeyId}|${cfg.secretAccessKey}`;
  if (!cachedClient || cachedClientKey !== cacheKey) {
    cachedClient = new S3Client({
      region: "auto",
      endpoint: cfg.endpoint,
      credentials: {
        accessKeyId: cfg.accessKeyId,
        secretAccessKey: cfg.secretAccessKey,
      },
      // R2 rejects or breaks browser presigned PUTs when AWS SDK v3 adds default CRC32 checksum headers.
      requestChecksumCalculation: "WHEN_REQUIRED",
      responseChecksumValidation: "WHEN_REQUIRED",
    });
    cachedClientKey = cacheKey;
  }
  return cachedClient;
}

function extractExtension(filename) {
  const base = path.posix
    .basename(String(filename || "").replace(/\\/g, "/"))
    .trim()
    .toLowerCase();
  if (!base) return "";
  if (base.endsWith(".tar.gz")) return ".tar.gz";
  return path.posix.extname(base);
}

function contentTypeForExt(ext) {
  if (ext === ".apk") return "application/vnd.android.package-archive";
  if (ext === ".zip") return "application/zip";
  return "application/octet-stream";
}

function sanitizeVersionSegment(version) {
  return (
    String(version || "")
      .trim()
      .replace(/^v/i, "")
      .replace(/[^A-Za-z0-9._-]+/g, "-")
      .replace(/^-+|-+$/g, "") || "0"
  );
}

function buildReleaseKey(slug, version, filename) {
  const rawName = path.posix
    .basename(String(filename || "").replace(/\\/g, "/"))
    .trim();
  const ext = extractExtension(rawName);
  let safeName = rawName.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^\.+/, "");
  if (!safeName) {
    safeName = `release${ext}`;
  }
  if (safeName.length > 100) {
    const stemMax = Math.max(1, 100 - ext.length);
    const stem = safeName.slice(0, stemMax).replace(/[.-]+$/, "") || "release";
    safeName = `${stem}${ext}`;
  }

  const safeSlug = String(slug || "").trim().toLowerCase();
  const safeVersion = sanitizeVersionSegment(version);
  const shortHex = crypto.randomBytes(4).toString("hex");
  return `releases/${safeSlug}/v${safeVersion}/${shortHex}-${safeName}`;
}

function isValidReleaseKeyForApp(slug, key) {
  if (typeof key !== "string" || !key || key.length > 512) return false;
  if (key.trim() !== key) return false;
  if (/[\x00-\x1f\x7f\\]/.test(key) || key.includes("//")) return false;

  const safeSlug = String(slug || "").trim().toLowerCase();
  if (!safeSlug) return false;

  const prefix = `releases/${safeSlug}/`;
  if (!key.startsWith(prefix) || key.length === prefix.length) return false;

  const segments = key.split("/");
  return !segments.some((segment) => !segment || segment === "." || segment === "..");
}

function getPublicUrl(key) {
  const cfg = getConfig();
  const encodedPath = String(key || "")
    .split("/")
    .map(encodeURIComponent)
    .join("/");
  return `${cfg.publicBaseUrl}/${encodedPath}`;
}

async function createReleaseUploadUrl({ slug, version, filename, sizeBytes }) {
  if (!isConfigured()) {
    throw new R2Error("Cloudflare R2 is not configured on this server", 503);
  }

  const ext = extractExtension(filename);
  if (!ext || !ALLOWED_RELEASE_EXTENSIONS.has(ext)) {
    throw new R2Error(
      `Unsupported release file extension "${ext || "none"}"`,
      400
    );
  }

  const size = Number(sizeBytes);
  if (!Number.isInteger(size) || size <= 0) {
    throw new R2Error("size_bytes must be a positive integer", 400);
  }
  if (size > MAX_RELEASE_UPLOAD_BYTES) {
    throw new R2Error(
      `Release file is too large (max ${Math.round(MAX_RELEASE_UPLOAD_BYTES / (1024 * 1024))} MB)`,
      413
    );
  }

  const cfg = getConfig();
  const client = getClient();
  const r2Key = buildReleaseKey(slug, version, filename);
  const contentType = contentTypeForExt(ext);
  const safeSlug = String(slug || "").trim().toLowerCase();
  const safeVersion = sanitizeVersionSegment(version);
  const contentDisposition = `attachment; filename="${safeSlug}-v${safeVersion}${ext}"`;

  const command = new PutObjectCommand({
    Bucket: cfg.bucket,
    Key: r2Key,
    ContentType: contentType,
    ContentDisposition: contentDisposition,
  });

  const sign = injectedPresigner || getSignedUrl;
  const uploadUrl = await sign(client, command, {
    expiresIn: PRESIGN_TTL_SECONDS,
  });

  return {
    uploadUrl,
    r2Key,
    publicUrl: getPublicUrl(r2Key),
    headers: {
      "Content-Type": contentType,
      "Content-Disposition": contentDisposition,
    },
    expiresIn: PRESIGN_TTL_SECONDS,
    maxBytes: MAX_RELEASE_UPLOAD_BYTES,
  };
}

function isNotFoundError(err) {
  if (!err) return false;
  return (
    err.$metadata?.httpStatusCode === 404 ||
    err.name === "NotFound" ||
    err.name === "NoSuchKey" ||
    err.Code === "NoSuchKey"
  );
}

async function headObject(key) {
  if (!isConfigured()) {
    throw new R2Error("Cloudflare R2 is not configured on this server", 503);
  }
  const cfg = getConfig();
  const client = getClient();
  try {
    const res = await client.send(
      new HeadObjectCommand({
        Bucket: cfg.bucket,
        Key: key,
      })
    );
    return {
      key,
      sizeBytes: Number(res?.ContentLength) || 0,
      contentType: res?.ContentType || null,
      etag: res?.ETag || null,
    };
  } catch (err) {
    if (isNotFoundError(err)) return null;
    throw err;
  }
}

async function deleteObject(key) {
  if (!isConfigured()) {
    throw new R2Error("Cloudflare R2 is not configured on this server", 503);
  }
  const cfg = getConfig();
  const client = getClient();
  await client.send(
    new DeleteObjectCommand({
      Bucket: cfg.bucket,
      Key: key,
    })
  );
  return true;
}

async function checkBucket() {
  if (!isConfigured()) {
    return {
      configured: false,
      ok: false,
      bucket: null,
      latencyMs: null,
      error: null,
    };
  }

  const cfg = getConfig();
  const client = getClient();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), HEALTH_TIMEOUT_MS);
  const started = Date.now();

  try {
    await client.send(
      new HeadBucketCommand({
        Bucket: cfg.bucket,
      }),
      { abortSignal: controller.signal }
    );
    return {
      configured: true,
      ok: true,
      bucket: cfg.bucket,
      latencyMs: Date.now() - started,
      error: null,
    };
  } catch (err) {
    return {
      configured: true,
      ok: false,
      bucket: cfg.bucket,
      latencyMs: Date.now() - started,
      error: err?.name === "AbortError" ? "Timed out" : err.message,
    };
  } finally {
    clearTimeout(timer);
  }
}

module.exports = {
  ALLOWED_RELEASE_EXTENSIONS,
  MAX_RELEASE_UPLOAD_BYTES,
  PRESIGN_TTL_SECONDS,
  R2Error,
  buildReleaseKey,
  checkBucket,
  contentTypeForExt,
  createReleaseUploadUrl,
  deleteObject,
  extractExtension,
  getConfig,
  getPublicUrl,
  headObject,
  isConfigured,
  isValidReleaseKeyForApp,
  setR2Client,
};
