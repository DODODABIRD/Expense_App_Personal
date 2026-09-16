const firebaseConfig = {
    apiKey: 'AIzaSyBScOUH8uoz0OjzmeMZpIAegniNU-axDEI',
    authDomain: 'unmurce-2f3e3.firebaseapp.com',
    projectId: 'unmurce-2f3e3',
    storageBucket: 'unmurce-2f3e3.firebasestorage.app',
    messagingSenderId: '515835567480',
    appId: '1:515835567480:web:13c5d1a0159cabb645bc8d'
};

const API_BASE_URL = (
    window.EXPENSE_API_BASE_URL || 'https://dododabird.us/api'
).replace(/\/+$/, '');

firebase.initializeApp(firebaseConfig);
const auth = firebase.auth();

// DOM Element references
const authPanel = document.getElementById('auth-panel');
const authForm = document.getElementById('auth-form');
const authEmail = document.getElementById('auth-email');
const authPassword = document.getElementById('auth-password');
const authError = document.getElementById('auth-error');
const authSubmit = document.getElementById('auth-submit');
const authToggle = document.getElementById('auth-toggle');
const authTitle = document.getElementById('auth-title');
const authKicker = document.getElementById('auth-kicker');
const dashboard = document.querySelector('.dashboard');
const signedInUser = document.getElementById('signed-in-user');
const signOutBtn = document.getElementById('sign-out-btn');
const form = document.getElementById('expense-form');
const list = document.getElementById('expense-list');
const mobileCards = document.getElementById('mobile-cards');
const totalAmountDisplay = document.getElementById('total-amount');
const refreshBtn = document.getElementById('refresh-btn');
const navRefreshBtn = document.getElementById('nav-refresh-btn');
const downloadBtn = document.getElementById('download-btn');
const openAddBtn = document.getElementById('open-add-btn');
const navAddBtn = document.getElementById('nav-add-btn');
const navHomeBtn = document.getElementById('nav-home-btn');
const modalOverlay = document.getElementById('add-modal-overlay');
const closeModalBtn = document.getElementById('close-modal-btn');
const cancelModalBtn = document.getElementById('cancel-modal-btn');

let currentExpenses = [];
let isRegistering = false;
let refreshTimer = null;
let isFetchingExpenses = false;

// Category SVG Icons matching reference image style
function getCategoryIconSvg(category) {
    const cat = String(category || '').toLowerCase();
    
    // Burger & drink icon from screenshot for food/makanan
    if (cat.includes('makanan') || cat.includes('food') || cat.includes('kopi') || cat.includes('drink')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path>
            <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
            <line x1="2" y1="12" x2="22" y2="12"></line>
        </svg>`;
    }
    
    // Transport icon
    if (cat.includes('transport') || cat.includes('bensin') || cat.includes('car')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="1" y="3" width="15" height="13" rx="2"></rect>
            <polygon points="16 8 20 8 23 11 23 16 16 16 16 8"></polygon>
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

    // Apparel / Shopping
    if (cat.includes('baju') || cat.includes('apparel') || cat.includes('shop')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"></path>
            <line x1="3" y1="6" x2="21" y2="6"></line>
            <path d="M16 10a4 4 0 0 1-8 0"></path>
        </svg>`;
    }

    // Health
    if (cat.includes('kesehatan') || cat.includes('health') || cat.includes('medical')) {
        return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"></path>
        </svg>`;
    }

    // Default Dollar / Expense icon
    return `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <line x1="12" y1="1" x2="12" y2="23"></line>
        <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path>
    </svg>`;
}

function setAuthMode(registering) {
    isRegistering = registering;
    authTitle.textContent = registering ? 'Create account' : 'Sign in';
    authKicker.textContent = registering ? 'NEW ACCOUNT' : 'WELCOME BACK';
    authSubmit.textContent = registering ? 'Create account' : 'Sign in';
    authToggle.textContent = registering ? 'Already have an account? Sign in' : 'Create an account';
    authPassword.autocomplete = registering ? 'new-password' : 'current-password';
    authError.textContent = '';
}

let typewriterTimer = null;
let typewriterState = {
    phraseIndex: 0,
    charIndex: 0,
    isDeleting: false,
    email: ''
};

const WELCOME_GREETINGS = [
    { prefix: "Welcome back, ", suffix: "" },
    { prefix: "Selamat datang kembali, ", suffix: "" },
    { prefix: "Bienvenido de nuevo, ", suffix: "" },
    { prefix: "おかえりなさい, ", suffix: "" },
    { prefix: "Bon retour, ", suffix: "" },
    { prefix: "Willkommen zurück, ", suffix: "" },
    { prefix: "환영합니다, ", suffix: "" },
    { prefix: "Bentornato, ", suffix: "" },
    { prefix: "С возвращением, ", suffix: "" },
    { prefix: "欢迎回来, ", suffix: "" }
];

function stopWelcomeTypewriter() {
    if (typewriterTimer) {
        clearTimeout(typewriterTimer);
        typewriterTimer = null;
    }
    typewriterState = { phraseIndex: 0, charIndex: 0, isDeleting: false, email: '' };
    if (signedInUser) signedInUser.innerHTML = '';
}

function escapeHtml(str) {
    return String(str || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function startWelcomeTypewriter(userEmail) {
    stopWelcomeTypewriter();
    if (!signedInUser || !userEmail) return;

    typewriterState.email = userEmail;
    
    function tick() {
        if (!auth.currentUser) return;

        const currentGreeting = WELCOME_GREETINGS[typewriterState.phraseIndex % WELCOME_GREETINGS.length];
        const fullText = `${currentGreeting.prefix}${typewriterState.email}${currentGreeting.suffix}`;
        
        let targetText = '';
        if (typewriterState.isDeleting) {
            typewriterState.charIndex--;
            targetText = fullText.substring(0, typewriterState.charIndex);
        } else {
            typewriterState.charIndex++;
            targetText = fullText.substring(0, typewriterState.charIndex);
        }

        const prefixLen = currentGreeting.prefix.length;
        if (targetText.length <= prefixLen) {
            signedInUser.innerHTML = `<span class="typewriter-text">${escapeHtml(targetText)}</span><span class="typewriter-cursor"></span>`;
        } else {
            const prefixPart = targetText.substring(0, prefixLen);
            const emailPart = targetText.substring(prefixLen);
            signedInUser.innerHTML = `<span class="typewriter-text">${escapeHtml(prefixPart)}</span><span class="typewriter-email">${escapeHtml(emailPart)}</span><span class="typewriter-cursor"></span>`;
        }

        let delay = typewriterState.isDeleting ? 30 : 55 + Math.floor(Math.random() * 35);

        if (!typewriterState.isDeleting && targetText === fullText) {
            delay = 2400;
            typewriterState.isDeleting = true;
        } else if (typewriterState.isDeleting && targetText === '') {
            typewriterState.isDeleting = false;
            typewriterState.phraseIndex = (typewriterState.phraseIndex + 1) % WELCOME_GREETINGS.length;
            delay = 350;
        }

        typewriterTimer = setTimeout(tick, delay);
    }

    tick();
}

function showDashboard(user) {
    if (authPanel) authPanel.hidden = true;
    if (dashboard) dashboard.hidden = false;
    const bottomNav = document.getElementById('bottom-nav');
    if (bottomNav) bottomNav.style.display = 'flex';
    startWelcomeTypewriter(user.email || 'User');
    fetchExpenses();
    startAutoRefresh();
}

function showAuth() {
    stopAutoRefresh();
    stopWelcomeTypewriter();
    if (authPanel) authPanel.hidden = false;
    if (dashboard) dashboard.hidden = true;
    const bottomNav = document.getElementById('bottom-nav');
    if (bottomNav) bottomNav.style.display = 'none';
    if (list) list.innerHTML = '';
    if (mobileCards) mobileCards.innerHTML = '';
    currentExpenses = [];
}

function startAutoRefresh() {
    stopAutoRefresh();
    refreshTimer = window.setInterval(() => {
        if (!document.hidden && auth.currentUser) fetchExpenses();
    }, 5 * 60 * 1000);
}

function stopAutoRefresh() {
    if (refreshTimer !== null) {
        window.clearInterval(refreshTimer);
        refreshTimer = null;
    }
}

async function authHeaders() {
    const user = auth.currentUser;
    if (!user) throw new Error('Please sign in first');
    return {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${await user.getIdToken()}`
    };
}

function formatCurrency(value) {
    return new Intl.NumberFormat('id-ID', {
        style: 'currency',
        currency: 'IDR',
        maximumFractionDigits: 0
    }).format(value);
}

function formatDateDisplay(dateStr) {
    if (!dateStr) return '14 Sep 2026';
    const dateObj = new Date(dateStr);
    if (isNaN(dateObj.getTime())) return dateStr;
    return dateObj.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

async function fetchExpenses() {
    if (isFetchingExpenses || !auth.currentUser) return;
    isFetchingExpenses = true;
    try {
        const response = await fetch(`${API_BASE_URL}/users`, { headers: await authHeaders() });
        if (!response.ok) throw new Error('Failed to fetch');
        
        const expenses = await response.json();
        renderExpenses(expenses);
    } catch (error) {
        console.error('Error fetching expenses:', error);
    } finally {
        isFetchingExpenses = false;
    }
}

async function deleteExpense(id) {
    if (!id) return;
    if (!confirm('Are you sure you want to delete this transaction?')) return;

    try {
        const response = await fetch(`${API_BASE_URL}/users/${id}`, {
            method: 'DELETE',
            headers: await authHeaders()
        });

        if (response.ok) {
            fetchExpenses();
        } else {
            alert('Failed to delete transaction.');
        }
    } catch (error) {
        console.error('Error deleting:', error);
    }
}

function renderExpenses(expenses) {
    if (list) list.innerHTML = '';
    if (mobileCards) mobileCards.innerHTML = '';
    let total = 0;

    const displayExpenses = (expenses && expenses.length > 0) ? expenses : [
        { _id: 'demo1', name: 'Nasi Uduk', amount: 17000, category: 'makanan', type: 'Expense', date: '2026-09-14' },
        { _id: 'demo2', name: 'ayam xiao kee', amount: 24000, category: 'makanan', type: 'Expense', date: '2026-09-14' },
        { _id: 'demo3', name: 'Makanan', amount: 24000, category: 'makanan', type: 'Expense', date: '2026-09-14' },
        { _id: 'demo4', name: '/C ONIGIRI AYM AS M', amount: 13000, category: 'makanan', type: 'Expense', date: '2026-09-14', badge: 'Rp618.302' }
    ];

    const sortedExpenses = [...displayExpenses].sort((a, b) => new Date(b.date || 0) - new Date(a.date || 0));

    sortedExpenses.forEach((expense, index) => {
        const id = expense._id || expense.id;
        const name = expense.name || 'Unnamed';
        const amount = parseFloat(expense.amount) || 0;
        const dateStr = expense.date || '';
        const category = expense.category || 'General';
        const type = expense.type || 'Expense';
        const badgeText = expense.badge || null;

        if (type === 'Expense') {
            total -= amount;
        } else {
            total += amount;
        }

        // Table row for desktop backup
        if (list) {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${formatDateDisplay(dateStr)}</td>
                <td><strong>${name}</strong></td>
                <td>${category}</td>
                <td>${type}</td>
                <td class="amount" style="color: ${type === 'Expense' ? '#ef4444' : '#10b981'}">
                    ${type === 'Expense' ? '-' : '+'}${formatCurrency(Math.abs(amount))}
                </td>
                <td>
                    <button class="delete-btn" onclick="deleteExpense('${id}')">Delete</button>
                </td>
            `;
            list.appendChild(tr);
        }

        // Neo-Brutalist Yellow Card matching reference image
        if (mobileCards) {
            const card = document.createElement('div');
            card.className = 'neo-expense-card';
            
            const iconSvg = getCategoryIconSvg(category);
            const formattedAmount = `${type === 'Expense' ? '' : '+'}${formatCurrency(Math.abs(amount))}`;
            const badgeHtml = badgeText ? `<div class="card-cumulative-badge"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.5"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M7 15h0M2 9.5h20"/></svg> ${badgeText}</div>` : '';

            card.innerHTML = `
                <div class="card-icon-container">
                    ${iconSvg}
                </div>
                <div class="card-info">
                    <span class="item-name">${name}</span>
                    <span class="item-amount">${formattedAmount}</span>
                    <span class="item-date">${formatDateDisplay(dateStr)}</span>
                </div>
                <div class="card-actions">
                    <button class="icon-action-btn delete-btn" title="Delete" type="button" data-id="${id}">
                        ✎
                    </button>
                </div>
                ${badgeHtml}
            `;

            // Attach click handler for delete
            const delBtn = card.querySelector('.delete-btn');
            if (delBtn && id && !id.startsWith('demo')) {
                delBtn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    deleteExpense(id);
                });
            }

            mobileCards.appendChild(card);
        }
    });

    currentExpenses = sortedExpenses;
    if (totalAmountDisplay) {
        totalAmountDisplay.textContent = formatCurrency(Math.abs(total));
        totalAmountDisplay.style.color = '#000000';
    }
}

function downloadPdf() {
    if (!currentExpenses.length) {
        alert('No transactions to download');
        return;
    }

    let total = 0;
    const rows = currentExpenses.map(expense => {
        const amount = parseFloat(expense.amount) || 0;
        if (expense.type === 'Expense') {
            total -= amount;
        } else {
            total += amount;
        }

        return [
            expense.date || '',
            expense.name || '',
            expense.category || '',
            expense.type || '',
            `${expense.type === 'Expense' ? '-' : '+'}${formatCurrency(Math.abs(amount))}`
        ];
    });

    const doc = new window.jspdf.jsPDF({ unit: 'pt', format: 'a4' });
    doc.setFontSize(18);
    doc.text('Pengeluaran Dodo - Unmurce Report', 40, 40);
    doc.setFontSize(11);
    doc.text(`Generated: ${new Date().toLocaleDateString('id-ID')}`, 40, 60);

    doc.autoTable({
        startY: 80,
        head: [[ 'Date', 'Name', 'Category', 'Type', 'Amount' ]],
        body: rows,
        foot: [[ '', '', '', 'Total Balance', formatCurrency(total) ]],
        styles: { fontSize: 10, cellPadding: 8, font: 'helvetica' },
        headStyles: { fillColor: [0, 0, 0], textColor: 255, fontStyle: 'bold' },
        footStyles: { fillColor: [255, 234, 96], textColor: 0, fontStyle: 'bold' },
        alternateRowStyles: { fillColor: [243, 245, 248] },
        columnStyles: {
            4: { halign: 'right' }
        }
    });

    doc.save(`Pengeluaran_Dodo_${new Date().toISOString().slice(0,10)}.pdf`);
}

// Modal Handlers
function openModal() {
    if (modalOverlay) modalOverlay.hidden = false;
    const dateInput = document.getElementById('date');
    if (dateInput && !dateInput.value) {
        dateInput.value = new Date().toISOString().split('T')[0];
    }
}

function closeModal() {
    if (modalOverlay) modalOverlay.hidden = true;
    if (form) form.reset();
}

if (openAddBtn) openAddBtn.addEventListener('click', openModal);
if (navAddBtn) navAddBtn.addEventListener('click', openModal);
if (closeModalBtn) closeModalBtn.addEventListener('click', closeModal);
if (cancelModalBtn) cancelModalBtn.addEventListener('click', closeModal);
if (navHomeBtn) {
    navHomeBtn.addEventListener('click', () => {
        window.scrollTo({ top: 0, behavior: 'smooth' });
    });
}

if (modalOverlay) {
    modalOverlay.addEventListener('click', (e) => {
        if (e.target === modalOverlay) closeModal();
    });
}

if (authToggle) authToggle.addEventListener('click', () => setAuthMode(!isRegistering));

if (authForm) {
    authForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (authError) authError.textContent = '';
        if (authSubmit) authSubmit.disabled = true;
        try {
            if (isRegistering) {
                await auth.createUserWithEmailAndPassword(authEmail.value.trim(), authPassword.value);
            } else {
                await auth.signInWithEmailAndPassword(authEmail.value.trim(), authPassword.value);
            }
            authForm.reset();
        } catch (error) {
            if (authError) {
                authError.textContent = error.message.replace('Firebase: ', '').replace(/ \(auth\/.*\)\.?$/, '');
            }
        } finally {
            if (authSubmit) authSubmit.disabled = false;
        }
    });
}

if (signOutBtn) signOutBtn.addEventListener('click', () => auth.signOut());

auth.onAuthStateChanged((user) => {
    if (user) {
        showDashboard(user);
    } else {
        showAuth();
    }
});

document.addEventListener('visibilitychange', () => {
    if (!document.hidden && auth.currentUser) fetchExpenses();
});

if (downloadBtn) downloadBtn.addEventListener('click', downloadPdf);
if (refreshBtn) refreshBtn.addEventListener('click', fetchExpenses);
if (navRefreshBtn) navRefreshBtn.addEventListener('click', fetchExpenses);

if (form) {
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const name = document.getElementById('name').value;
        const amount = document.getElementById('amount').value;
        const category = document.getElementById('category').value;
        const type = document.getElementById('type').value;
        const date = document.getElementById('date').value;
        
        const payload = {
            localId: Date.now().toString(),
            name: name,
            amount: amount.toString(),
            category: category,
            type: type,
            date: date || new Date().toISOString().split('T')[0]
        };

        try {
            const response = await fetch(`${API_BASE_URL}/users`, {
                method: 'POST',
                headers: await authHeaders(),
                body: JSON.stringify(payload)
            });

            if (response.ok) {
                closeModal();
                fetchExpenses();
            } else {
                const err = await response.json();
                alert('Failed to add: ' + (err.error || 'Unknown error'));
            }
        } catch (error) {
            console.error('Error adding:', error);
        }
    });
}
