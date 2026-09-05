const firebaseConfig = {
    apiKey: 'AIzaSyBScOUH8uoz0OjzmeMZpIAegniNU-axDEI',
    authDomain: 'unmurce-2f3e3.firebaseapp.com',
    projectId: 'unmurce-2f3e3',
    storageBucket: 'unmurce-2f3e3.firebasestorage.app',
    messagingSenderId: '515835567480',
    appId: '1:515835567480:web:13c5d1a0159cabb645bc8d'
};

firebase.initializeApp(firebaseConfig);
const auth = firebase.auth();
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
const downloadBtn = document.getElementById('download-btn');
let currentExpenses = [];
let isRegistering = false;
let refreshTimer = null;
let isFetchingExpenses = false;

function setAuthMode(registering) {
    isRegistering = registering;
    authTitle.textContent = registering ? 'Create account' : 'Sign in';
    authKicker.textContent = registering ? 'NEW ACCOUNT' : 'WELCOME BACK';
    authSubmit.textContent = registering ? 'Create account' : 'Sign in';
    authToggle.textContent = registering ? 'Already have an account? Sign in' : 'Create an account';
    authPassword.autocomplete = registering ? 'new-password' : 'current-password';
    authError.textContent = '';
}

function showDashboard(user) {
    authPanel.hidden = true;
    dashboard.hidden = false;
    signedInUser.textContent = user.email || '';
    fetchExpenses();
    startAutoRefresh();
}

function showAuth() {
    stopAutoRefresh();
    authPanel.hidden = false;
    dashboard.hidden = true;
    signedInUser.textContent = '';
    list.innerHTML = '';
    mobileCards.innerHTML = '';
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

async function fetchExpenses() {
    if (isFetchingExpenses || !auth.currentUser) return;
    isFetchingExpenses = true;
    try {
        const response = await fetch('/api/users', { headers: await authHeaders() });
        if (!response.ok) throw new Error('Failed to fetch');
        
        const expenses = await response.json();
        renderExpenses(expenses);
    } catch (error) {
        console.error('Error fetching expenses:', error);
    } finally {
        isFetchingExpenses = false;
    }
}

function renderExpenses(expenses) {
    list.innerHTML = '';
    mobileCards.innerHTML = '';
    let total = 0;

    // Sort by date descending if possible
    const sortedExpenses = [...expenses].sort((a, b) => new Date(b.date) - new Date(a.date));

    sortedExpenses.forEach(expense => {
        const name = expense.name || 'Unnamed';
        const amount = parseFloat(expense.amount) || 0;
        const date = expense.date || 'N/A';
        const category = expense.category || 'General';
        const type = expense.type || 'Expense';

        if (type === 'Expense') {
            total -= amount;
        } else {
            total += amount;
        }

        // Table row
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td>${date}</td>
            <td>${name}</td>
            <td>${category}</td>
            <td>${type}</td>
            <td class="amount" style="color: ${type === 'Expense' ? '#ef4444' : '#10b981'}">
                ${type === 'Expense' ? '-' : '+'}${formatCurrency(Math.abs(amount))}
            </td>
        `;
        list.appendChild(tr);

        // Mobile card
        const card = document.createElement('div');
        card.className = 'card';
        card.innerHTML = `
            <div class="card-row">
                <span class="label">Date:</span>
                <span class="value">${date}</span>
            </div>
            <div class="card-row">
                <span class="label">Name:</span>
                <span class="value">${name}</span>
            </div>
            <div class="card-row">
                <span class="label">Category:</span>
                <span class="value">${category}</span>
            </div>
            <div class="card-row">
                <span class="label">Type:</span>
                <span class="value">${type}</span>
            </div>
            <div class="card-row">
                <span class="label">Amount:</span>
                <span class="value amount" style="color: ${type === 'Expense' ? '#ef4444' : '#10b981'}">
                    ${type === 'Expense' ? '-' : '+'}${formatCurrency(Math.abs(amount))}
                </span>
            </div>
        `;
        mobileCards.appendChild(card);
    });

    currentExpenses = sortedExpenses;
    totalAmountDisplay.textContent = formatCurrency(total);
    totalAmountDisplay.style.color = total >= 0 ? '#10b981' : '#ef4444';
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
    doc.text('Pengeluaran Dodo', 40, 40);
    doc.setFontSize(11);
    doc.text(`Generated: ${new Date().toLocaleDateString('id-ID')}`, 40, 60);

    doc.autoTable({
        startY: 80,
        head: [[ 'Date', 'Name', 'Category', 'Type', 'Amount' ]],
        body: rows,
        foot: [[ '', '', '', 'Total', formatCurrency(total) ]],
        styles: { fontSize: 10, cellPadding: 6 },
        headStyles: { fillColor: [79, 70, 229], textColor: 255 },
        footStyles: { fillColor: [240, 240, 240], textColor: 0, fontStyle: 'bold' },
        alternateRowStyles: { fillColor: [245, 245, 245] },
        columnStyles: {
            4: { halign: 'right' }
        }
    });

    doc.save(`Pengeluaran_Dodo_${new Date().toISOString().slice(0,10)}.pdf`);
}

authToggle.addEventListener('click', () => setAuthMode(!isRegistering));

authForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    authError.textContent = '';
    authSubmit.disabled = true;
    try {
        if (isRegistering) {
            await auth.createUserWithEmailAndPassword(authEmail.value.trim(), authPassword.value);
        } else {
            await auth.signInWithEmailAndPassword(authEmail.value.trim(), authPassword.value);
        }
        authForm.reset();
    } catch (error) {
        authError.textContent = error.message.replace('Firebase: ', '').replace(/ \(auth\/.*\)\.?$/, '');
    } finally {
        authSubmit.disabled = false;
    }
});

signOutBtn.addEventListener('click', () => auth.signOut());

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

if (downloadBtn) {
    downloadBtn.addEventListener('click', downloadPdf);
}

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
            const response = await fetch('/api/users', {
                method: 'POST',
                headers: await authHeaders(),
                body: JSON.stringify(payload)
            });

            if (response.ok) {
                form.reset();
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

if (refreshBtn) {
    refreshBtn.addEventListener('click', fetchExpenses);
}

