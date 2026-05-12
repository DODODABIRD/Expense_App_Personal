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
    doc.text('Expense Transactions', 40, 40);
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

    doc.save(`transactions_${new Date().toISOString().slice(0,10)}.pdf`);
}

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
}

if (refreshBtn) {
    refreshBtn.addEventListener('click', fetchExpenses);
}

// Initial fetch
fetchExpenses();
