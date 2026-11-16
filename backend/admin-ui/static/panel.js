const statusEl = document.getElementById('status');
const assetGrid = document.getElementById('assetGrid');
const fileInput = document.getElementById('fileInput');

const state = {
  assets: [],
  pendingAsset: null,
  page: 1,
  pageSize: 50,
  txTotal: 0,
  backupsAsset: null,
  activeTab: 'assets',
  portfolio: null,
  ragEvents: [],
  ragUnanswered: []
};

const rupiah = new Intl.NumberFormat('id-ID', {
  style: 'currency',
  currency: 'IDR',
  maximumFractionDigits: 0
});

function $(id) {
  return document.getElementById(id);
}

function showStatus(message, type) {
  statusEl.textContent = message;
  statusEl.className = 'status visible ' + type;
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return '-';
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function formatDate(value) {
  if (!value) return '-';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleString();
}

function formatDay(value) {
  if (!value) return '-';
  return String(value).slice(0, 10);
}

function cell(content, className) {
  const td = document.createElement('td');
  if (className) td.className = className;
  if (content instanceof Node) td.appendChild(content);
  else td.textContent = content === null || content === undefined ? '-' : String(content);
  return td;
}

function tag(text, kind) {
  const span = document.createElement('span');
  span.className = 'tag' + (kind ? ' ' + kind : '');
  span.textContent = text;
  return span;
}

function emptyRow(tbody, columns, message) {
  tbody.innerHTML = '';
  const tr = document.createElement('tr');
  const td = document.createElement('td');
  td.colSpan = columns;
  td.className = 'empty';
  td.textContent = message;
  tr.appendChild(td);
  tbody.appendChild(tr);
}

function actionButton(label, className, onClick) {
  const button = document.createElement('button');
  button.className = 'btn ' + className;
  button.textContent = label;
  button.addEventListener('click', onClick);
  return button;
}

function formatDuration(seconds) {
  const total = Math.max(0, Math.round(Number(seconds) || 0));
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (days > 0) return days + 'd ' + hours + 'h';
  if (hours > 0) return hours + 'h ' + minutes + 'm';
  if (minutes > 0) return minutes + 'm ' + (total % 60) + 's';
  return total + 's';
}

async function api(url, options) {
  const res = await fetch(url, Object.assign({ cache: 'no-store' }, options));
  if (res.status === 401) {
    window.location.href = '/dodo/login';
    throw new Error('Not authenticated');
  }

  let data = {};
  try {
    data = await res.json();
  } catch (err) {
    data = {};
  }

  if (!res.ok || data.success === false) {
    throw new Error(data.error || 'Request failed (' + res.status + ')');
  }
  return data;
}

/* Tabs */

const loaders = {
  assets: loadAssets,
  content: loadContent,
  overview: loadOverview,
  transactions: loadTransactions,
  users: loadUsers,
  ai: loadAiUsage,
  rag: loadRag,
  health: loadHealth,
  audit: loadAudit
};

function activateTab(name) {
  state.activeTab = name;
  document.querySelectorAll('.tab').forEach(function (tab) {
    tab.classList.toggle('active', tab.dataset.tab === name);
  });
  document.querySelectorAll('.section').forEach(function (section) {
    section.classList.toggle('active', section.id === 'section-' + name);
  });

  const loader = loaders[name];
  if (!loader) return;
  loader().catch(function (err) {
    showStatus('Failed to load ' + name + ': ' + err.message, 'error');
  });
}

document.querySelectorAll('.tab').forEach(function (tab) {
  tab.addEventListener('click', function () {
    activateTab(tab.dataset.tab);
  });
});

/* Assets */

function assetKind(asset) {
  if (asset.preview) return 'image';
  return (asset.ext || '').replace('.', '');
}

function createAssetCard(asset) {
  const card = document.createElement('div');
  card.className = 'asset-card';

  const thumb = document.createElement('div');
  thumb.className = 'thumb';
  if (asset.preview) {
    const img = document.createElement('img');
    img.src = asset.url + '?v=' + Math.round(asset.version);
    img.alt = asset.name;
    img.loading = 'lazy';
    thumb.appendChild(img);
  } else {
    const badge = document.createElement('span');
    badge.className = 'ext';
    badge.textContent = (asset.ext || 'file').replace('.', '').toUpperCase();
    thumb.appendChild(badge);
  }

  const body = document.createElement('div');
  body.className = 'asset-body';

  const name = document.createElement('div');
  name.className = 'asset-name';
  name.textContent = asset.name;

  const assetPath = document.createElement('div');
  assetPath.className = 'asset-path';
  assetPath.textContent = asset.path;

  const meta = document.createElement('div');
  meta.className = 'asset-meta';
  meta.textContent = formatBytes(asset.size) + ' - updated ' + formatDate(asset.modifiedAt);

  const actions = document.createElement('div');
  actions.className = 'asset-actions';

  const replaceBtn = document.createElement('button');
  replaceBtn.className = 'btn btn-small btn-primary';
  replaceBtn.textContent = 'Replace';
  replaceBtn.disabled = !asset.replaceable;
  replaceBtn.addEventListener('click', function () {
    state.pendingAsset = asset;
    fileInput.accept = asset.ext;
    fileInput.value = '';
    fileInput.click();
  });

  const backupsBtn = document.createElement('button');
  backupsBtn.className = 'btn btn-small btn-ghost';
  backupsBtn.textContent = 'Backups';
  backupsBtn.disabled = !asset.replaceable;
  backupsBtn.addEventListener('click', function () {
    openBackups(asset);
  });

  const deleteBtn = document.createElement('button');
  deleteBtn.className = 'btn btn-small btn-danger';
  deleteBtn.textContent = 'Delete';
  deleteBtn.addEventListener('click', function () {
    deleteAsset(asset);
  });

  actions.appendChild(replaceBtn);
  actions.appendChild(backupsBtn);
  actions.appendChild(deleteBtn);
  body.appendChild(name);
  body.appendChild(assetPath);
  body.appendChild(meta);
  body.appendChild(actions);
  card.appendChild(thumb);
  card.appendChild(body);
  return card;
}

function renderAssets() {
  const query = $('assetSearch').value.trim().toLowerCase();
  const type = $('assetType').value;
  const filtered = state.assets.filter(function (asset) {
    const matchesQuery = asset.path.toLowerCase().indexOf(query) !== -1;
    const matchesType = type === 'all' || assetKind(asset) === type;
    return matchesQuery && matchesType;
  });

  assetGrid.innerHTML = '';
  $('assetCount').textContent = filtered.length + ' of ' + state.assets.length + ' assets';

  if (filtered.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'No assets found.';
    assetGrid.appendChild(empty);
    return;
  }

  filtered.forEach(function (asset) {
    assetGrid.appendChild(createAssetCard(asset));
  });
}

async function loadAssets() {
  const data = await api('/dodo/api/assets');
  state.assets = data.assets || [];
  renderAssets();
}

async function replaceAsset(file) {
  const asset = state.pendingAsset;
  state.pendingAsset = null;
  if (!file || !asset) return;

  const dotIndex = file.name.lastIndexOf('.');
  const ext = dotIndex >= 0 ? file.name.slice(dotIndex).toLowerCase() : '';

  if (ext !== asset.ext) {
    showStatus('Extension must match the existing file (' + asset.ext + ').', 'error');
    return;
  }

  if (!confirm('Replace "' + asset.path + '" with "' + file.name + '"? A backup will be kept.')) {
    return;
  }

  showStatus('Uploading ' + file.name + '...', 'info');

  try {
    const data = await api('/dodo/api/assets/replace?file=' + encodeURIComponent(asset.path), {
      method: 'POST',
      headers: { 'Content-Type': 'application/octet-stream' },
      body: file
    });
    showStatus('Replaced ' + asset.path + ' (' + formatBytes(data.size) + ').', 'success');
    await loadAssets();
  } catch (err) {
    showStatus('Upload failed: ' + err.message, 'error');
  }
}

async function deleteAsset(asset) {
  if (!confirm('Delete "' + asset.path + '"? A backup will be kept so you can restore it.')) {
    return;
  }

  try {
    await api('/dodo/api/assets?file=' + encodeURIComponent(asset.path), { method: 'DELETE' });
    showStatus('Deleted ' + asset.path + '.', 'success');
    await loadAssets();
  } catch (err) {
    showStatus('Delete failed: ' + err.message, 'error');
  }
}

function openBackups(asset) {
  state.backupsAsset = asset;
  const dialog = $('backupsDialog');
  $('backupsTitle').textContent = 'Backups: ' + asset.path;
  const list = $('backupsList');
  list.textContent = 'Loading...';
  dialog.showModal();

  api('/dodo/api/assets/backups?file=' + encodeURIComponent(asset.path))
    .then(function (data) {
      list.innerHTML = '';
      const backups = data.backups || [];
      if (backups.length === 0) {
        list.textContent = 'No backups yet.';
        return;
      }

      backups.forEach(function (backup) {
        const row = document.createElement('div');
        row.className = 'backup-row';

        const meta = document.createElement('div');
        meta.className = 'meta';
        meta.textContent = formatDate(backup.createdAt) + ' - ' + formatBytes(backup.size);

        const restoreBtn = document.createElement('button');
        restoreBtn.className = 'btn btn-small btn-primary';
        restoreBtn.textContent = 'Restore';
        restoreBtn.addEventListener('click', function () {
          restoreBackup(asset, backup);
        });

        row.appendChild(meta);
        row.appendChild(restoreBtn);
        list.appendChild(row);
      });
    })
    .catch(function (err) {
      list.textContent = 'Failed to load backups: ' + err.message;
    });
}

async function restoreBackup(asset, backup) {
  if (!confirm('Restore "' + asset.path + '" from ' + formatDate(backup.createdAt) + '?')) return;

  try {
    await api('/dodo/api/assets/restore', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ file: asset.path, backup: backup.id })
    });
    $('backupsDialog').close();
    showStatus('Restored ' + asset.path + '.', 'success');
    await loadAssets();
  } catch (err) {
    showStatus('Restore failed: ' + err.message, 'error');
  }
}

/* Overview */

function statCard(label, value, hint) {
  const card = document.createElement('div');
  card.className = 'stat';

  const labelEl = document.createElement('div');
  labelEl.className = 'label';
  labelEl.textContent = label;

  const valueEl = document.createElement('div');
  valueEl.className = 'value';
  valueEl.textContent = value;

  const hintEl = document.createElement('div');
  hintEl.className = 'hint';
  hintEl.textContent = hint || '';

  card.appendChild(labelEl);
  card.appendChild(valueEl);
  card.appendChild(hintEl);
  return card;
}

async function loadOverview() {
  const data = await api('/dodo/api/overview');
  const totals = data.totals || {};

  const stats = $('overviewStats');
  stats.innerHTML = '';
  stats.appendChild(statCard('Total spending', rupiah.format(totals.totalAmount || 0), 'All recorded expenses'));
  stats.appendChild(statCard('Transactions', String(totals.expenses || 0), 'Rows in expenses'));
  stats.appendChild(statCard('Owners', String(totals.owners || 0), 'Distinct Firebase UIDs'));
  stats.appendChild(statCard('Last 30 days', rupiah.format(totals.totalAmount30d || 0), 'Created in the last 30 days'));

  const categoryBody = $('categoryBody');
  categoryBody.innerHTML = '';
  if ((data.categories || []).length === 0) {
    emptyRow(categoryBody, 3, 'No expenses yet.');
  } else {
    data.categories.forEach(function (row) {
      const tr = document.createElement('tr');
      tr.appendChild(cell(row.category));
      tr.appendChild(cell(String(row.count), 'right'));
      tr.appendChild(cell(rupiah.format(row.total), 'right'));
      categoryBody.appendChild(tr);
    });
  }

  const dailyBody = $('dailyBody');
  dailyBody.innerHTML = '';
  if ((data.daily || []).length === 0) {
    emptyRow(dailyBody, 3, 'No expenses in the last 14 days.');
  } else {
    data.daily.forEach(function (row) {
      const tr = document.createElement('tr');
      tr.appendChild(cell(formatDay(row.date)));
      tr.appendChild(cell(String(row.count), 'right'));
      tr.appendChild(cell(rupiah.format(row.total), 'right'));
      dailyBody.appendChild(tr);
    });
  }

  const monthlyBody = $('monthlyBody');
  monthlyBody.innerHTML = '';
  const monthly = data.monthly || [];
  const maxMonthTotal = monthly.reduce(function (max, row) {
    return Math.max(max, row.total);
  }, 0);

  if (monthly.length === 0) {
    emptyRow(monthlyBody, 4, 'No expenses in the last 12 months.');
  } else {
    monthly.forEach(function (row) {
      const tr = document.createElement('tr');
      const share = document.createElement('div');
      share.className = 'bar';
      const fill = document.createElement('span');
      fill.style.width = (maxMonthTotal > 0 ? (row.total / maxMonthTotal) * 100 : 0) + '%';
      share.appendChild(fill);
      tr.appendChild(cell(row.month));
      tr.appendChild(cell(String(row.count), 'right'));
      tr.appendChild(cell(rupiah.format(row.total), 'right'));
      tr.appendChild(cell(share));
      monthlyBody.appendChild(tr);
    });
  }
}

/* Transactions */

function txQuery() {
  const params = new URLSearchParams();
  const search = $('txSearch').value.trim();
  const owner = $('txOwner').value.trim();
  const from = $('txFrom').value;
  const to = $('txTo').value;
  if (search) params.set('q', search);
  if (owner) params.set('owner', owner);
  if (from) params.set('from', from);
  if (to) params.set('to', to);
  return params;
}

async function loadTransactions() {
  const params = txQuery();
  params.set('page', state.page);
  params.set('pageSize', state.pageSize);

  const data = await api('/dodo/api/expenses?' + params.toString());
  state.txTotal = data.total || 0;

  const body = $('expensesBody');
  body.innerHTML = '';
  if ((data.expenses || []).length === 0) {
    emptyRow(body, 7, 'No transactions match these filters.');
  } else {
    data.expenses.forEach(function (expense) {
      const tr = document.createElement('tr');
      tr.appendChild(cell(formatDay(expense.date)));
      tr.appendChild(cell(expense.name));
      tr.appendChild(cell(expense.category));
      tr.appendChild(cell(expense.type));
      tr.appendChild(cell(rupiah.format(expense.amount), 'right'));
      tr.appendChild(cell(expense.ownerId, 'mono'));

      const actions = document.createElement('div');
      actions.className = 'row-actions';
      actions.appendChild(
        actionButton('Edit', 'btn-small btn-ghost', function () {
          openExpenseDialog(expense);
        })
      );
      actions.appendChild(
        actionButton('Delete', 'btn-small btn-danger', function () {
          deleteExpense(expense);
        })
      );
      tr.appendChild(cell(actions));
      body.appendChild(tr);
    });
  }

  const totalPages = Math.max(1, Math.ceil(state.txTotal / state.pageSize));
  $('txPageInfo').textContent = 'Page ' + state.page + ' of ' + totalPages + ' - ' + state.txTotal + ' transactions';
  $('txPrevBtn').disabled = state.page <= 1;
  $('txNextBtn').disabled = state.page >= totalPages;
}

function exportCsv() {
  const params = txQuery();
  window.location.href = '/dodo/api/expenses/export.csv?' + params.toString();
}

function openExpenseDialog(expense) {
  $('expenseOwner').value = expense.ownerId;
  $('expenseLocalId').value = expense.localId;
  $('expenseName').value = expense.name || '';
  $('expenseAmount').value = expense.amount || 0;
  $('expenseCategory').value = expense.category || '';
  $('expenseType').value = expense.type || 'unexpected';
  $('expenseDate').value = formatDay(expense.date);
  $('expenseDialog').showModal();
}

async function saveExpense(event) {
  event.preventDefault();
  const owner = $('expenseOwner').value;
  const localId = $('expenseLocalId').value;

  const payload = {
    name: $('expenseName').value.trim(),
    amount: Number($('expenseAmount').value),
    category: $('expenseCategory').value.trim(),
    type: $('expenseType').value,
    date: $('expenseDate').value
  };

  try {
    await api(
      '/dodo/api/expenses/' +
        encodeURIComponent(owner) +
        '/' +
        encodeURIComponent(localId),
      {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      }
    );
    $('expenseDialog').close();
    showStatus('Expense updated. Live clients refresh immediately.', 'success');
    await loadTransactions();
  } catch (err) {
    showStatus('Update failed: ' + err.message, 'error');
  }
}

async function deleteExpense(expense) {
  const label = expense.name + ' (' + rupiah.format(expense.amount) + ')';
  if (!confirm('Delete ' + label + ' for ' + expense.ownerId + '? This removes it for the owner too.')) {
    return;
  }

  try {
    await api(
      '/dodo/api/expenses/' +
        encodeURIComponent(expense.ownerId) +
        '/' +
        encodeURIComponent(expense.localId),
      { method: 'DELETE' }
    );
    showStatus('Expense deleted.', 'success');
    await loadTransactions();
  } catch (err) {
    showStatus('Delete failed: ' + err.message, 'error');
  }
}

function filterByOwner(ownerId) {
  $('txOwner').value = ownerId;
  $('txSearch').value = '';
  $('txFrom').value = '';
  $('txTo').value = '';
  state.page = 1;
  activateTab('transactions');
}

/* Users */

async function loadUsers() {
  const ownersBody = $('ownersBody');
  ownersBody.innerHTML = '';
  const firebaseBody = $('firebaseUsersBody');
  firebaseBody.innerHTML = '';
  const devicesBody = $('devicesBody');
  devicesBody.innerHTML = '';

  try {
    const data = await api('/dodo/api/owners');
    if ((data.owners || []).length === 0) {
      emptyRow(ownersBody, 5, 'No expense owners yet.');
    } else {
      data.owners.forEach(function (owner) {
        const tr = document.createElement('tr');
        tr.className = 'clickable';
        tr.title = 'Show transactions for this owner';
        tr.addEventListener('click', function () {
          filterByOwner(owner.ownerId);
        });
        tr.appendChild(cell(owner.ownerId, 'mono'));
        tr.appendChild(cell(String(owner.expenseCount), 'right'));
        tr.appendChild(cell(rupiah.format(owner.totalAmount), 'right'));
        tr.appendChild(cell(formatDay(owner.lastExpenseDate)));
        tr.appendChild(
          cell(
            actionButton('View', 'btn-small btn-ghost', function (event) {
              event.stopPropagation();
              filterByOwner(owner.ownerId);
            })
          )
        );
        ownersBody.appendChild(tr);
      });
    }
  } catch (err) {
    emptyRow(ownersBody, 5, 'Failed to load owners: ' + err.message);
  }

  try {
    const data = await api('/dodo/api/devices');
    if ((data.devices || []).length === 0) {
      emptyRow(devicesBody, 6, 'No device syncs yet. Devices appear after the mobile app syncs once.');
    } else {
      data.devices.forEach(function (device) {
        const tr = document.createElement('tr');
        tr.appendChild(cell(device.ownerId, 'mono'));
        tr.appendChild(cell(device.deviceName || device.deviceId, 'mono'));
        tr.appendChild(cell(device.platform || '-'));
        tr.appendChild(cell(device.appVersion || '-'));
        tr.appendChild(
          cell(
            device.expenseCount === null || device.expenseCount === undefined
              ? '-'
              : String(device.expenseCount),
            'right'
          )
        );
        tr.appendChild(cell(formatDate(device.lastSyncAt)));
        devicesBody.appendChild(tr);
      });
    }
  } catch (err) {
    emptyRow(devicesBody, 6, 'Failed to load devices: ' + err.message);
  }

  try {
    const data = await api('/dodo/api/firebase-users');
    if ((data.users || []).length === 0) {
      emptyRow(firebaseBody, 5, 'No Firebase users found.');
    } else {
      data.users.forEach(function (user) {
        const tr = document.createElement('tr');
        tr.appendChild(cell(user.uid, 'mono'));
        tr.appendChild(cell(user.email || '-'));
        tr.appendChild(cell(user.displayName || '-'));
        tr.appendChild(cell(tag(user.disabled ? 'disabled' : 'active', user.disabled ? 'error' : 'success')));
        tr.appendChild(cell(formatDate(user.lastSignInAt)));
        firebaseBody.appendChild(tr);
      });
    }
  } catch (err) {
    emptyRow(firebaseBody, 5, 'Firebase users unavailable: ' + err.message);
  }
}

/* AI usage */

async function loadAiUsage() {
  const data = await api('/dodo/api/ai-usage');

  const providersBody = $('aiProvidersBody');
  providersBody.innerHTML = '';
  if ((data.providers || []).length === 0) {
    emptyRow(providersBody, 4, 'No AI events recorded yet.');
  } else {
    data.providers.forEach(function (row) {
      const tr = document.createElement('tr');
      tr.appendChild(cell(row.provider));
      tr.appendChild(cell(tag(row.status, row.status === 'success' ? 'success' : 'error')));
      tr.appendChild(cell(String(row.count), 'right'));
      tr.appendChild(cell(row.avg_duration_ms === null ? '-' : row.avg_duration_ms + ' ms', 'right'));
      providersBody.appendChild(tr);
    });
  }

  const recentBody = $('aiRecentBody');
  recentBody.innerHTML = '';
  if ((data.recent || []).length === 0) {
    emptyRow(recentBody, 5, 'No AI events recorded yet.');
  } else {
    data.recent.forEach(function (row) {
      const tr = document.createElement('tr');
      tr.appendChild(cell(formatDate(row.created_at)));
      tr.appendChild(cell(row.provider));
      tr.appendChild(cell(tag(row.status, row.status === 'success' ? 'success' : 'error')));
      tr.appendChild(cell(row.duration_ms === null ? '-' : row.duration_ms + ' ms', 'right'));
      tr.appendChild(cell(row.error || '-'));
      recentBody.appendChild(tr);
    });
  }
}

/* Portfolio content */

function renderPortfolioPreview(content) {
  const list = $('portfolioPreview');
  list.innerHTML = '';
  const profile = content.profile || {};
  const apk = content.apk || {};
  const projects = Array.isArray(content.projects) ? content.projects : [];
  const experience = Array.isArray(content.experience) ? content.experience : [];

  function line(label, value) {
    const row = document.createElement('div');
    row.className = 'preview-row';
    const labelEl = document.createElement('span');
    labelEl.className = 'preview-label';
    labelEl.textContent = label;
    const valueEl = document.createElement('strong');
    valueEl.textContent = value === null || value === undefined || value === '' ? '-' : String(value);
    row.appendChild(labelEl);
    row.appendChild(valueEl);
    list.appendChild(row);
  }

  line('Name', profile.name);
  line('Role', profile.role);
  line('Location', profile.location);
  line('Status', profile.status);
  line('Projects', projects.length + ' in the extra grid');
  line('Experience', experience.length + ' timeline entries');
  line('APK', apk.version ? 'v' + apk.version : 'not set');
  line('APK size', apk.size_bytes ? formatBytes(apk.size_bytes) : 'not set');
  line('APK file', apk.url);

  const note = document.createElement('p');
  note.className = 'muted preview-note';
  note.textContent = 'Changes appear on / and /projects/unmurce after saving. The static HTML is only the fallback.';
  list.appendChild(note);
}

async function loadContent() {
  const data = await api('/dodo/api/portfolio');
  state.portfolio = data.content || {};
  $('portfolioJson').value = JSON.stringify(state.portfolio, null, 2);
  renderPortfolioPreview(state.portfolio);
}

function parsePortfolioJson() {
  try {
    return JSON.parse($('portfolioJson').value);
  } catch (err) {
    showStatus('Invalid JSON: ' + err.message, 'error');
    return null;
  }
}

function formatPortfolioJson() {
  const parsed = parsePortfolioJson();
  if (!parsed) return;
  $('portfolioJson').value = JSON.stringify(parsed, null, 2);
  renderPortfolioPreview(parsed);
  showStatus('JSON formatted.', 'success');
}

async function saveContent() {
  const parsed = parsePortfolioJson();
  if (!parsed) return;

  try {
    await api('/dodo/api/portfolio', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: parsed })
    });
    state.portfolio = parsed;
    renderPortfolioPreview(parsed);
    showStatus('Portfolio content saved. Public pages now render this data.', 'success');
  } catch (err) {
    showStatus('Save failed: ' + err.message, 'error');
  }
}

/* RAG chatbot monitoring */

function shortText(value, max) {
  const text = String(value || '');
  return text.length > max ? text.slice(0, max - 1) + '…' : text;
}

function voteText(event) {
  if (event.feedback === 'up') return '👍';
  if (event.feedback === 'down') return '👎';
  return '-';
}

function needsAttention(event) {
  return (!event.answered || event.feedback === 'down') && !event.resolvedAt;
}

function renderRagTable(body, events, mode) {
  body.innerHTML = '';
  const columns = mode === 'queue' ? 5 : 7;

  if (events.length === 0) {
    emptyRow(
      body,
      columns,
      mode === 'queue' ? 'No unanswered questions. The bot is covering the current traffic.' : 'No chat events yet.'
    );
    return;
  }

  events.forEach(function (event) {
    const tr = document.createElement('tr');

    tr.appendChild(cell(formatDate(event.createdAt)));
    const question = cell(shortText(event.question, 120));
    question.title = event.question || '';
    tr.appendChild(question);
    const answer = cell(shortText(event.answer, 160));
    answer.title = event.answer || '';
    tr.appendChild(answer);

    if (mode !== 'queue') {
      tr.appendChild(cell(tag(event.provider, event.provider === 'groq' ? 'success' : undefined)));
      tr.appendChild(
        cell(event.latencyMs === null ? '-' : event.latencyMs + ' ms', 'right')
      );
      tr.appendChild(cell(voteText(event)));
    } else {
      tr.appendChild(cell(voteText(event)));
    }

    const actions = document.createElement('div');
    actions.className = 'row-actions';
    actions.appendChild(
      actionButton('Add to KB', 'btn-small btn-primary', function () {
        openRagAddDialog(event);
      })
    );
    if (needsAttention(event)) {
      actions.appendChild(
        actionButton('Dismiss', 'btn-small btn-ghost', function () {
          resolveRagQuestion(event);
        })
      );
    }
    tr.appendChild(cell(actions));
    body.appendChild(tr);
  });
}

async function loadRag() {
  const results = await Promise.all([
    api('/dodo/api/rag/stats'),
    api('/dodo/api/rag/events?limit=100'),
    api('/dodo/api/rag/events?limit=100&unanswered=1'),
    api('/dodo/api/rag/knowledge')
  ]);

  const stats = results[0].totals || {};
  const statsEl = $('ragStats');
  statsEl.innerHTML = '';
  statsEl.appendChild(statCard('Questions logged', String(stats.total || 0), 'All time'));
  statsEl.appendChild(statCard('Last 7 days', String(stats.total7d || 0), 'Recent traffic'));
  statsEl.appendChild(statCard('Helpful votes', '👍 ' + (stats.up || 0) + ' / 👎 ' + (stats.down || 0), 'Visitor feedback'));
  statsEl.appendChild(statCard('Unanswered', String(stats.unanswered || 0), 'Queue that needs a FAQ'));
  statsEl.appendChild(
    statCard(
      'Avg latency',
      stats.avgLatencyMs === null || stats.avgLatencyMs === undefined ? '-' : stats.avgLatencyMs + ' ms',
      'Request to reply'
    )
  );
  const providers = results[0].providers || [];
  statsEl.appendChild(
    statCard(
      'Providers',
      providers.length === 0
        ? '-'
        : providers.map(function (item) {
            return item.provider + ' ' + item.count;
          }).join(' · '),
      'Answers by provider'
    )
  );

  state.ragEvents = results[1].events || [];
  state.ragUnanswered = results[2].events || [];
  renderRagTable($('ragEventsBody'), state.ragEvents, 'recent');
  renderRagTable($('ragUnansweredBody'), state.ragUnanswered, 'queue');
  $('ragKnowledgeJson').value = JSON.stringify(results[3].knowledge || {}, null, 2);
}

function keywordsFromQuestion(question) {
  const stopWords = new Set([
    'what', 'who', 'when', 'where', 'why', 'how', 'does', 'your', 'you',
    'the', 'and', 'for', 'with', 'about', 'this', 'that', 'are', 'can',
    'apa', 'siapa', 'kapan', 'dimana', 'bagaimana', 'yang', 'dan', 'untuk',
    'dengan', 'tentang', 'bisa', 'kamu', 'saya'
  ]);
  const words = String(question || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, ' ')
    .split(/\s+/)
    .filter(function (word) {
      return word.length > 3 && !stopWords.has(word);
    });
  return Array.from(new Set(words)).slice(0, 6);
}

function openRagAddDialog(event) {
  $('ragAddEventId').value = event.id;
  $('ragAddQuestion').value = event.question || '';
  $('ragAddAnswer').value = event.answer || '';
  $('ragAddKeywords').value = keywordsFromQuestion(event.question).join(', ');
  $('ragAddDialog').showModal();
}

async function saveRagKnowledge() {
  let parsed;
  try {
    parsed = JSON.parse($('ragKnowledgeJson').value);
  } catch (err) {
    showStatus('Invalid knowledge JSON: ' + err.message, 'error');
    return;
  }

  try {
    await api('/dodo/api/rag/knowledge', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ knowledge: parsed })
    });
    showStatus('Knowledge base saved. New chats use it immediately.', 'success');
  } catch (err) {
    showStatus('Save failed: ' + err.message, 'error');
  }
}

async function addRagKnowledgeEntry(event) {
  event.preventDefault();
  const id = $('ragAddEventId').value;

  try {
    const data = await api(
      '/dodo/api/rag/events/' + encodeURIComponent(id) + '/add-to-knowledge',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          question: $('ragAddQuestion').value.trim(),
          answer: $('ragAddAnswer').value.trim(),
          keywords: $('ragAddKeywords').value
        })
      }
    );
    $('ragAddDialog').close();
    showStatus('FAQ added. Knowledge base now has ' + data.faqs + ' entries.', 'success');
    await loadRag();
  } catch (err) {
    showStatus('Could not add FAQ: ' + err.message, 'error');
  }
}

async function resolveRagQuestion(event) {
  try {
    await api('/dodo/api/rag/events/' + encodeURIComponent(event.id) + '/resolve', {
      method: 'POST'
    });
    showStatus('Question dismissed from the queue.', 'success');
    await loadRag();
  } catch (err) {
    showStatus('Could not dismiss question: ' + err.message, 'error');
  }
}

/* Health */

function healthRow(body, label, value, status) {
  const tr = document.createElement('tr');
  tr.appendChild(cell(label));
  if (status) {
    tr.appendChild(cell(tag(value, status)));
  } else {
    tr.appendChild(cell(value));
  }
  body.appendChild(tr);
}

async function loadHealth() {
  const data = await api('/dodo/api/health');
  const health = data.health || {};
  const database = health.database || {};
  const firebase = health.firebase || {};
  const backups = health.backups || {};
  const runtime = health.runtime || {};

  const statsEl = $('healthStats');
  statsEl.innerHTML = '';
  statsEl.appendChild(
    statCard(
      'Database',
      database.ok ? 'Online' : 'DOWN',
      database.ok ? (database.latencyMs + ' ms ping') : database.error || 'Unavailable'
    )
  );
  statsEl.appendChild(
    statCard(
      'Firebase Admin',
      firebase.initialized ? 'Initialized' : 'Not initialized',
      firebase.projectId || 'Check FIREBASE_SERVICE_ACCOUNT_JSON'
    )
  );
  statsEl.appendChild(
    statCard(
      'Backups',
      formatBytes(backups.totalBytes || 0),
      (backups.count || 0) + ' files' + (backups.latestAt ? ' · newest ' + formatDate(backups.latestAt) : '')
    )
  );
  statsEl.appendChild(
    statCard(
      'Running commit',
      runtime.shortCommit || 'unknown',
      (runtime.branch || 'no branch') + (runtime.dirty ? ' · dirty tree' : '')
    )
  );
  statsEl.appendChild(
    statCard('Uptime', formatDuration(runtime.uptimeSeconds), 'Node ' + (runtime.nodeVersion || '-'))
  );

  const envBody = $('healthEnvBody');
  envBody.innerHTML = '';
  (health.env || []).forEach(function (item) {
    healthRow(envBody, item.key, item.configured ? 'configured' : 'missing', item.configured ? 'success' : 'error');
  });

  const runtimeBody = $('healthRuntimeBody');
  runtimeBody.innerHTML = '';
  healthRow(runtimeBody, 'Commit', runtime.commit || 'unknown');
  healthRow(runtimeBody, 'Message', runtime.message || '-');
  healthRow(runtimeBody, 'Branch', runtime.branch || '-');
  healthRow(runtimeBody, 'Working tree', runtime.dirty === null ? 'unknown' : runtime.dirty ? 'uncommitted changes' : 'clean');
  healthRow(runtimeBody, 'Node', runtime.nodeVersion || '-');
  healthRow(runtimeBody, 'Environment', runtime.nodeEnv || '-');
  healthRow(runtimeBody, 'PID', runtime.pid === undefined ? '-' : String(runtime.pid));
  healthRow(runtimeBody, 'RSS memory', formatBytes(runtime.memoryRssBytes || 0));
  healthRow(runtimeBody, 'Uptime', formatDuration(runtime.uptimeSeconds));
  healthRow(runtimeBody, 'Missing env', (health.missingEnv || []).join(', ') || 'none');
}

/* Audit */

async function loadAudit() {
  const data = await api('/dodo/api/audit?limit=100');
  const body = $('auditBody');
  body.innerHTML = '';

  if ((data.logs || []).length === 0) {
    emptyRow(body, 6, 'No admin actions recorded yet.');
    return;
  }

  data.logs.forEach(function (log) {
    const tr = document.createElement('tr');
    tr.appendChild(cell(formatDate(log.createdAt)));
    tr.appendChild(cell(log.actor, 'mono'));
    tr.appendChild(cell(log.action));
    tr.appendChild(cell(log.target || '-', 'mono'));
    tr.appendChild(cell(JSON.stringify(log.detail || {}), 'mono'));
    tr.appendChild(cell(log.ip || '-', 'mono'));
    body.appendChild(tr);
  });
}

/* Events */

$('assetSearch').addEventListener('input', renderAssets);
$('assetType').addEventListener('change', renderAssets);

fileInput.addEventListener('change', function () {
  const file = fileInput.files && fileInput.files[0];
  replaceAsset(file);
});

$('refreshAssetsBtn').addEventListener('click', function () {
  loadAssets()
    .then(function () {
      showStatus('Asset list refreshed.', 'success');
    })
    .catch(function (err) {
      showStatus('Failed to load assets: ' + err.message, 'error');
    });
});

$('uploadBtn').addEventListener('click', function () {
  $('uploadForm').reset();
  $('uploadDialog').showModal();
});

$('cancelUploadBtn').addEventListener('click', function () {
  $('uploadDialog').close();
});

$('uploadForm').addEventListener('submit', async function (event) {
  event.preventDefault();
  const targetPath = $('uploadPath').value.trim().replace(/\\/g, '/');
  const file = $('uploadFile').files && $('uploadFile').files[0];

  if (!targetPath || !file) {
    showStatus('Target path and file are required.', 'error');
    return;
  }

  showStatus('Uploading ' + file.name + '...', 'info');

  try {
    const data = await api('/dodo/api/assets/upload?file=' + encodeURIComponent(targetPath), {
      method: 'POST',
      headers: { 'Content-Type': 'application/octet-stream' },
      body: file
    });
    $('uploadDialog').close();
    showStatus('Uploaded ' + data.path + ' (' + formatBytes(data.size) + ').', 'success');
    await loadAssets();
  } catch (err) {
    showStatus('Upload failed: ' + err.message, 'error');
  }
});

$('closeBackupsBtn').addEventListener('click', function () {
  $('backupsDialog').close();
});

$('refreshOverviewBtn').addEventListener('click', function () {
  loadOverview().catch(function (err) {
    showStatus('Failed to load overview: ' + err.message, 'error');
  });
});

$('txApplyBtn').addEventListener('click', function () {
  state.page = 1;
  loadTransactions().catch(function (err) {
    showStatus('Failed to load transactions: ' + err.message, 'error');
  });
});

$('txResetBtn').addEventListener('click', function () {
  $('txSearch').value = '';
  $('txOwner').value = '';
  $('txFrom').value = '';
  $('txTo').value = '';
  state.page = 1;
  loadTransactions().catch(function (err) {
    showStatus('Failed to load transactions: ' + err.message, 'error');
  });
});

$('txPrevBtn').addEventListener('click', function () {
  if (state.page <= 1) return;
  state.page -= 1;
  loadTransactions().catch(function (err) {
    showStatus('Failed to load transactions: ' + err.message, 'error');
  });
});

$('txNextBtn').addEventListener('click', function () {
  if (state.page >= Math.ceil(state.txTotal / state.pageSize)) return;
  state.page += 1;
  loadTransactions().catch(function (err) {
    showStatus('Failed to load transactions: ' + err.message, 'error');
  });
});

$('txExportBtn').addEventListener('click', exportCsv);

$('refreshOwnersBtn').addEventListener('click', function () {
  loadUsers().catch(function (err) {
    showStatus('Failed to load users: ' + err.message, 'error');
  });
});

$('refreshAiBtn').addEventListener('click', function () {
  loadAiUsage().catch(function (err) {
    showStatus('Failed to load AI usage: ' + err.message, 'error');
  });
});

$('contentReloadBtn').addEventListener('click', function () {
  loadContent().catch(function (err) {
    showStatus('Failed to load portfolio content: ' + err.message, 'error');
  });
});

$('contentFormatBtn').addEventListener('click', formatPortfolioJson);
$('contentSaveBtn').addEventListener('click', saveContent);
$('portfolioJson').addEventListener('input', function () {
  try {
    renderPortfolioPreview(JSON.parse($('portfolioJson').value));
  } catch (err) {
    // Keep the last valid preview while the JSON is being edited.
  }
});

$('expenseForm').addEventListener('submit', saveExpense);
$('cancelExpenseBtn').addEventListener('click', function () {
  $('expenseDialog').close();
});

$('refreshRagBtn').addEventListener('click', function () {
  loadRag().catch(function (err) {
    showStatus('Failed to load chatbot monitoring: ' + err.message, 'error');
  });
});

$('ragAddForm').addEventListener('submit', addRagKnowledgeEntry);
$('cancelRagAddBtn').addEventListener('click', function () {
  $('ragAddDialog').close();
});

$('ragKnowledgeReload').addEventListener('click', function () {
  loadRag().catch(function (err) {
    showStatus('Failed to reload knowledge base: ' + err.message, 'error');
  });
});

$('ragKnowledgeSave').addEventListener('click', saveRagKnowledge);

$('refreshHealthBtn').addEventListener('click', function () {
  loadHealth().catch(function (err) {
    showStatus('Failed to load health: ' + err.message, 'error');
  });
});

$('refreshAuditBtn').addEventListener('click', function () {
  loadAudit().catch(function (err) {
    showStatus('Failed to load audit log: ' + err.message, 'error');
  });
});

$('logoutBtn').addEventListener('click', function () {
  if (!confirm('Log out from the admin panel?')) return;
  fetch('/dodo/api/logout', { method: 'POST' }).finally(function () {
    window.location.href = '/dodo/login';
  });
});

loadAssets().catch(function (err) {
  showStatus('Failed to load assets: ' + err.message, 'error');
});
