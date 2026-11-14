const express = require("express");
const fs = require("fs");
const path = require("path");
const { validateSession } = require("./adminLogin");

const router = express.Router();

// Session authentication middleware
function requireSession(req, res, next) {
  const sessionId = req.cookies?.dodo_session;
  const session = validateSession(sessionId);

  if (!session) {
    return res.status(401).json({ error: "Not authenticated", redirect: "/dodo/login" });
  }

  req.adminSession = session;
  next();
}

// Apply to all routes
router.use(requireSession);

// Path to .env.local file
const envFilePath = path.join(__dirname, "../../.env.local");
const envExamplePath = path.join(__dirname, "../../.env.example");

// List of allowed environment variables to manage
const ALLOWED_VARS = [
  "DATABASE_URL",
  "FIREBASE_SERVICE_ACCOUNT_JSON",
  "GROQ_API_KEY",
  "GROQ_MODEL",
  "GROQ_NOTIFICATION_MODEL",
  "AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT",
  "AZURE_DOCUMENT_INTELLIGENCE_KEY",
  "OPENROUTER_API_KEY",
  "PORT",
  "MONGODB_URI"
];

// Mask sensitive values for display
function maskValue(key, value) {
  if (!value) return "";
  if (key.includes("KEY") || key.includes("SECRET") || key.includes("PASSWORD") || key.includes("TOKEN")) {
    if (value.length > 8) {
      return value.substring(0, 4) + "****" + value.substring(value.length - 4);
    }
    return "****";
  }
  if (key.includes("SERVICE_ACCOUNT")) {
    return "[JSON Object - click to view/edit raw]";
  }
  return value;
}

// Parse .env file content
function parseEnvContent(content) {
  const lines = content.split(/\r?\n/);
  const envVars = {};

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const eqIndex = trimmed.indexOf("=");
    if (eqIndex > 0) {
      const key = trimmed.substring(0, eqIndex).trim();
      let value = trimmed.substring(eqIndex + 1).trim();

      // Handle quoted values
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }

      envVars[key] = value;
    }
  }

  return envVars;
}

// Serialize env vars back to file format
function serializeEnvVars(envVars) {
  const lines = [];

  for (const [key, value] of Object.entries(envVars)) {
    if (value.includes(" ") || value.includes("\n") || value.includes('"')) {
      lines.push(`${key}="${value.replace(/"/g, '\\"')}"`);
    } else {
      lines.push(`${key}=${value}`);
    }
  }

  return lines.join("\n");
}

// GET /dodo - Admin panel page
router.get("/", (req, res) => {
  let envVars = {};
  let envFileExists = false;
  let error = null;

  try {
    if (fs.existsSync(envFilePath)) {
      envFileExists = true;
      const content = fs.readFileSync(envFilePath, "utf8");
      envVars = parseEnvContent(content);
    } else if (fs.existsSync(envExamplePath)) {
      const content = fs.readFileSync(envExamplePath, "utf8");
      envVars = parseEnvContent(content);
    }
  } catch (e) {
    error = "Failed to read env file: " + e.message;
  }

  // Build HTML page
  const currentVars = {};
  for (const key of ALLOWED_VARS) {
    currentVars[key] = {
      current: envVars[key] || "",
      masked: maskValue(key, envVars[key] || "")
    };
  }

  const varsJson = JSON.stringify(currentVars).replace(/</g, "&lt;").replace(/>/g, "&gt;");

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Admin Panel - Env Variables</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #1a1a2e; color: #eee; min-height: 100vh; padding: 20px; }
    .container { max-width: 1000px; margin: 0 auto; }
    h1 { color: #00d4ff; margin-bottom: 10px; }
    .subtitle { color: #888; margin-bottom: 30px; }
    .error { background: #ff4444; color: white; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
    .success { background: #00aa55; color: white; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
    .file-status { background: #2a2a4e; padding: 10px 15px; border-radius: 6px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; }
    .file-status .exists { color: #00aa55; }
    .file-status .not-exists { color: #ff8800; }
    .var-row { background: #2a2a4e; border-radius: 8px; padding: 15px; margin-bottom: 12px; }
    .var-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
    .var-name { font-weight: 600; color: #00d4ff; font-family: monospace; }
    .var-toggle { background: #444; border: none; color: #fff; padding: 4px 10px; border-radius: 4px; cursor: pointer; font-size: 12px; }
    .var-toggle:hover { background: #555; }
    .var-input { width: 100%; background: #1a1a2e; border: 1px solid #444; border-radius: 6px; padding: 10px; color: #eee; font-family: monospace; resize: vertical; }
    .var-input:focus { outline: none; border-color: #00d4ff; }
    .var-display { background: #1a1a2e; padding: 10px; border-radius: 6px; font-family: monospace; word-break: break-all; color: #888; }
    .btn-row { display: flex; gap: 10px; margin-top: 20px; }
    .btn { padding: 12px 24px; border: none; border-radius: 8px; cursor: pointer; font-size: 14px; font-weight: 600; }
    .btn-save { background: #00d4ff; color: #1a1a2e; }
    .btn-save:hover { background: #00b8e6; }
    .btn-cancel { background: #444; color: #fff; }
    .btn-cancel:hover { background: #555; }
    .btn-refresh { background: #2a2a4e; color: #00d4ff; border: 1px solid #00d4ff; }
    .btn-refresh:hover { background: #3a3a5e; }
    .hidden { display: none; }
    .readonly-note { color: #ff8800; font-size: 12px; margin-top: 5px; }
    .new-var-section { background: #2a2a4e; border: 2px dashed #444; border-radius: 8px; padding: 20px; margin-bottom: 20px; text-align: center; }
    .new-var-section h3 { color: #888; margin-bottom: 15px; }
    .new-var-inputs { display: flex; gap: 10px; justify-content: center; flex-wrap: wrap; }
    .new-var-inputs input { padding: 10px; border-radius: 6px; border: 1px solid #444; background: #1a1a2e; color: #eee; }
    .new-var-inputs input:first-child { width: 200px; font-family: monospace; }
    .new-var-inputs input:last-child { width: 300px; }
    .btn-add { background: #00aa55; color: white; }
    .btn-add:hover { background: #008844; }
    .header-row { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 30px; }
    .header-left h1 { margin-bottom: 5px; }
    .header-left .subtitle { margin-bottom: 0; }
    .header-right { display: flex; align-items: center; gap: 10px; }
    .user-info { color: var(--text-secondary); font-size: 13px; }
    .btn-logout { background: #ff4757; color: white; padding: 8px 16px; border: none; border-radius: 6px; cursor: pointer; font-size: 13px; }
    .btn-logout:hover { background: #ff3344; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header-row">
      <div class="header-left">
        <h1>🔧 Admin Panel</h1>
        <p class="subtitle">Manage Environment Variables (.env.local)</p>
      </div>
      <div class="header-right">
        <span class="user-info" id="userInfo">Admin</span>
        <button class="btn btn-logout" onclick="logout()">🚪 Logout</button>
      </div>
    </div>

    <div id="error" class="error hidden"></div>
    <div id="success" class="success hidden"></div>

    <div class="file-status">
      <span>File: <code>${envFilePath}</code></span>
      <span class="${envFileExists ? 'exists' : 'not-exists'}">
        ${envFileExists ? '✓ File exists' : '○ File not found'}
      </span>
    </div>

    <div class="new-var-section">
      <h3>Add New Variable</h3>
      <div class="new-var-inputs">
        <input type="text" id="newKey" placeholder="VARIABLE_NAME">
        <input type="text" id="newValue" placeholder="value">
        <button class="btn btn-add" onclick="addNewVar()">Add</button>
      </div>
    </div>

    <div id="varsList"></div>

    <div class="btn-row">
      <button class="btn btn-save" onclick="saveAll()">💾 Save Changes</button>
      <button class="btn btn-cancel" onclick="resetChanges()">↺ Reset</button>
      <button class="btn btn-refresh" onclick="loadVars()">🔄 Reload</button>
    </div>
  </div>

  <script>
    const allowedVars = ${JSON.stringify(ALLOWED_VARS)};
    let envVars = ${varsJson};
    let originalVars = JSON.parse(${JSON.stringify(JSON.stringify(currentVars))});
    let isModified = false;

    function getVarType(key) {
      if (key.includes('KEY') || key.includes('SECRET') || key.includes('PASSWORD') || key.includes('TOKEN')) return 'password';
      if (key.includes('SERVICE_ACCOUNT') || key.includes('JSON')) return 'textarea';
      if (key.includes('URI') || key.includes('URL') || key.includes('ENDPOINT')) return 'url';
      return 'text';
    }

    function renderVars() {
      const container = document.getElementById('varsList');
      let html = '';

      for (const key of allowedVars) {
        const varData = envVars[key];
        const origData = originalVars[key];
        const hasChanged = varData && origData && varData.current !== origData.current;
        const varType = getVarType(key);
        const isJson = varType === 'textarea';

        html += \`
          <div class="var-row">
            <div class="var-header">
              <span class="var-name">\${key}</span>
              <button class="var-toggle" onclick="toggleEdit('\${key}')">
                \${isJson ? 'View/Edit JSON' : 'Edit'}
              </button>
            </div>
            \${isJson ?
              \`<div id="display-\${key}" class="var-display">\${varData.masked || '(empty)'}</div>\` :
              \`<div id="display-\${key}" class="var-display">\${varData.masked || '(empty)'}</div>\`
            }
            <div id="edit-\${key}" class="hidden" style="margin-top: 10px;">
              <textarea id="input-\${key}" class="var-input" rows="\${isJson ? 8 : 2}"
                placeholder="Enter value..." oninput="markModified('\${key}')">\${varData.current || ''}</textarea>
            </div>
            \${hasChanged ? '<div class="readonly-note">✎ Modified (unsaved)</div>' : ''}
          </div>
        \`;
      }

      container.innerHTML = html;
    }

    function toggleEdit(key) {
      const display = document.getElementById('display-' + key);
      const edit = document.getElementById('edit-' + key);
      const input = document.getElementById('input-' + key);

      if (edit.classList.contains('hidden')) {
        display.classList.add('hidden');
        edit.classList.remove('hidden');
        input.focus();
      } else {
        // Save the value before hiding
        envVars[key].current = input.value;
        envVars[key].masked = maskValue(key, input.value);
        display.classList.remove('hidden');
        edit.classList.add('hidden');
        renderVars();
      }
    }

    function maskValue(key, value) {
      if (!value) return '';
      if (key.includes('KEY') || key.includes('SECRET') || key.includes('PASSWORD') || key.includes('TOKEN')) {
        if (value.length > 8) {
          return value.substring(0, 4) + '****' + value.substring(value.length - 4);
        }
        return '****';
      }
      if (key.includes('SERVICE_ACCOUNT')) {
        return '[JSON Object]';
      }
      return value;
    }

    function markModified(key) {
      isModified = true;
    }

    function addNewVar() {
      const keyInput = document.getElementById('newKey');
      const valueInput = document.getElementById('newValue');
      const key = keyInput.value.trim().toUpperCase();
      const value = valueInput.value;

      if (!key) {
        alert('Please enter a variable name');
        return;
      }

      if (!/^[A-Z][A-Z0-9_]*$/.test(key)) {
        alert('Variable name must start with a letter and contain only uppercase letters, numbers, and underscores');
        return;
      }

      if (!allowedVars.includes(key)) {
        alert('This variable is not in the allowed list. Contact admin to add it.');
        return;
      }

      if (envVars[key]) {
        alert('Variable already exists. Use the edit function instead.');
        return;
      }

      envVars[key] = { current: value, masked: maskValue(key, value) };
      keyInput.value = '';
      valueInput.value = '';
      isModified = true;
      renderVars();
    }

    function saveAll() {
      // Collect all values from inputs
      for (const key of allowedVars) {
        const input = document.getElementById('input-' + key);
        if (input) {
          envVars[key].current = input.value;
        }
      }

      const varsToSave = {};
      for (const [key, data] of Object.entries(envVars)) {
        if (data.current) {
          varsToSave[key] = data.current;
        }
      }

      fetch('/dodo/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ vars: varsToSave })
      })
      .then(r => r.json())
      .then(data => {
        if (data.success) {
          showSuccess('Saved successfully! File: ' + data.path);
          originalVars = JSON.parse(JSON.stringify(envVars));
          isModified = false;
        } else {
          showError('Error: ' + data.error);
        }
      })
      .catch(e => showError('Save failed: ' + e.message));
    }

    function resetChanges() {
      if (isModified && !confirm('Discard all changes?')) return;
      envVars = JSON.parse(JSON.stringify(originalVars));
      isModified = false;
      renderVars();
    }

    function loadVars() {
      fetch('/dodo/load')
        .then(r => r.json())
        .then(data => {
          if (data.success) {
            const newVars = {};
            for (const key of allowedVars) {
              newVars[key] = {
                current: data.vars[key] || '',
                masked: maskValue(key, data.vars[key] || '')
              };
            }
            envVars = newVars;
            originalVars = JSON.parse(JSON.stringify(newVars));
            isModified = false;
            renderVars();
            showSuccess('Reloaded successfully');
          } else {
            showError('Load failed: ' + data.error);
          }
        })
        .catch(e => showError('Load failed: ' + e.message));
    }

    function logout() {
      if (!confirm('Are you sure you want to logout?')) return;
      fetch('/dodo/api/logout', { method: 'POST' })
        .then(() => window.location.href = '/dodo/login')
        .catch(() => window.location.href = '/dodo/login');
    }

    // Check auth status on load
    fetch('/dodo/api/check')
      .then(r => r.json())
      .then(data => {
        if (!data.authenticated) {
          window.location.href = '/dodo/login';
        } else {
          document.getElementById('userInfo').textContent = 'UID: ' + (data.uid || 'admin').substring(0, 12) + '...';
        }
      })
      .catch(() => window.location.href = '/dodo/login');

    function showError(msg) {
      const el = document.getElementById('error');
      el.textContent = msg;
      el.classList.remove('hidden');
      document.getElementById('success').classList.add('hidden');
    }

    function showSuccess(msg) {
      const el = document.getElementById('success');
      el.textContent = msg;
      el.classList.remove('hidden');
      document.getElementById('error').classList.add('hidden');
    }

    // Initial render
    renderVars();
  </script>
</body>
</html>`;

  res.set("Cache-Control", "no-store, max-age=0");
  res.type("html").send(html);
});

// GET /load - Load current env vars
router.get("/load", (req, res) => {
  try {
    let envVars = {};

    if (fs.existsSync(envFilePath)) {
      const content = fs.readFileSync(envFilePath, "utf8");
      envVars = parseEnvContent(content);
    } else if (fs.existsSync(envExamplePath)) {
      const content = fs.readFileSync(envExamplePath, "utf8");
      envVars = parseEnvContent(content);
    }

    // Only return allowed vars
    const filtered = {};
    for (const key of ALLOWED_VARS) {
      filtered[key] = envVars[key] || "";
    }

    res.json({ success: true, vars: filtered });
  } catch (e) {
    res.json({ success: false, error: e.message });
  }
});

// POST /save - Save env vars
router.post("/save", (req, res) => {
  try {
    const { vars } = req.body;

    if (!vars || typeof vars !== "object") {
      return res.json({ success: false, error: "Invalid data" });
    }

    // Validate all keys are allowed
    for (const key of Object.keys(vars)) {
      if (!ALLOWED_VARS.includes(key)) {
        return res.json({ success: false, error: `Key "${key}" is not allowed` });
      }
    }

    // Read existing content to preserve comments and formatting
    let existingContent = "";
    if (fs.existsSync(envFilePath)) {
      existingContent = fs.readFileSync(envFilePath, "utf8");
    }

    // Parse existing content
    const existingVars = parseEnvContent(existingContent);

    // Merge with new values
    const merged = { ...existingVars };
    for (const [key, value] of Object.entries(vars)) {
      if (value !== "") {
        merged[key] = value;
      } else {
        delete merged[key];
      }
    }

    // Serialize back
    const newContent = serializeEnvVars(merged);

    // Write to file
    fs.writeFileSync(envFilePath, newContent, "utf8");

    res.json({ success: true, path: envFilePath });
  } catch (e) {
    res.json({ success: false, error: e.message });
  }
});

module.exports = router;
