// Firebase Configuration & Initialization
const firebaseConfig = {
    apiKey: 'AIzaSyBScOUH8uoz0OjzmeMZpIAegniNU-axDEI',
    authDomain: 'unmurce-2f3e3.firebaseapp.com',
    projectId: 'unmurce-2f3e3',
    storageBucket: 'unmurce-2f3e3.firebasestorage.app',
    messagingSenderId: '515835567480',
    appId: '1:515835567480:web:13c5d1a0159cabb645bc8d'
};

const API_BASE_URL = (
    window.EXPENSE_API_BASE_URL ||
    (window.location.origin ? `${window.location.origin}/api` : 'https://dododabird.us/api')
).replace(/\/+$/, '');

firebase.initializeApp(firebaseConfig);
const auth = firebase.auth();

// Global State
let isGuestMode = false;
let currentExpenses = [];
let activeView = 'dashboard';
let isRegistering = false;
let editingExpenseId = null;
let currentSort = 'newest';
let detectedOcrItems = [];
let ocrReceiptDate = '';
let currentReceiptPhotoBase64 = null;
let liveSyncConnection = null;

const DEMO_EXPENSES = [
    {
        _id: 'demo-1',
        localId: 'demo-1',
        name: 'Kopi Kenangan Mantan',
        amount: 24000,
        category: 'makanan',
        type: 'expected',
        date: new Date(Date.now() - 3600000 * 3).toISOString().split('T')[0]
    },
    {
        _id: 'demo-2',
        localId: 'demo-2',
        name: 'Bensin Pertamax Full',
        amount: 50000,
        category: 'transportasi',
        type: 'expected',
        date: new Date(Date.now() - 86400000 * 1).toISOString().split('T')[0]
    },
    {
        _id: 'demo-3',
        localId: 'demo-3',
        name: 'Mouse Logitech G304',
        amount: 389000,
        category: 'elektronik',
        type: 'unexpected',
        date: new Date(Date.now() - 86400000 * 2).toISOString().split('T')[0]
    },
    {
        _id: 'demo-4',
        localId: 'demo-4',
        name: 'Makan Siang Nasi Padang',
        amount: 32000,
        category: 'makanan',
        type: 'expected',
        date: new Date(Date.now() - 86400000 * 3).toISOString().split('T')[0]
    },
    {
        _id: 'demo-5',
        localId: 'demo-5',
        name: 'Spotify Family Subscription',
        amount: 86900,
        category: 'langganan',
        type: 'expected',
        date: new Date(Date.now() - 86400000 * 4).toISOString().split('T')[0]
    },
    {
        _id: 'demo-6',
        localId: 'demo-6',
        name: 'Tambal Ban Motor Bocor',
        amount: 25000,
        category: 'transportasi',
        type: 'unexpected',
        date: new Date(Date.now() - 86400000 * 5).toISOString().split('T')[0]
    }
];

// Category Icons (SVGs matching the reference Flutter app screenshots)
function getCategoryIconSvg(category) {
    const cat = String(category || '').toLowerCase();
    
    // Food / Makanan (Burger / Plate / Drink icon)
    if (cat.includes('makanan') || cat.includes('food') || cat.includes('kopi') || cat.includes('drink')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path>
            <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
            <line x1="2" y1="12" x2="22" y2="12"></line>
        </svg>`;
    }
    
    // Transport
    if (cat.includes('transport') || cat.includes('bensin') || cat.includes('car')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="1" y="3" width="15" height="13" rx="2"></rect>
            <polygon points="16 8 20 8 23 11 23 16 16 16 8"></polygon>
            <circle cx="5.5" cy="18.5" r="2.5"></circle>
            <circle cx="18.5" cy="18.5" r="2.5"></circle>
        </svg>`;
    }

    // Electronics / Tech
    if (cat.includes('elektronik') || cat.includes('gadget') || cat.includes('tech')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="2" y="3" width="20" height="14" rx="2" ry="2"></rect>
            <line x1="8" y1="21" x2="16" y2="21"></line>
            <line x1="12" y1="17" x2="12" y2="21"></line>
        </svg>`;
    }

    // Apparel / Baju
    if (cat.includes('baju') || cat.includes('apparel') || cat.includes('shop')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"></path>
            <line x1="3" y1="6" x2="21" y2="6"></line>
            <path d="M16 10a4 4 0 0 1-8 0"></path>
        </svg>`;
    }

    // Health / Kesehatan (Bag / Cross icon)
    if (cat.includes('kesehatan') || cat.includes('health') || cat.includes('med')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="2" y="7" width="20" height="14" rx="3"></rect>
            <path d="M16 7V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v3"></path>
            <line x1="12" y1="11" x2="12" y2="17"></line>
            <line x1="9" y1="14" x2="15" y2="14"></line>
        </svg>`;
    }

    // Entertainment / Hiburan
    if (cat.includes('hiburan') || cat.includes('movie') || cat.includes('game')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="2" y="6" width="20" height="12" rx="3"></rect>
            <line x1="6" y1="12" x2="10" y2="12"></line>
            <line x1="8" y1="10" x2="8" y2="14"></line>
            <circle cx="15" cy="11" r="1"></circle>
            <circle cx="17" cy="13" r="1"></circle>
        </svg>`;
    }

    // Default / Others (Lightbulb / Wallet)
    return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M9 18h6"></path>
        <path d="M10 22h4"></path>
        <path d="M15.09 14c.18-.98.65-1.74 1.41-2.5A4.65 4.65 0 0 0 18 8 6 6 0 0 0 6 8c0 1 .23 2.23 1.5 3.5.76.76 1.23 1.52 1.41 2.5"></path>
    </svg>`;
}

// Helpers
function formatCurrency(num) {
    const val = Math.round(Number(num) || 0);
    return 'Rp' + new Intl.NumberFormat('id-ID').format(Math.abs(val));
}

function formatDateDisplay(dateStr) {
    if (!dateStr) return 'Today';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return dateStr;
    const day = String(d.getDate()).padStart(2, '0');
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    const month = months[d.getMonth()];
    const year = d.getFullYear();
    return `${day} ${month} ${year}`;
}

function showToast(message, duration = 2800) {
    const banner = document.getElementById('toast-banner');
    if (!banner) return;
    banner.textContent = message;
    banner.classList.add('show');
    clearTimeout(banner._timer);
    banner._timer = setTimeout(() => {
        banner.classList.remove('show');
    }, duration);
}

function showConfirmDialog(title, message, onConfirm) {
    const modal = document.getElementById('confirm-modal');
    const titleEl = document.getElementById('confirm-modal-title');
    const msgEl = document.getElementById('confirm-modal-message');
    const okBtn = document.getElementById('confirm-modal-ok-btn');
    const cancelBtn = document.getElementById('confirm-modal-cancel-btn');
    const closeBtn = document.getElementById('close-confirm-modal-btn');

    if (!modal) return;
    titleEl.textContent = title;
    msgEl.textContent = message;
    modal.hidden = false;

    const cleanup = () => {
        modal.hidden = true;
        okBtn.onclick = null;
        cancelBtn.onclick = null;
        closeBtn.onclick = null;
    };

    okBtn.onclick = () => {
        cleanup();
        onConfirm();
    };
    cancelBtn.onclick = cleanup;
    closeBtn.onclick = cleanup;
}

async function authHeaders() {
    if (isGuestMode) {
        return { 'Content-Type': 'application/json' };
    }
    const user = auth.currentUser;
    if (!user) throw new Error('Please sign in first');
    const token = await user.getIdToken();
    return {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
    };
}

// View Navigation & Router
function navigateToView(viewId, params = {}) {
    const views = ['dashboard', 'expense-form', 'analytics', 'receipt-ocr', 'settings'];
    views.forEach(v => {
        const el = document.getElementById(`view-${v}`);
        if (el) el.hidden = (v !== viewId);
    });

    const bottomNav = document.getElementById('bottom-nav');
    if (bottomNav) {
        // Show bottom navigation on dashboard and settings; hide on focused forms
        bottomNav.style.display = (viewId === 'dashboard' || viewId === 'settings') ? 'flex' : 'none';
        
        // Update active tab highlight
        const homeBtn = document.getElementById('nav-home-btn');
        if (homeBtn) homeBtn.classList.toggle('active', viewId === 'dashboard');
    }

    activeView = viewId;
    window.scrollTo({ top: 0, behavior: 'smooth' });

    if (viewId === 'dashboard') {
        renderDashboard();
    } else if (viewId === 'expense-form') {
        setupExpenseForm(params);
    } else if (viewId === 'analytics') {
        renderAnalytics();
    } else if (viewId === 'receipt-ocr') {
        setupReceiptOcr();
    } else if (viewId === 'settings') {
        renderSettings();
    }
}

// Live Sync Manager (WebSocket + SSE Fallback + Polling)
class LiveSyncManager {
    constructor() {
        this.ws = null;
        this.sse = null;
        this.pollingTimer = null;
        this.status = 'disconnected'; // 'live', 'syncing', 'offline'
        this.retryCount = 0;
    }

    async connect() {
        if (isGuestMode) {
            this.updateStatus('live', 'Demo Mode');
            return;
        }
        if (!auth.currentUser) return;
        this.updateStatus('syncing', 'Connecting...');

        try {
            const token = await auth.currentUser.getIdToken();

            // Native WebSockets require a standalone Node.js server (e.g. node api/index.js).
            // On Vercel and vercel dev, serverless lambdas do not support WebSockets,
            // and sending an Upgrade: websocket header causes vercel dev to crash with ECONNRESET.
            if (window.EXPENSE_WS_URL) {
                const wsUrl = `${window.EXPENSE_WS_URL}?token=${encodeURIComponent(token)}`;
                this.ws = new WebSocket(wsUrl);

                const wsTimeout = setTimeout(() => {
                    if (this.ws && this.ws.readyState !== WebSocket.OPEN) {
                        console.log('[LiveSync] WebSocket connection timed out; falling back to SSE/Polling.');
                        try { this.ws.close(); } catch (e) {}
                        this.ws = null;
                        this.connectSse(token);
                    }
                }, 3000);

                this.ws.onopen = () => {
                    clearTimeout(wsTimeout);
                    this.updateStatus('live', 'Live');
                    this.retryCount = 0;
                    console.log('[LiveSync] WebSocket connected successfully');
                };

                this.ws.onmessage = (event) => {
                    try {
                        const data = JSON.parse(event.data);
                        this.handleLiveEvent(data);
                    } catch (e) {
                        console.error('[LiveSync] Failed to parse ws message', e);
                    }
                };

                this.ws.onclose = () => {
                    clearTimeout(wsTimeout);
                    if (this.status === 'live') {
                        console.log('[LiveSync] WebSocket closed; reconnecting via SSE...');
                        this.connectSse(token);
                    }
                };

                this.ws.onerror = () => {
                    clearTimeout(wsTimeout);
                    try { this.ws.close(); } catch (e) {}
                    this.connectSse(token);
                };
                return;
            }

            // Default to SSE / Polling for Vercel dev and production
            this.connectSse(token);
        } catch (err) {
            console.warn('[LiveSync] Live connection error, starting SSE fallback', err);
            this.connectSse();
        }
    }

    async connectSse(token) {
        if (this.sse) {
            try { this.sse.close(); } catch (e) {}
            this.sse = null;
        }

        try {
            if (!token && auth.currentUser) {
                token = await auth.currentUser.getIdToken();
            }
            if (!token) return;

            const sseUrl = `${API_BASE_URL}/events?token=${encodeURIComponent(token)}`;
            this.sse = new EventSource(sseUrl);

            this.sse.onopen = () => {
                this.updateStatus('live', 'Live (SSE)');
                this.retryCount = 0;
                console.log('[LiveSync] Connected via SSE');
            };

            this.sse.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);
                    this.handleLiveEvent(data);
                } catch (e) {}
            };

            this.sse.onerror = () => {
                try { this.sse.close(); } catch (e) {}
                this.sse = null;
                this.startAdaptivePolling();
            };
        } catch (e) {
            this.startAdaptivePolling();
        }
    }

    startAdaptivePolling() {
        this.updateStatus('syncing', 'Syncing');
        if (this.pollingTimer) clearInterval(this.pollingTimer);

        this.pollingTimer = setInterval(() => {
            if (!document.hidden && auth.currentUser) {
                fetchExpenses(false);
            }
        }, 8000);
    }

    handleLiveEvent(data) {
        if (!data || !data.type) return;
        console.log('[LiveSync] Event received:', data.type);

        if (data.type === 'expense_created' && data.item) {
            const exists = currentExpenses.some(e => e._id === data.item._id || (e.localId && e.localId === data.item.localId));
            if (!exists) {
                currentExpenses.unshift(data.item);
                this.refreshActiveView();
                showToast(`+ Added ${data.item.name || 'Expense'}`);
            }
        } else if (data.type === 'expense_updated' && data.item) {
            const idx = currentExpenses.findIndex(e => e._id === data.item._id);
            if (idx !== -1) {
                currentExpenses[idx] = data.item;
                this.refreshActiveView();
                showToast(`Updated ${data.item.name}`);
            }
        } else if (data.type === 'expense_deleted' && data.id) {
            currentExpenses = currentExpenses.filter(e => e._id !== data.id);
            this.refreshActiveView();
            showToast('Transaction deleted');
        } else if (data.type === 'bulk_deleted') {
            currentExpenses = [];
            this.refreshActiveView();
            showToast('All transactions cleared');
        }
    }

    refreshActiveView() {
        if (activeView === 'dashboard') renderDashboard();
        if (activeView === 'analytics') renderAnalytics();
    }

    updateStatus(status, label) {
        this.status = status;
        const dot = document.getElementById('live-indicator-dot');
        const text = document.getElementById('live-indicator-text');
        if (!dot || !text) return;

        dot.className = 'live-dot';
        if (status === 'syncing') dot.classList.add('syncing');
        if (status === 'offline') dot.classList.add('offline');
        text.textContent = label;
    }

    disconnect() {
        if (this.ws) {
            try { this.ws.close(); } catch (e) {}
            this.ws = null;
        }
        if (this.sse) {
            try { this.sse.close(); } catch (e) {}
            this.sse = null;
        }
        if (this.pollingTimer) {
            clearInterval(this.pollingTimer);
            this.pollingTimer = null;
        }
        this.updateStatus('offline', 'Offline');
    }
}

const liveSync = new LiveSyncManager();

// Fetch Expenses from API
let isFetching = false;
async function fetchExpenses(showLoading = true) {
    if (isGuestMode) {
        const saved = localStorage.getItem('unmurce_demo_expenses');
        currentExpenses = saved ? JSON.parse(saved) : [...DEMO_EXPENSES];
        renderDashboard();
        liveSync.updateStatus('live', 'Demo Mode');
        return;
    }
    if (isFetching || !auth.currentUser) return;
    isFetching = true;
    if (showLoading) liveSync.updateStatus('syncing', 'Syncing');

    try {
        const res = await fetch(`${API_BASE_URL}/users`, { headers: await authHeaders() });
        if (!res.ok) throw new Error('Fetch failed: ' + res.status);
        const data = await res.json();
        currentExpenses = Array.isArray(data) ? data : [];
        renderDashboard();
        liveSync.updateStatus('live', 'Live');
    } catch (err) {
        console.error('Error fetching expenses:', err);
        liveSync.updateStatus('offline', 'Offline');
    } finally {
        isFetching = false;
    }
}

// Render Dashboard View
function renderDashboard() {
    const listEl = document.getElementById('transaction-list');
    const emptyEl = document.getElementById('empty-tx-state');
    const totalEl = document.getElementById('dashboard-total-amount');
    const statTxEl = document.getElementById('stat-tx-count');
    const statCatEl = document.getElementById('stat-cat-count');

    if (!listEl) return;

    // Filter & Sort
    let sorted = [...currentExpenses];
    if (currentSort === 'newest') {
        sorted.sort((a, b) => new Date(b.date || 0) - new Date(a.date || 0));
    } else if (currentSort === 'oldest') {
        sorted.sort((a, b) => new Date(a.date || 0) - new Date(b.date || 0));
    } else if (currentSort === 'highest') {
        sorted.sort((a, b) => (Number(b.amount) || 0) - (Number(a.amount) || 0));
    } else if (currentSort === 'lowest') {
        sorted.sort((a, b) => (Number(a.amount) || 0) - (Number(b.amount) || 0));
    }

    // Totals & Categories
    let total = 0;
    const catSet = new Set();
    currentExpenses.forEach(item => {
        const amt = Number(item.amount) || 0;
        total += (item.type === 'Income' ? -amt : amt);
        if (item.category) catSet.add(item.category.toLowerCase().trim());
    });

    if (totalEl) totalEl.textContent = formatCurrency(total);
    if (statTxEl) statTxEl.textContent = `📑 ${currentExpenses.length} Transaksi`;
    if (statCatEl) statCatEl.textContent = `🗃 ${catSet.size} Kategori`;

    if (sorted.length === 0) {
        listEl.innerHTML = '';
        if (emptyEl) emptyEl.style.display = 'flex';
        return;
    }

    if (emptyEl) emptyEl.style.display = 'none';
    listEl.innerHTML = '';

    sorted.forEach(item => {
        const card = document.createElement('article');
        card.className = 'neo-transaction-card';
        card.setAttribute('data-id', item._id || '');

        const iconSvg = getCategoryIconSvg(item.category);
        const amtStr = formatCurrency(item.amount);
        const dateStr = formatDateDisplay(item.date);

        card.innerHTML = `
            <div class="tx-left">
                <div class="tx-icon-box">
                    ${iconSvg}
                </div>
                <div class="tx-content">
                    <h3 class="tx-title">${escapeHtml(item.name || 'Expense')}</h3>
                    <div class="tx-amount">${amtStr}</div>
                    <span class="tx-date">${dateStr}</span>
                </div>
            </div>
            <button class="tx-edit-btn" type="button" aria-label="Edit ${escapeHtml(item.name || 'Expense')}" title="Edit Expense">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M12 20h9"></path>
                    <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path>
                </svg>
            </button>
        `;

        // Card click / Edit button click opens Edit form
        card.addEventListener('click', () => {
            navigateToView('expense-form', { expense: item });
        });

        listEl.appendChild(card);
    });
}

// FORM VIEW CONTROLLER (Add / Edit)
function setupExpenseForm(params = {}) {
    const form = document.getElementById('expense-form');
    const titleEl = document.getElementById('form-title');
    const deleteBtn = document.getElementById('form-delete-btn');
    const submitBtn = document.getElementById('form-submit-btn');
    const idInput = document.getElementById('edit-expense-id');
    const localIdInput = document.getElementById('edit-expense-localId');
    const amountInput = document.getElementById('amount-input');
    const nameInput = document.getElementById('expense-name-input');
    const nativeDateInput = document.getElementById('native-date-input');
    const dateLabel = document.getElementById('date-display-label');

    const expense = params.expense || null;
    editingExpenseId = expense ? (expense._id || null) : null;

    if (expense) {
        titleEl.textContent = 'Edit Expense';
        submitBtn.textContent = 'Update Transaction';
        deleteBtn.style.display = 'inline-flex';
        idInput.value = expense._id || '';
        localIdInput.value = expense.localId || '';
        amountInput.value = String(Math.round(Number(expense.amount) || 0));
        nameInput.value = expense.name || '';
        
        selectCategory(expense.category || 'makanan');
        selectType(expense.type || 'Expected');
        setDateValue(expense.date || new Date().toISOString().split('T')[0]);
    } else {
        titleEl.textContent = 'Add Expense';
        submitBtn.textContent = 'Save Transaction';
        deleteBtn.style.display = 'none';
        idInput.value = '';
        localIdInput.value = Date.now().toString();
        amountInput.value = '';
        nameInput.value = '';

        selectCategory('makanan');
        selectType('Expected');
        setDateValue(new Date().toISOString().split('T')[0]);
    }

    amountInput.focus();
}

function selectCategory(cat) {
    const normalized = String(cat || 'makanan').toLowerCase();
    document.querySelectorAll('.cat-pill-btn').forEach(btn => {
        const bCat = btn.getAttribute('data-category');
        btn.classList.toggle('active', bCat === normalized);
    });
}

function getSelectedCategory() {
    const active = document.querySelector('.cat-pill-btn.active');
    return active ? active.getAttribute('data-category') : 'makanan';
}

function selectType(type) {
    const normalized = String(type || 'Expected');
    document.querySelectorAll('.type-pill-btn').forEach(btn => {
        const bType = btn.getAttribute('data-type');
        btn.classList.toggle('active', bType.toLowerCase() === normalized.toLowerCase());
    });
}

function getSelectedType() {
    const active = document.querySelector('.type-pill-btn.active');
    return active ? active.getAttribute('data-type') : 'Expected';
}

function setDateValue(isoDate) {
    const nativeInput = document.getElementById('native-date-input');
    const dateLabel = document.getElementById('date-display-label');
    const todayBtn = document.getElementById('quick-date-today');
    const yestBtn = document.getElementById('quick-date-yesterday');

    if (!nativeInput || !dateLabel) return;
    nativeInput.value = isoDate;
    dateLabel.textContent = `📅 ${formatDateDisplay(isoDate)}`;

    const todayStr = new Date().toISOString().split('T')[0];
    const yest = new Date();
    yest.setDate(yest.getDate() - 1);
    const yestStr = yest.toISOString().split('T')[0];

    if (todayBtn) todayBtn.classList.toggle('active', isoDate === todayStr);
    if (yestBtn) yestBtn.classList.toggle('active', isoDate === yestStr);
}

// ANALYTICS VIEW CONTROLLER
function renderAnalytics() {
    const totalEl = document.getElementById('analytics-total-amount');
    const txCountEl = document.getElementById('analytics-tx-count');
    const catCountEl = document.getElementById('analytics-cat-count');
    const badge7d = document.getElementById('analytics-7d-badge');
    const peakBanner = document.getElementById('analytics-peak-banner');
    const barsTrack = document.getElementById('analytics-7d-bars');
    const progressTrack = document.getElementById('analytics-cat-progress');
    const catList = document.getElementById('analytics-cat-list');

    // Financial totals
    let total = 0;
    const catTotals = {};
    const typeTotals = { expected: 0, unexpected: 0, others: 0 };
    const amounts = [];

    currentExpenses.forEach(item => {
        const amt = Math.max(0, Number(item.amount) || 0);
        total += amt;
        amounts.push(amt);

        const cat = (item.category || 'others').toLowerCase().trim();
        catTotals[cat] = (catTotals[cat] || 0) + amt;

        const type = String(item.type || 'expected').toLowerCase();
        if (type.includes('unexpect')) {
            typeTotals.unexpected += amt;
        } else if (type.includes('other')) {
            typeTotals.others += amt;
        } else {
            typeTotals.expected += amt;
        }
    });

    if (totalEl) totalEl.textContent = formatCurrency(total);
    if (txCountEl) txCountEl.textContent = `📑 ${currentExpenses.length} Transaksi`;
    if (catCountEl) catCountEl.textContent = `🗃 ${Object.keys(catTotals).length} Kategori`;

    // 7-Day Chart Calculation
    const days = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];
    const past7Days = [];
    const today = new Date();

    for (let i = 6; i >= 0; i--) {
        const d = new Date();
        d.setDate(today.getDate() - i);
        const iso = d.toISOString().split('T')[0];
        const dayName = days[d.getDay()];
        past7Days.push({ date: iso, dayName, total: 0, isToday: (i === 0) });
    }

    let total7d = 0;
    currentExpenses.forEach(item => {
        if (!item.date) return;
        const match = past7Days.find(d => d.date === item.date);
        if (match) {
            const amt = Number(item.amount) || 0;
            match.total += amt;
            total7d += amt;
        }
    });

    if (badge7d) badge7d.textContent = `Total 7H: ${formatCurrency(total7d)}`;

    // Find peak day
    let peakDay = past7Days[0];
    past7Days.forEach(d => {
        if (d.total > peakDay.total) peakDay = d;
    });

    if (peakBanner) {
        if (peakDay.total > 0) {
            peakBanner.innerHTML = `<span>🔥 Puncak pengeluaran 7 hari ini terjadi pada <strong>${peakDay.dayName} (${formatCurrency(peakDay.total)})</strong></span>`;
            peakBanner.style.display = 'flex';
        } else {
            peakBanner.innerHTML = `<span>✓ Tidak ada pengeluaran dalam 7 hari terakhir.</span>`;
            peakBanner.style.display = 'flex';
        }
    }

    // Render 7-day pillars
    if (barsTrack) {
        barsTrack.innerHTML = '';
        const maxVal = Math.max(1, peakDay.total);

        past7Days.forEach(d => {
            const pct = Math.max(6, Math.min(100, Math.round((d.total / maxVal) * 100)));
            const isPeak = (d.total === peakDay.total && peakDay.total > 0);
            
            const col = document.createElement('div');
            col.className = 'bar-column';
            col.innerHTML = `
                <span class="bar-value-label">${d.total > 0 ? (d.total >= 1000 ? Math.round(d.total/1000) + 'k' : d.total) : ''}</span>
                <div class="bar-pillar ${isPeak ? 'peak' : ''} ${d.isToday ? 'today' : ''}" style="height: ${pct}%;"></div>
                <span class="bar-day-name ${d.isToday ? 'today' : ''}">${d.dayName}</span>
            `;
            barsTrack.appendChild(col);
        });
    }

    // Category Distribution Progress Bar & List
    const catColors = {
        makanan: '#ffe500',
        transportasi: '#4ee0e6',
        elektronik: '#a78bfa',
        baju: '#f472b6',
        kesehatan: '#fb7185',
        hiburan: '#38bdf8',
        others: '#94a3b8'
    };

    const sortedCats = Object.entries(catTotals).sort((a, b) => b[1] - a[1]);

    if (progressTrack) {
        progressTrack.innerHTML = '';
        sortedCats.forEach(([cat, amt]) => {
            const pct = total > 0 ? (amt / total) * 100 : 0;
            if (pct > 0) {
                const seg = document.createElement('div');
                seg.className = 'progress-segment';
                seg.style.width = `${pct}%`;
                seg.style.backgroundColor = catColors[cat] || '#cbd5e1';
                seg.title = `${cat}: ${pct.toFixed(1)}%`;
                progressTrack.appendChild(seg);
            }
        });
    }

    if (catList) {
        catList.innerHTML = '';
        if (sortedCats.length === 0) {
            catList.innerHTML = '<p style="color: var(--muted); font-size: 0.9rem;">Belum ada data kategori.</p>';
        } else {
            sortedCats.forEach(([cat, amt]) => {
                const pct = total > 0 ? ((amt / total) * 100).toFixed(1) : '0';
                const count = currentExpenses.filter(e => (e.category || '').toLowerCase() === cat).length;
                const row = document.createElement('div');
                row.className = 'cat-breakdown-row';
                row.innerHTML = `
                    <div class="cat-name-info">
                        <div class="cat-mini-icon" style="background: ${catColors[cat] || '#fff'};">
                            ${getCategoryMiniEmoji(cat)}
                        </div>
                        <div>
                            <strong style="text-transform: uppercase; font-size: 0.95rem;">${escapeHtml(cat)}</strong>
                            <div style="font-size: 0.75rem; color: var(--muted); font-weight: 700;">${count} item • ${pct}%</div>
                        </div>
                    </div>
                    <strong style="font-size: 1rem;">${formatCurrency(amt)}</strong>
                `;
                catList.appendChild(row);
            });
        }
    }

    // Expense Type Ratio
    const expTotal = total || 1;
    const expPct = Math.round((typeTotals.expected / expTotal) * 100);
    const unexpPct = Math.round((typeTotals.unexpected / expTotal) * 100);
    const othPct = Math.max(0, 100 - expPct - unexpPct);

    document.getElementById('ratio-expected-pct').textContent = `${expPct}%`;
    document.getElementById('ratio-expected-rp').textContent = formatCurrency(typeTotals.expected);
    document.getElementById('ratio-unexpected-pct').textContent = `${unexpPct}%`;
    document.getElementById('ratio-unexpected-rp').textContent = formatCurrency(typeTotals.unexpected);
    document.getElementById('ratio-others-pct').textContent = `${othPct}%`;
    document.getElementById('ratio-others-rp').textContent = formatCurrency(typeTotals.others);

    const healthBox = document.getElementById('analytics-ratio-health');
    if (healthBox) {
        if (unexpPct <= 35) {
            healthBox.className = 'ratio-health-box';
            healthBox.innerHTML = `<span>✓ Rasio terencana sehat! Pengeluaran tak terduga terkendali di bawah 35%.</span>`;
        } else {
            healthBox.className = 'insight-banner-box';
            healthBox.innerHTML = `<span>⚠️ Pengeluaran tak terduga (${unexpPct}%) melebihi ambang 35%. Pertimbangkan evaluasi pos belanja.</span>`;
        }
    }

    // Outlier Anomaly Detector
    const outlierCountPill = document.getElementById('analytics-outlier-count-pill');
    const outlierResult = document.getElementById('analytics-outlier-result');

    if (amounts.length >= 3) {
        const avg = total / amounts.length;
        const outlierThreshold = avg * 2.5;
        const outliers = currentExpenses.filter(e => (Number(e.amount) || 0) >= outlierThreshold);

        if (outliers.length > 0) {
            outlierCountPill.textContent = `${outliers.length} Anomali`;
            outlierCountPill.style.background = '#fecaca';
            outlierResult.className = 'insight-banner-box';
            const outlierNames = outliers.map(o => `<strong>${escapeHtml(o.name)}</strong> (${formatCurrency(o.amount)})`).join(', ');
            outlierResult.innerHTML = `<span>⚠️ Terdeteksi pengeluaran anomali yang melebihi batas rata-rata: ${outlierNames}</span>`;
        } else {
            outlierCountPill.textContent = '0 Anomali';
            outlierCountPill.style.background = 'var(--card-yellow)';
            outlierResult.className = 'ratio-health-box';
            outlierResult.innerHTML = `<span>✓ Tidak ada outlier terdeteksi! Semua pengeluaran berada dalam rentang wajar.</span>`;
        }
    } else {
        outlierCountPill.textContent = '0 Anomali';
        outlierResult.className = 'ratio-health-box';
        outlierResult.innerHTML = `<span>✓ Belum cukup transaksi untuk kalkulasi statistik (minimal 3 transaksi).</span>`;
    }
}

function getCategoryMiniEmoji(cat) {
    const c = String(cat || '').toLowerCase();
    if (c.includes('makan')) return '🍔';
    if (c.includes('trans')) return '🚗';
    if (c.includes('elek')) return '💻';
    if (c.includes('baju')) return '👕';
    if (c.includes('keseh')) return '🏥';
    if (c.includes('hibur')) return '🎬';
    return '💡';
}

// SMART RECEIPT OCR CONTROLLER
function setupReceiptOcr() {
    detectedOcrItems = [];
    currentReceiptPhotoBase64 = null;
    ocrReceiptDate = new Date().toISOString().split('T')[0];

    const promptCard = document.getElementById('ocr-upload-prompt-card');
    const previewCard = document.getElementById('ocr-preview-card');
    const progressBanner = document.getElementById('ocr-progress-banner');
    const itemsContainer = document.getElementById('ocr-items-container');
    const stickyBar = document.getElementById('ocr-sticky-bar');

    if (promptCard) promptCard.style.display = 'flex';
    if (previewCard) previewCard.style.display = 'none';
    if (progressBanner) progressBanner.style.display = 'none';
    if (itemsContainer) itemsContainer.style.display = 'none';
    if (stickyBar) stickyBar.style.display = 'none';

    updateOcrDateLabel(ocrReceiptDate);
}

function updateOcrDateLabel(isoDate) {
    const lbl = document.getElementById('ocr-receipt-date-label');
    if (lbl) lbl.textContent = `📅 RECEIPT DATE: ${formatDateDisplay(isoDate)}`;
}

// Compress and resize image before upload for speed
async function compressImageToDataUrl(file, maxWidth = 1200, quality = 0.85) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.readAsDataURL(file);
        reader.onload = (event) => {
            const img = new Image();
            img.src = event.target.result;
            img.onload = () => {
                let width = img.width;
                let height = img.height;

                if (width > maxWidth) {
                    height = Math.round((height * maxWidth) / width);
                    width = maxWidth;
                }

                const canvas = document.createElement('canvas');
                canvas.width = width;
                canvas.height = height;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(img, 0, 0, width, height);

                const dataUrl = canvas.toDataURL('image/jpeg', quality);
                resolve(dataUrl);
            };
            img.onerror = reject;
        };
        reader.onerror = reject;
    });
}

async function handleReceiptImageSelected(file) {
    if (!file) return;

    const promptCard = document.getElementById('ocr-upload-prompt-card');
    const previewCard = document.getElementById('ocr-preview-card');
    const previewImg = document.getElementById('ocr-preview-img');
    const progressBanner = document.getElementById('ocr-progress-banner');
    const progressText = document.getElementById('ocr-progress-text');

    try {
        progressBanner.style.display = 'flex';
        progressText.textContent = 'Optimizing image...';

        const dataUrl = await compressImageToDataUrl(file);
        currentReceiptPhotoBase64 = dataUrl;

        previewImg.src = dataUrl;
        promptCard.style.display = 'none';
        previewCard.style.display = 'block';

        // Extract raw base64 without prefix
        const base64Content = dataUrl.split(',')[1] || dataUrl;

        let finalResult = null;

        if (isGuestMode || !auth.currentUser) {
            progressText.textContent = 'Simulating OCR Vision & Tax distribution...';
            await new Promise(r => setTimeout(r, 600));
            progressText.textContent = 'Extracting line items and zero-loss tax reconciliation...';
            await new Promise(r => setTimeout(r, 600));
            finalResult = {
                date: new Date().toISOString().split('T')[0],
                items: [
                    { name: 'Iced Caramel Macchiato', amount: 48000, category: 'makanan' },
                    { name: 'Smoked Beef Croissant', amount: 36000, category: 'makanan' },
                    { name: 'Sparkling Water 330ml', amount: 18000, category: 'makanan' }
                ]
            };
        } else {
            progressText.textContent = 'Analyzing receipt with Gemini & Azure AI...';

            const token = await auth.currentUser.getIdToken();
            const response = await fetch(`${API_BASE_URL}/parse-receipt`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({
                    image: base64Content,
                    mimeType: 'image/jpeg'
                })
            });

            if (!response.ok && !response.headers.get('content-type')?.includes('ndjson')) {
                const errJson = await response.json().catch(() => ({}));
                throw new Error(errJson.error || `Server responded with ${response.status}`);
            }

            // Stream reader for NDJSON progress
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let buffer = '';

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                buffer += decoder.decode(value, { stream: true });
                const lines = buffer.split('\n');
                buffer = lines.pop(); // keep remainder

                for (const line of lines) {
                    if (!line.trim()) continue;
                    try {
                        const msg = JSON.parse(line);
                        if (msg.type === 'progress') {
                            progressText.textContent = msg.message || 'Processing receipt...';
                        } else if (msg.type === 'result') {
                            finalResult = msg;
                        } else if (msg.type === 'error') {
                            throw new Error(msg.message || 'OCR parsing failed');
                        }
                    } catch (e) {
                        if (e.message !== 'Unexpected end of JSON input') throw e;
                    }
                }
            }
        }

        if (!finalResult || !Array.isArray(finalResult.items) || finalResult.items.length === 0) {
            throw new Error('No itemized transactions detected on this receipt.');
        }

        progressBanner.style.display = 'none';
        if (finalResult.date) {
            ocrReceiptDate = finalResult.date;
            updateOcrDateLabel(ocrReceiptDate);
        }

        detectedOcrItems = finalResult.items.map((item, idx) => ({
            id: 'ocr_' + Date.now() + '_' + idx,
            selected: true,
            name: item.name || 'Receipt Item',
            amount: Math.round(Number(item.amount) || 0),
            qty: 1,
            unitPrice: Math.round(Number(item.amount) || 0),
            category: item.category || 'makanan',
            type: 'Expected'
        }));

        renderDetectedOcrItems();
        showToast(`Detected ${detectedOcrItems.length} items from receipt!`);

    } catch (err) {
        console.error('OCR Error:', err);
        progressBanner.style.display = 'none';
        showToast('Receipt scan failed: ' + err.message, 4000);
        // Show fallback manual item creation
        if (detectedOcrItems.length === 0) {
            addManualOcrItem();
        }
    }
}

function renderDetectedOcrItems() {
    const container = document.getElementById('ocr-items-container');
    const listEl = document.getElementById('ocr-items-list');
    const countHeading = document.getElementById('ocr-items-count-heading');
    const stickyBar = document.getElementById('ocr-sticky-bar');

    if (!container || !listEl) return;
    container.style.display = 'flex';
    stickyBar.style.display = 'flex';
    listEl.innerHTML = '';

    countHeading.textContent = `Detected Items (${detectedOcrItems.length})`;

    detectedOcrItems.forEach(item => {
        const card = document.createElement('div');
        card.className = 'detected-item-card';
        card.setAttribute('data-ocr-id', item.id);

        card.innerHTML = `
            <div class="item-top-row">
                <div class="item-check-group">
                    <input type="checkbox" class="neo-checkbox ocr-check" ${item.selected ? 'checked' : ''} aria-label="Select item">
                    <input type="text" class="item-title-input ocr-title" value="${escapeHtml(item.name)}" placeholder="Item name">
                </div>
                <button type="button" class="item-delete-btn ocr-delete-btn" title="Remove Item">✕</button>
            </div>
            <div class="item-controls-row">
                <div class="qty-stepper-box">
                    <span>🍴 Qty:</span>
                    <button type="button" class="qty-btn ocr-qty-minus">-</button>
                    <strong class="ocr-qty-num">${item.qty}x</strong>
                    <button type="button" class="qty-btn ocr-qty-plus">+</button>
                </div>
                <div class="item-price-box">
                    <span style="font-weight: 800; font-size: 0.85rem; margin-right: 4px;">Rp</span>
                    <input type="number" class="item-price-input ocr-price" value="${item.amount}" step="500">
                </div>
                <select class="ocr-category neo-card" style="padding: 4px 8px; border-radius: var(--radius-sm); font-size: 0.8rem; font-weight: 800; width: auto;">
                    <option value="makanan" ${item.category === 'makanan' ? 'selected' : ''}>Makanan</option>
                    <option value="transportasi" ${item.category === 'transportasi' ? 'selected' : ''}>Transport</option>
                    <option value="elektronik" ${item.category === 'elektronik' ? 'selected' : ''}>Elektronik</option>
                    <option value="baju" ${item.category === 'baju' ? 'selected' : ''}>Baju</option>
                    <option value="kesehatan" ${item.category === 'kesehatan' ? 'selected' : ''}>Kesehatan</option>
                    <option value="hiburan" ${item.category === 'hiburan' ? 'selected' : ''}>Hiburan</option>
                    <option value="others" ${item.category === 'others' ? 'selected' : ''}>Others</option>
                </select>
            </div>
        `;

        // Event listeners for this card
        const checkEl = card.querySelector('.ocr-check');
        const titleEl = card.querySelector('.ocr-title');
        const priceEl = card.querySelector('.ocr-price');
        const minusBtn = card.querySelector('.ocr-qty-minus');
        const plusBtn = card.querySelector('.ocr-qty-plus');
        const qtyNum = card.querySelector('.ocr-qty-num');
        const delBtn = card.querySelector('.ocr-delete-btn');
        const catSelect = card.querySelector('.ocr-category');

        checkEl.addEventListener('change', () => {
            item.selected = checkEl.checked;
            updateOcrSelectedTotals();
        });

        titleEl.addEventListener('input', () => {
            item.name = titleEl.value;
        });

        priceEl.addEventListener('input', () => {
            item.amount = Math.max(0, Number(priceEl.value) || 0);
            item.unitPrice = Math.round(item.amount / Math.max(1, item.qty));
            updateOcrSelectedTotals();
        });

        minusBtn.addEventListener('click', () => {
            if (item.qty > 1) {
                item.qty--;
                item.amount = item.unitPrice * item.qty;
                priceEl.value = item.amount;
                qtyNum.textContent = `${item.qty}x`;
                updateOcrSelectedTotals();
            }
        });

        plusBtn.addEventListener('click', () => {
            item.qty++;
            item.amount = item.unitPrice * item.qty;
            priceEl.value = item.amount;
            qtyNum.textContent = `${item.qty}x`;
            updateOcrSelectedTotals();
        });

        catSelect.addEventListener('change', () => {
            item.category = catSelect.value;
        });

        delBtn.addEventListener('click', () => {
            detectedOcrItems = detectedOcrItems.filter(i => i.id !== item.id);
            renderDetectedOcrItems();
        });

        listEl.appendChild(card);
    });

    updateOcrSelectedTotals();
}

function updateOcrSelectedTotals() {
    const totalValEl = document.getElementById('ocr-selected-total-val');
    const saveBtn = document.getElementById('ocr-save-selected-btn');
    if (!totalValEl || !saveBtn) return;

    const selected = detectedOcrItems.filter(i => i.selected);
    const sum = selected.reduce((acc, i) => acc + (Number(i.amount) || 0), 0);

    totalValEl.textContent = formatCurrency(sum);
    saveBtn.textContent = `✓ SAVE (${selected.length})`;
    saveBtn.disabled = (selected.length === 0);
}

function addManualOcrItem() {
    detectedOcrItems.push({
        id: 'manual_' + Date.now(),
        selected: true,
        name: 'Item ' + (detectedOcrItems.length + 1),
        amount: 25000,
        qty: 1,
        unitPrice: 25000,
        category: 'makanan',
        type: 'Expected'
    });
    renderDetectedOcrItems();
}

async function saveSelectedOcrItems() {
    const selected = detectedOcrItems.filter(i => i.selected && (Number(i.amount) || 0) > 0);
    if (selected.length === 0) {
        showToast('Please select at least one item');
        return;
    }

    const saveBtn = document.getElementById('ocr-save-selected-btn');
    if (saveBtn) {
        saveBtn.disabled = true;
        saveBtn.textContent = 'Saving...';
    }

    try {
        if (isGuestMode) {
            selected.forEach((item, idx) => {
                currentExpenses.unshift({
                    _id: 'demo_ocr_' + Date.now() + '_' + idx,
                    localId: Date.now().toString() + '_' + idx,
                    name: item.name || 'Receipt Item',
                    amount: item.amount,
                    category: item.category || 'makanan',
                    type: 'Expected',
                    date: ocrReceiptDate || new Date().toISOString().split('T')[0]
                });
            });
            localStorage.setItem('unmurce_demo_expenses', JSON.stringify(currentExpenses));
            showToast(`Saved ${selected.length} items to expenses!`);
            resetOcrState();
            renderDashboard();
            navigateToView('dashboard');
            return;
        }

        const headers = await authHeaders();
        for (const item of selected) {
            const payload = {
                localId: item.id || Date.now().toString(),
                name: item.name || 'Receipt Item',
                amount: item.amount,
                category: item.category || 'makanan',
                type: 'Expected',
                date: ocrReceiptDate || new Date().toISOString().split('T')[0]
            };

            await fetch(`${API_BASE_URL}/users`, {
                method: 'POST',
                headers,
                body: JSON.stringify(payload)
            });
        }

        showToast(`Saved ${selected.length} items successfully!`);
        resetOcrState();
        await fetchExpenses(true);
        navigateToView('dashboard');
    } catch (err) {
        console.error('Error saving OCR items:', err);
        showToast('Failed to save some items: ' + err.message);
        if (saveBtn) saveBtn.disabled = false;
    }
}

// SETTINGS & PROFILE VIEW CONTROLLER
async function renderSettings() {
    const user = auth.currentUser;
    const emailEl = document.getElementById('settings-user-email');
    if (emailEl) {
        emailEl.textContent = isGuestMode 
            ? 'demo@unmurce.app (Guest Preview)' 
            : (user ? (user.email || 'User') : 'Not signed in');
    }

    // Fetch exchange rates
    const usdEl = document.getElementById('rate-usd');
    const eurEl = document.getElementById('rate-eur');

    try {
        const headers = await authHeaders();
        const res = await fetch(`${API_BASE_URL}/exchange-rates`, { headers });
        if (res.ok) {
            const data = await res.json();
            if (data.rates) {
                // Rates are IDR base -> 1 IDR = X USD, so 1 USD = 1/X IDR
                const usdInIdr = data.rates.USD ? Math.round(1 / data.rates.USD) : null;
                const eurInIdr = data.rates.EUR ? Math.round(1 / data.rates.EUR) : null;
                if (usdEl) usdEl.textContent = usdInIdr ? formatCurrency(usdInIdr) : 'Unavailable';
                if (eurEl) eurEl.textContent = eurInIdr ? formatCurrency(eurInIdr) : 'Unavailable';
            }
        }
    } catch (e) {
        if (usdEl) usdEl.textContent = 'Rp16.250';
        if (eurEl) eurEl.textContent = 'Rp17.600';
    }
}

function exportPdfReport() {
    if (!currentExpenses.length) {
        showToast('No transactions to export');
        return;
    }

    let total = 0;
    const rows = currentExpenses.map(e => {
        const amt = Number(e.amount) || 0;
        total += (e.type === 'Income' ? -amt : amt);
        return [
            e.date || '',
            e.name || '',
            e.category || '',
            e.type || 'Expense',
            formatCurrency(amt)
        ];
    });

    const doc = new window.jspdf.jsPDF({ unit: 'pt', format: 'a4' });
    doc.setFontSize(18);
    doc.text('Unmurce - Personal Finance Report', 40, 40);
    doc.setFontSize(10);
    doc.text(`Exported: ${new Date().toLocaleString('id-ID')} | Total Balance: ${formatCurrency(total)}`, 40, 58);

    doc.autoTable({
        startY: 75,
        head: [['Date', 'Description', 'Category', 'Type', 'Amount']],
        body: rows,
        foot: [['', '', '', 'Total Balance', formatCurrency(total)]],
        theme: 'grid',
        headStyles: { fillColor: [0, 0, 0], textColor: 255, fontStyle: 'bold' },
        footStyles: { fillColor: [255, 234, 96], textColor: 0, fontStyle: 'bold' },
        styles: { font: 'helvetica', fontSize: 9 }
    });

    doc.save(`Unmurce_Report_${new Date().toISOString().slice(0, 10)}.pdf`);
    showToast('PDF downloaded successfully!');
}

function exportJsonBackup() {
    if (!currentExpenses.length) {
        showToast('No transactions to export');
        return;
    }

    const jsonStr = JSON.stringify(currentExpenses, null, 2);
    const blob = new Blob([jsonStr], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `Unmurce_Backup_${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
    showToast('JSON backup exported!');
}

function escapeHtml(str) {
    return String(str || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

// DOM Event Listeners Initialization
document.addEventListener('DOMContentLoaded', () => {
    // Auth Form Toggle
    const authToggle = document.getElementById('auth-toggle');
    const authTitle = document.getElementById('auth-title');
    const authKicker = document.getElementById('auth-kicker');
    const authSubmit = document.getElementById('auth-submit');
    const authForm = document.getElementById('auth-form');
    const authEmail = document.getElementById('auth-email');
    const authPassword = document.getElementById('auth-password');
    const authError = document.getElementById('auth-error');

    if (authToggle) {
        authToggle.addEventListener('click', () => {
            isRegistering = !isRegistering;
            authTitle.textContent = isRegistering ? 'Create account' : 'Sign in';
            authKicker.textContent = isRegistering ? 'NEW ACCOUNT' : 'WELCOME BACK';
            authSubmit.textContent = isRegistering ? 'Create account' : 'Sign in';
            authToggle.textContent = isRegistering ? 'Already have an account? Sign in' : 'Create an account';
            authError.textContent = '';
        });
    }

    if (authForm) {
        authForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            authError.textContent = '';
            authSubmit.disabled = true;
            try {
                if (isRegistering) {
                    await auth.createUserWithEmailAndPassword(authEmail.value.trim(), authPassword.value);
                } else {
                    await auth.signInWithEmailAndPassword(authEmail.value.trim(), authPassword.value);
                }
                authForm.reset();
            } catch (err) {
                authError.textContent = err.message.replace('Firebase: ', '').replace(/ \(auth\/.*\)\.?$/, '');
            } finally {
                authSubmit.disabled = false;
            }
        });
    }

    const authGuestBtn = document.getElementById('auth-guest-btn');
    if (authGuestBtn) {
        authGuestBtn.addEventListener('click', () => {
            isGuestMode = true;
            const authPanel = document.getElementById('auth-panel');
            const appViewport = document.getElementById('app-viewport');
            if (authPanel) authPanel.hidden = true;
            if (appViewport) appViewport.hidden = false;
            liveSync.connect();
            fetchExpenses(true);
            navigateToView('dashboard');
            showToast('⚡ Demo mode aktif! Coba semua fitur secara langsung.');
        });
    }

    // Auth State Observer
    auth.onAuthStateChanged((user) => {
        const authPanel = document.getElementById('auth-panel');
        const appViewport = document.getElementById('app-viewport');

        if (user) {
            isGuestMode = false;
            if (authPanel) authPanel.hidden = true;
            if (appViewport) appViewport.hidden = false;
            liveSync.connect();
            fetchExpenses(true);
            navigateToView('dashboard');
        } else if (!isGuestMode) {
            liveSync.disconnect();
            if (authPanel) authPanel.hidden = false;
            if (appViewport) appViewport.hidden = true;
            currentExpenses = [];
        }
    });

    // Navigation Buttons
    document.querySelectorAll('.back-to-dashboard-btn').forEach(btn => {
        btn.addEventListener('click', () => navigateToView('dashboard'));
    });

    const navHomeBtn = document.getElementById('nav-home-btn');
    if (navHomeBtn) navHomeBtn.addEventListener('click', () => navigateToView('dashboard'));

    const navAddBtn = document.getElementById('nav-add-btn');
    if (navAddBtn) navAddBtn.addEventListener('click', () => navigateToView('expense-form'));

    const navSettingsBtn = document.getElementById('nav-settings-btn');
    if (navSettingsBtn) navSettingsBtn.addEventListener('click', () => navigateToView('settings'));

    const emptyAddBtn = document.getElementById('empty-add-btn');
    if (emptyAddBtn) emptyAddBtn.addEventListener('click', () => navigateToView('expense-form'));

    const openAnalyticsBtn = document.getElementById('open-analytics-btn');
    if (openAnalyticsBtn) openAnalyticsBtn.addEventListener('click', () => navigateToView('analytics'));

    const headerScanOcrBtn = document.getElementById('header-scan-ocr-btn');
    if (headerScanOcrBtn) headerScanOcrBtn.addEventListener('click', () => navigateToView('receipt-ocr'));

    // Sorting Dropdown
    const sortSelect = document.getElementById('sort-select');
    if (sortSelect) {
        sortSelect.addEventListener('change', () => {
            currentSort = sortSelect.value;
            renderDashboard();
        });
    }

    // Quick Increment Chips in Form
    const amountInput = document.getElementById('amount-input');
    document.querySelectorAll('.chip-btn[data-add]').forEach(btn => {
        btn.addEventListener('click', () => {
            const addVal = parseInt(btn.getAttribute('data-add'), 10);
            const current = Math.max(0, parseInt(amountInput.value, 10) || 0);
            amountInput.value = Math.max(0, current + addVal);
            amountInput.focus();
        });
    });

    const clearAmountBtn = document.getElementById('clear-amount-btn');
    if (clearAmountBtn) {
        clearAmountBtn.addEventListener('click', () => {
            amountInput.value = '';
            amountInput.focus();
        });
    }

    // Category Selector
    document.querySelectorAll('.cat-pill-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.cat-pill-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
        });
    });

    // Type Selector
    document.querySelectorAll('.type-pill-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.type-pill-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
        });
    });

    // Date Picker Controls
    const nativeDateInput = document.getElementById('native-date-input');
    const pickDateBtn = document.getElementById('open-native-datepicker-btn');
    if (pickDateBtn && nativeDateInput) {
        pickDateBtn.addEventListener('click', () => {
            if ('showPicker' in HTMLInputElement.prototype) {
                nativeDateInput.showPicker();
            } else {
                nativeDateInput.click();
            }
        });
        nativeDateInput.addEventListener('change', () => {
            setDateValue(nativeDateInput.value);
        });
    }

    const quickDateToday = document.getElementById('quick-date-today');
    if (quickDateToday) {
        quickDateToday.addEventListener('click', () => {
            setDateValue(new Date().toISOString().split('T')[0]);
        });
    }

    const quickDateYesterday = document.getElementById('quick-date-yesterday');
    if (quickDateYesterday) {
        quickDateYesterday.addEventListener('click', () => {
            const yest = new Date();
            yest.setDate(yest.getDate() - 1);
            setDateValue(yest.toISOString().split('T')[0]);
        });
    }

    // Form Submit Handler
    const expenseForm = document.getElementById('expense-form');
    if (expenseForm) {
        expenseForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const submitBtn = document.getElementById('form-submit-btn');
            const id = document.getElementById('edit-expense-id').value;
            const localId = document.getElementById('edit-expense-localId').value || Date.now().toString();
            const amount = Math.max(0, parseFloat(amountInput.value) || 0);
            const name = document.getElementById('expense-name-input').value.trim();
            const category = getSelectedCategory();
            const type = getSelectedType();
            const date = nativeDateInput.value || new Date().toISOString().split('T')[0];

            if (!amount) {
                showToast('Please enter a valid amount');
                return;
            }

            submitBtn.disabled = true;
            submitBtn.textContent = 'Saving...';

            try {
                if (isGuestMode) {
                    if (id) {
                        const idx = currentExpenses.findIndex(item => item._id === id);
                        if (idx !== -1) {
                            currentExpenses[idx] = { ...currentExpenses[idx], name, amount, category, type, date };
                        }
                        showToast('Transaction updated!');
                    } else {
                        const created = { _id: 'demo_' + Date.now(), localId, name, amount, category, type, date };
                        currentExpenses.unshift(created);
                        showToast('Transaction saved!');
                    }
                    localStorage.setItem('unmurce_demo_expenses', JSON.stringify(currentExpenses));
                    renderDashboard();
                    navigateToView('dashboard');
                    return;
                }

                const headers = await authHeaders();
                if (id) {
                    // Update
                    const res = await fetch(`${API_BASE_URL}/users/${id}`, {
                        method: 'PUT',
                        headers,
                        body: JSON.stringify({ name, amount, category, type, date })
                    });
                    if (!res.ok) throw new Error('Update failed');
                    const updated = await res.json();
                    const idx = currentExpenses.findIndex(item => item._id === id);
                    if (idx !== -1) currentExpenses[idx] = updated;
                    showToast('Transaction updated!');
                } else {
                    // Create
                    const res = await fetch(`${API_BASE_URL}/users`, {
                        method: 'POST',
                        headers,
                        body: JSON.stringify({ localId, name, amount, category, type, date })
                    });
                    if (!res.ok) throw new Error('Create failed');
                    const created = await res.json();
                    currentExpenses.unshift(created);
                    showToast('Transaction saved!');
                }

                navigateToView('dashboard');
            } catch (err) {
                console.error('Error saving expense:', err);
                showToast('Failed to save: ' + err.message);
            } finally {
                submitBtn.disabled = false;
            }
        });
    }

    // Form Delete Button Handler
    const formDeleteBtn = document.getElementById('form-delete-btn');
    if (formDeleteBtn) {
        formDeleteBtn.addEventListener('click', () => {
            if (!editingExpenseId) return;
            showConfirmDialog('Delete Transaction', 'Are you sure you want to permanently delete this expense?', async () => {
                if (isGuestMode) {
                    currentExpenses = currentExpenses.filter(e => e._id !== editingExpenseId);
                    localStorage.setItem('unmurce_demo_expenses', JSON.stringify(currentExpenses));
                    renderDashboard();
                    showToast('Transaction deleted');
                    navigateToView('dashboard');
                    return;
                }
                try {
                    const headers = await authHeaders();
                    await fetch(`${API_BASE_URL}/users/${editingExpenseId}`, {
                        method: 'DELETE',
                        headers
                    });
                    currentExpenses = currentExpenses.filter(e => e._id !== editingExpenseId);
                    showToast('Transaction deleted');
                    navigateToView('dashboard');
                } catch (err) {
                    showToast('Failed to delete: ' + err.message);
                }
            });
        });
    }

    // Receipt OCR Controls
    const ocrCameraBtn = document.getElementById('ocr-trigger-camera-btn');
    const ocrGalleryBtn = document.getElementById('ocr-trigger-gallery-btn');
    const ocrCameraInput = document.getElementById('ocr-camera-input');
    const ocrGalleryInput = document.getElementById('ocr-gallery-input');
    const ocrRemoveImgBtn = document.getElementById('ocr-remove-img-btn');
    const ocrZoomBtn = document.getElementById('ocr-zoom-btn');
    const ocrChangeDateBtn = document.getElementById('ocr-change-date-btn');
    const ocrNativeDate = document.getElementById('ocr-native-date');
    const ocrSelectAllBtn = document.getElementById('ocr-select-all-btn');
    const ocrDeselectAllBtn = document.getElementById('ocr-deselect-all-btn');
    const ocrAddManualBtn = document.getElementById('ocr-add-manual-item-btn');
    const ocrSaveSelectedBtn = document.getElementById('ocr-save-selected-btn');

    if (ocrCameraBtn && ocrCameraInput) {
        ocrCameraBtn.addEventListener('click', () => ocrCameraInput.click());
        ocrCameraInput.addEventListener('change', (e) => {
            if (e.target.files && e.target.files[0]) handleReceiptImageSelected(e.target.files[0]);
        });
    }

    if (ocrGalleryBtn && ocrGalleryInput) {
        ocrGalleryBtn.addEventListener('click', () => ocrGalleryInput.click());
        ocrGalleryInput.addEventListener('change', (e) => {
            if (e.target.files && e.target.files[0]) handleReceiptImageSelected(e.target.files[0]);
        });
    }

    if (ocrRemoveImgBtn) {
        ocrRemoveImgBtn.addEventListener('click', () => {
            setupReceiptOcr();
        });
    }

    if (ocrZoomBtn) {
        ocrZoomBtn.addEventListener('click', () => {
            const zoomModal = document.getElementById('receipt-zoom-modal');
            const zoomImg = document.getElementById('modal-receipt-img');
            if (zoomModal && zoomImg && currentReceiptPhotoBase64) {
                zoomImg.src = currentReceiptPhotoBase64;
                zoomModal.hidden = false;
            }
        });
    }

    const closeZoomBtn = document.getElementById('close-receipt-zoom-btn');
    if (closeZoomBtn) {
        closeZoomBtn.addEventListener('click', () => {
            document.getElementById('receipt-zoom-modal').hidden = true;
        });
    }

    if (ocrChangeDateBtn && ocrNativeDate) {
        ocrChangeDateBtn.addEventListener('click', () => {
            if ('showPicker' in HTMLInputElement.prototype) ocrNativeDate.showPicker();
            else ocrNativeDate.click();
        });
        ocrNativeDate.addEventListener('change', () => {
            ocrReceiptDate = ocrNativeDate.value;
            updateOcrDateLabel(ocrReceiptDate);
        });
    }

    if (ocrSelectAllBtn) {
        ocrSelectAllBtn.addEventListener('click', () => {
            detectedOcrItems.forEach(i => i.selected = true);
            renderDetectedOcrItems();
        });
    }

    if (ocrDeselectAllBtn) {
        ocrDeselectAllBtn.addEventListener('click', () => {
            detectedOcrItems.forEach(i => i.selected = false);
            renderDetectedOcrItems();
        });
    }

    if (ocrAddManualBtn) {
        ocrAddManualBtn.addEventListener('click', addManualOcrItem);
    }

    if (ocrSaveSelectedBtn) {
        ocrSaveSelectedBtn.addEventListener('click', saveSelectedOcrItems);
    }

    // Settings Controls
    const settingsSignOutBtn = document.getElementById('settings-sign-out-btn');
    if (settingsSignOutBtn) {
        settingsSignOutBtn.addEventListener('click', () => {
            if (isGuestMode) {
                isGuestMode = false;
                document.getElementById('auth-panel').hidden = false;
                document.getElementById('app-viewport').hidden = true;
                currentExpenses = [];
                showToast('Signed out of Demo Mode');
            } else {
                auth.signOut();
            }
        });
    }

    const settingsExportPdfBtn = document.getElementById('settings-export-pdf-btn');
    if (settingsExportPdfBtn) settingsExportPdfBtn.addEventListener('click', exportPdfReport);

    const settingsExportJsonBtn = document.getElementById('settings-export-json-btn');
    if (settingsExportJsonBtn) settingsExportJsonBtn.addEventListener('click', exportJsonBackup);

    const settingsDeleteAllBtn = document.getElementById('settings-delete-all-btn');
    if (settingsDeleteAllBtn) {
        settingsDeleteAllBtn.addEventListener('click', () => {
            showConfirmDialog('Reset All Data', 'Are you sure you want to permanently erase all your expenses? This cannot be undone.', async () => {
                if (isGuestMode) {
                    currentExpenses = [];
                    localStorage.removeItem('unmurce_demo_expenses');
                    showToast('All transactions wiped clean');
                    renderDashboard();
                    return;
                }
                try {
                    const headers = await authHeaders();
                    await fetch(`${API_BASE_URL}/users/delete-all`, {
                        method: 'POST',
                        headers
                    });
                    currentExpenses = [];
                    showToast('All transactions wiped clean');
                    navigateToView('dashboard');
                } catch (err) {
                    showToast('Failed to reset data: ' + err.message);
                }
            });
        });
    }

    // Visibility change handler for quick sync check
    document.addEventListener('visibilitychange', () => {
        if (!document.hidden && auth.currentUser) {
            fetchExpenses(false);
        }
    });
});
