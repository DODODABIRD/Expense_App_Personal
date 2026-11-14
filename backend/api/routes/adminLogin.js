const express = require("express");
const crypto = require("crypto");

const router = express.Router();

// Admin credentials from environment
const ADMIN_SECRET = process.env.ADMIN_SECRET || "";
const ADMIN_FIREBASE_UIDS = (process.env.ADMIN_FIREBASE_UIDS || "").split(",").filter(Boolean);

// Simple session store (in-memory for dev, use Redis for production)
const sessions = new Map();
const SESSION_DURATION = 24 * 60 * 60 * 1000; // 24 hours

function generateSessionId() {
  return crypto.randomBytes(32).toString("hex");
}

function createSession(uid) {
  const sessionId = generateSessionId();
  sessions.set(sessionId, {
    uid,
    createdAt: Date.now(),
    expiresAt: Date.now() + SESSION_DURATION
  });
  return sessionId;
}

function validateSession(sessionId) {
  if (!sessionId) return null;
  const session = sessions.get(sessionId);
  if (!session) return null;
  if (Date.now() > session.expiresAt) {
    sessions.delete(sessionId);
    return null;
  }
  return session;
}

// Login page
router.get("/login", (req, res) => {
  const sessionId = req.cookies?.dodo_session;
  const session = validateSession(sessionId);

  // If already logged in, redirect to admin
  if (session) {
    return res.redirect("/dodo");
    //TODO: Ubah jadi routing yang lebih masuk 
  }

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Admin Login - Unmurce</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --bg-primary: #0f0f1a;
      --bg-secondary: #1a1a2e;
      --bg-card: #16213e;
      --accent: #00d4ff;
      --accent-hover: #00b8e6;
      --text-primary: #ffffff;
      --text-secondary: #a0a0b0;
      --error: #ff4757;
      --success: #2ed573;
      --warning: #ffa502;
    }

    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: var(--bg-primary);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
      color: var(--text-primary);
    }

    .login-container {
      width: 100%;
      max-width: 420px;
    }

    .logo-section {
      text-align: center;
      margin-bottom: 40px;
    }

    .logo {
      width: 80px;
      height: 80px;
      background: linear-gradient(135deg, var(--accent) 0%, #0099cc 100%);
      border-radius: 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto 20px;
      box-shadow: 0 10px 40px rgba(0, 212, 255, 0.3);
    }

    .logo svg {
      width: 48px;
      height: 48px;
      fill: white;
    }

    .logo-section h1 {
      font-size: 28px;
      font-weight: 700;
      background: linear-gradient(135deg, var(--text-primary) 0%, var(--accent) 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
      margin-bottom: 8px;
    }

    .logo-section p {
      color: var(--text-secondary);
      font-size: 14px;
    }

    .login-card {
      background: var(--bg-card);
      border-radius: 20px;
      padding: 40px;
      box-shadow: 0 20px 60px rgba(0, 0, 0, 0.4);
      border: 1px solid rgba(255, 255, 255, 0.05);
    }

    .login-card h2 {
      font-size: 20px;
      margin-bottom: 8px;
      text-align: center;
    }

    .login-card .subtitle {
      color: var(--text-secondary);
      font-size: 14px;
      text-align: center;
      margin-bottom: 30px;
    }

    .form-group {
      margin-bottom: 24px;
    }

    .form-group label {
      display: block;
      font-size: 13px;
      font-weight: 500;
      color: var(--text-secondary);
      margin-bottom: 8px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .input-wrapper {
      position: relative;
    }

    .input-wrapper svg {
      position: absolute;
      left: 16px;
      top: 50%;
      transform: translateY(-50%);
      width: 20px;
      height: 20px;
      fill: var(--text-secondary);
      transition: fill 0.2s;
    }

    .input-wrapper input {
      width: 100%;
      padding: 16px 16px 16px 48px;
      background: var(--bg-secondary);
      border: 2px solid rgba(255, 255, 255, 0.1);
      border-radius: 12px;
      font-size: 15px;
      color: var(--text-primary);
      transition: all 0.2s;
    }

    .input-wrapper input:focus {
      outline: none;
      border-color: var(--accent);
      box-shadow: 0 0 0 4px rgba(0, 212, 255, 0.1);
    }

    .input-wrapper input:focus + svg,
    .input-wrapper:has(input:focus) svg {
      fill: var(--accent);
    }

    .input-wrapper input::placeholder {
      color: var(--text-secondary);
      opacity: 0.6;
    }

    .btn-login {
      width: 100%;
      padding: 16px;
      background: linear-gradient(135deg, var(--accent) 0%, #0099cc 100%);
      border: none;
      border-radius: 12px;
      font-size: 16px;
      font-weight: 600;
      color: var(--bg-primary);
      cursor: pointer;
      transition: all 0.2s;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
    }

    .btn-login:hover {
      transform: translateY(-2px);
      box-shadow: 0 10px 30px rgba(0, 212, 255, 0.4);
    }

    .btn-login:active {
      transform: translateY(0);
    }

    .btn-login:disabled {
      opacity: 0.6;
      cursor: not-allowed;
      transform: none;
    }

    .btn-login svg {
      width: 20px;
      height: 20px;
      fill: currentColor;
    }

    .spinner {
      width: 20px;
      height: 20px;
      border: 2px solid rgba(0, 0, 0, 0.2);
      border-top-color: currentColor;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }

    @keyframes spin {
      to { transform: rotate(360deg); }
    }

    .alert {
      padding: 14px 16px;
      border-radius: 10px;
      margin-bottom: 20px;
      font-size: 14px;
      display: flex;
      align-items: center;
      gap: 10px;
      animation: slideIn 0.3s ease;
    }

    @keyframes slideIn {
      from {
        opacity: 0;
        transform: translateY(-10px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }

    .alert-error {
      background: rgba(255, 71, 87, 0.15);
      border: 1px solid rgba(255, 71, 87, 0.3);
      color: var(--error);
    }

    .alert svg {
      width: 18px;
      height: 18px;
      fill: currentColor;
      flex-shrink: 0;
    }

    .divider {
      display: flex;
      align-items: center;
      margin: 24px 0;
      color: var(--text-secondary);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 1px;
    }

    .divider::before,
    .divider::after {
      content: "";
      flex: 1;
      height: 1px;
      background: rgba(255, 255, 255, 0.1);
    }

    .divider span {
      padding: 0 16px;
    }

    .firebase-section {
      text-align: center;
    }

    .firebase-section p {
      color: var(--text-secondary);
      font-size: 13px;
      margin-bottom: 16px;
    }

    .btn-firebase {
      width: 100%;
      padding: 14px;
      background: var(--bg-secondary);
      border: 2px solid rgba(255, 255, 255, 0.1);
      border-radius: 12px;
      font-size: 14px;
      font-weight: 500;
      color: var(--text-primary);
      cursor: pointer;
      transition: all 0.2s;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
    }

    .btn-firebase:hover {
      border-color: var(--accent);
      background: rgba(0, 212, 255, 0.05);
    }

    .btn-firebase svg {
      width: 18px;
      height: 18px;
      fill: #FFCA28;
    }

    .footer {
      text-align: center;
      margin-top: 30px;
      color: var(--text-secondary);
      font-size: 12px;
    }

    .footer a {
      color: var(--accent);
      text-decoration: none;
    }

    .security-note {
      background: rgba(0, 212, 255, 0.1);
      border: 1px solid rgba(0, 212, 255, 0.2);
      border-radius: 10px;
      padding: 12px 16px;
      margin-top: 20px;
      font-size: 12px;
      color: var(--text-secondary);
      display: flex;
      align-items: flex-start;
      gap: 10px;
    }

    .security-note svg {
      width: 16px;
      height: 16px;
      fill: var(--accent);
      flex-shrink: 0;
      margin-top: 2px;
    }

    .token-input {
      font-family: 'JetBrains Mono', 'Fira Code', monospace;
    }
  </style>
</head>
<body>
  <div class="login-container">
    <div class="logo-section">
      <div class="logo">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/>
        </svg>
      </div>
      <h1>Unmurce Admin</h1>
      <p>Environment Variables Management</p>
    </div>

    <div class="login-card">
      <h2>Welcome Back</h2>
      <p class="subtitle">Sign in to access the admin panel</p>

      <div id="alert" class="alert alert-error" style="display: none;">
        <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>
        <span id="alertMessage"></span>
      </div>

      <form id="secretForm" onsubmit="handleSecretLogin(event)">
        <div class="form-group">
          <label for="secretKey">Admin Secret Key</label>
          <div class="input-wrapper">
            <input
              type="password"
              id="secretKey"
              name="secret"
              placeholder="Enter your admin secret"
              autocomplete="current-password"
              required
            >
            <svg viewBox="0 0 24 24"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z"/></svg>
          </div>
        </div>

        <button type="submit" class="btn-login" id="secretBtn">
          <svg viewBox="0 0 24 24"><path d="M10 17l5-5-5-5v10z"/></svg>
          Sign In with Secret
        </button>
      </form>

      <div class="divider"><span>or</span></div>

      <div class="firebase-section">
        <p>Use your Firebase token to authenticate</p>
        <form id="firebaseForm" onsubmit="handleFirebaseLogin(event)">
          <div class="form-group">
            <label for="firebaseToken">Firebase ID Token</label>
            <div class="input-wrapper">
              <input
                type="text"
                id="firebaseToken"
                name="token"
                placeholder="Paste your Firebase ID token"
                class="token-input"
              >
              <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
            </div>
          </div>

          <button type="submit" class="btn-firebase">
            <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
            Verify Firebase Token
          </button>
        </form>
      </div>

      <div class="security-note">
        <svg viewBox="0 0 24 24"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V6.3l7-3.11v8.8z"/></svg>
        <span>Your credentials are verified securely. Sessions expire after 24 hours for security.</span>
      </div>
    </div>

    <div class="footer">
      <p>&copy; 2024 Unmurce Admin Panel</p>
    </div>
  </div>

  <script>
    function showAlert(message) {
      const alert = document.getElementById('alert');
      const alertMessage = document.getElementById('alertMessage');
      alertMessage.textContent = message;
      alert.style.display = 'flex';
      setTimeout(() => {
        alert.style.display = 'none';
      }, 5000);
    }

    function setLoading(btn, loading) {
      if (loading) {
        btn.disabled = true;
        btn.innerHTML = '<span class="spinner"></span> Verifying...';
      } else {
        btn.disabled = false;
        btn.innerHTML = '<svg viewBox="0 0 24 24"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z"/></svg> Sign In with Secret';
      }
    }

    async function handleSecretLogin(e) {
      e.preventDefault();
      const btn = document.getElementById('secretBtn');
      const secret = document.getElementById('secretKey').value;

      setLoading(btn, true);

      try {
        const res = await fetch('/dodo/api/login-secret', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ secret })
        });

        const data = await res.json();

        if (data.success) {
          window.location.href = '/dodo';
        } else {
          showAlert(data.error || 'Invalid credentials');
          setLoading(btn, false);
        }
      } catch (err) {
        showAlert('Connection error. Please try again.');
        setLoading(btn, false);
      }
    }

    async function handleFirebaseLogin(e) {
      e.preventDefault();
      const token = document.getElementById('firebaseToken').value.trim();

      if (!token) {
        showAlert('Please enter a Firebase token');
        return;
      }

      try {
        const res = await fetch('/dodo/api/login-firebase', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token })
        });

        const data = await res.json();

        if (data.success) {
          window.location.href = '/dodo';
        } else {
          showAlert(data.error || 'Invalid Firebase token');
        }
      } catch (err) {
        showAlert('Connection error. Please try again.');
      }
    }
  </script>
</body>
</html>`;

  res.set("Cache-Control", "no-store, max-age=0");
  res.type("html").send(html);
});

// API: Login with secret key
router.post("/api/login-secret", async (req, res) => {
  const { secret } = req.body;

  if (!secret) {
    return res.json({ success: false, error: "Secret is required" });
  }

  // Check against ADMIN_SECRET env var
  if (ADMIN_SECRET && secret !== ADMIN_SECRET) {
    return res.json({ success: false, error: "Invalid secret key" });
  }

  // If no ADMIN_SECRET is set, allow access in development mode
  if (!ADMIN_SECRET) {
    console.warn("Warning: ADMIN_SECRET not set. Admin panel is accessible without password.");
  }

  const sessionId = createSession("admin_secret");

  res.cookie("dodo_session", sessionId, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "strict",
    maxAge: SESSION_DURATION,
    path: "/"
  });

  res.json({ success: true });
});

// API: Login with Firebase token
router.post("/api/login-firebase", async (req, res) => {
  const { token } = req.body;
  const admin = require("firebase-admin");

  if (!token) {
    return res.json({ success: false, error: "Token is required" });
  }

  if (!admin.apps.length) {
    return res.json({ success: false, error: "Firebase is not configured" });
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);

    // Check if user's UID is in the allowed list (optional)
    if (ADMIN_FIREBASE_UIDS.length > 0 && !ADMIN_FIREBASE_UIDS.includes(decoded.uid)) {
      return res.json({ success: false, error: "You are not authorized to access this panel" });
    }

    const sessionId = createSession(decoded.uid);

    res.cookie("dodo_session", sessionId, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "strict",
      maxAge: SESSION_DURATION,
      path: "/"
    });

    res.json({ success: true });
  } catch (err) {
    res.json({ success: false, error: "Invalid or expired Firebase token" });
  }
});

// API: Logout
router.post("/api/logout", (req, res) => {
  const sessionId = req.cookies?.dodo_session;
  if (sessionId) {
    sessions.delete(sessionId);
  }

  res.clearCookie("dodo_session", { path: "/" });
  res.json({ success: true });
});

// API: Check auth status
router.get("/api/check", (req, res) => {
  const sessionId = req.cookies?.dodo_session;
  const session = validateSession(sessionId);

  if (session) {
    res.json({ authenticated: true, uid: session.uid });
  } else {
    res.json({ authenticated: false });
  }
});

module.exports = {
  router,
  sessions,
  validateSession,
  createSession,
  SESSION_DURATION
};
