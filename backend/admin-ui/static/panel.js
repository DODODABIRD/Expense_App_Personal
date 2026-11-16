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
  activeTab: 'assets'
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
  overview: loadOverview,
  transactions: loadTransactions,
  users: loadUsers,
  ai: loadAiUsage,
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
    emptyRow(body, 6, 'No transactions match these filters.');
  } else {
    data.expenses.forEach(function (expense) {
      const tr = document.createElement('tr');
      tr.appendChild(cell(formatDay(expense.date)));
      tr.appendChild(cell(expense.name));
      tr.appendChild(cell(expense.category));
      tr.appendChild(cell(expense.type));
      tr.appendChild(cell(rupiah.format(expense.amount), 'right'));
      tr.appendChild(cell(expense.ownerId, 'mono'));
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

/* Users */

async function loadUsers() {
  const ownersBody = $('ownersBody');
  ownersBody.innerHTML = '';
  const firebaseBody = $('firebaseUsersBody');
  firebaseBody.innerHTML = '';

  try {
    const data = await api('/dodo/api/owners');
    if ((data.owners || []).length === 0) {
      emptyRow(ownersBody, 4, 'No expense owners yet.');
    } else {
      data.owners.forEach(function (owner) {
        const tr = document.createElement('tr');
        tr.appendChild(cell(owner.ownerId, 'mono'));
        tr.appendChild(cell(String(owner.expenseCount), 'right'));
        tr.appendChild(cell(rupiah.format(owner.totalAmount), 'right'));
        tr.appendChild(cell(formatDay(owner.lastExpenseDate)));
        ownersBody.appendChild(tr);
      });
    }
  } catch (err) {
    emptyRow(ownersBody, 4, 'Failed to load owners: ' + err.message);
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
