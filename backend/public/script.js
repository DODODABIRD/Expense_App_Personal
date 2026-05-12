const form = document.getElementById('expense-form');
const list = document.getElementById('expense-list');
const totalAmountDisplay = document.getElementById('total-amount');
const refreshBtn = document.getElementById('refresh-btn');

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
        const id = expense._id;

        if (type === 'Expense') {
            total -= amount;
        } else {
            total += amount;
        }

        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td>${date}</td>
            <td>
                <div><strong>${name}</strong></div>
                <small style="color: #64748b">${category} • ${type}</small>
            </td>
            <td class="amount" style="color: ${type === 'Expense' ? '#ef4444' : '#10b981'}">
                ${type === 'Expense' ? '-' : '+'}$${Math.abs(amount).toFixed(2)}
            </td>
            <td>
                <button class="delete-btn" onclick="deleteExpense('${id}')">Delete</button>
            </td>
        `;
        list.appendChild(tr);
    });

    totalAmountDisplay.textContent = `$${total.toFixed(2)}`;
    totalAmountDisplay.style.color = total >= 0 ? '#10b981' : '#ef4444';
}

async function deleteExpense(id) {
    if (!confirm('Are you sure you want to delete this?')) return;

    try {
        const response = await fetch(`/api/users/${id}`, { method: 'DELETE' });
        if (response.ok) {
            fetchExpenses();
        } else {
            alert('Failed to delete');
        }
    } catch (error) {
        console.error('Error deleting:', error);
    }
}

form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = document.getElementById('name').value;
    const amount = document.getElementById('amount').value;
    const category = document.getElementById('category').value;
    const type = document.getElementById('type').value;
    
    const payload = {
        localId: Date.now().toString(),
        name: name,
        amount: amount.toString(),
        category: category,
        type: type,
        date: new Date().toISOString().split('T')[0]
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
