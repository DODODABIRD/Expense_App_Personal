const form = document.getElementById('expense-form');
const list = document.getElementById('expense-list');
const totalAmountDisplay = document.getElementById('total-amount');
const refreshBtn = document.getElementById('refresh-btn');
const downloadBtn = document.getElementById('download-btn');
let currentExpenses = [];

function formatCurrency(value) {
    return new Intl.NumberFormat('id-ID', {
        style: 'currency',
        currency: 'IDR',
        maximumFractionDigits: 0
    }).format(value);
}

async function fetchExpenses() {
    try {
        const response = await fetch('/api/users');
        if (!response.ok) throw new Error('Failed to fetch');
        
        const expenses = await response.json();
        renderExpenses(expenses);
    } catch (error) {
        console.error('Error fetching expenses:', error);
    }
}

function renderExpenses(expenses) {
    list.innerHTML = '';
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
    });

    currentExpenses = sortedExpenses;
    totalAmountDisplay.textContent = formatCurrency(total);
    totalAmountDisplay.style.color = total >= 0 ? '#10b981' : '#ef4444';
}

function downloadCsv() {
    if (!currentExpenses.length) {
        alert('No transactions to download');
        return;
    }

    let total = 0;
    const rows = [
        ['Date', 'Name', 'Category', 'Type', 'Amount']
    ];

    currentExpenses.forEach(expense => {
        const amount = parseFloat(expense.amount) || 0;
        if (expense.type === 'Expense') {
            total -= amount;
        } else {
            total += amount;
        }

        rows.push([
            expense.date || '',
            expense.name || '',
            expense.category || '',
            expense.type || '',
            formatCurrency(amount)
        ]);
    });

    rows.push([]);
    rows.push(['', '', '', 'Total', formatCurrency(total)]);

    const csv = rows.map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\r\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `expenses_${new Date().toISOString().slice(0,10)}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

downloadBtn.addEventListener('click', downloadCsv);

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
            headers: {
                'Content-Type': 'application/json'
            },
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

refreshBtn.addEventListener('click', fetchExpenses);

// Initial fetch
fetchExpenses();
