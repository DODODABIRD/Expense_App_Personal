const form = document.getElementById('expense-form');
const list = document.getElementById('expense-list');

async function fetchExpenses() {
    try {
        const response = await fetch('/api/expenses');
        const expenses = await response.json();
        renderExpenses(expenses);
    } catch (error) {
        console.error('Error fetching expenses:', error);
    }
}

function renderExpenses(expenses) {
    list.innerHTML = '';
    expenses.forEach(expense => {
        const li = document.createElement('li');
        li.innerHTML = `
            <span>${expense.description}</span>
            <span class="amount">$${expense.amount.toFixed(2)}</span>
        `;
        list.appendChild(li);
    });
}

function reloadSHIT() {
    const response = fetch('/api/expenses');
    const expenses = response.json();
    list.innerHTML = '';
    expenses.forEach(expense => {
        const li = document.createElement('li');
        li.innerHTML = `
            <span>${expense.description}</span>
            <span class="amount">$${expense.amount.toFixed(2)}</span>
        `;
        list.appendChild(li);
    });
}


form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const description = document.getElementById('description').value;
    const amount = document.getElementById('amount').value;

    try {
        const response = await fetch('/api/expenses', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ description, amount })
        });

        if (response.ok) {
            form.reset();
            fetchExpenses();
        } else {
            alert('Failed to add expense');
        }
    } catch (error) {
        console.error('Error adding expense:', error);
    }
});

fetchExpenses();
