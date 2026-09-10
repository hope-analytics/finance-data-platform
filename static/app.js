const form = document.getElementById("expenseForm");
const message = document.getElementById("message");
const saveButton = document.getElementById("saveButton");
const expensesContainer = document.getElementById("expensesContainer");
const refreshButton = document.getElementById("refreshButton");


// ---------------------------------
// Set today's date
// ---------------------------------

function setToday() {
    const today = new Date();

    const year = today.getFullYear();
    const month = String(today.getMonth() + 1).padStart(2, "0");
    const day = String(today.getDate()).padStart(2, "0");

    document.getElementById("transaction_date").value =
        `${year}-${month}-${day}`;
}


// ---------------------------------
// Show message
// ---------------------------------

function showMessage(text, type) {

    message.textContent = text;
    message.className = `message ${type}`;

}


// ---------------------------------
// Format amount
// ---------------------------------

function formatAmount(amount) {

    return new Intl.NumberFormat("en-PH", {
        style: "currency",
        currency: "PHP"
    }).format(amount);

}


// ---------------------------------
// Format date
// ---------------------------------

function formatDate(dateString) {

    const date = new Date(dateString + "T00:00:00");

    return date.toLocaleDateString("en-PH", {
        year: "numeric",
        month: "short",
        day: "numeric"
    });

}


// ---------------------------------
// Load expenses
// ---------------------------------

async function loadExpenses() {

    expensesContainer.innerHTML =
        `<p class="loading">Loading expenses...</p>`;

    try {

        const response = await fetch("/app/expenses");

        if (!response.ok) {
            throw new Error("Failed to load expenses");
        }

        const expenses = await response.json();

        if (expenses.length === 0) {

            expensesContainer.innerHTML =
                `<p class="empty">No expenses recorded yet.</p>`;

            return;
        }


        const list = document.createElement("div");
        list.className = "expense-list";


        expenses.forEach(expense => {

            const row = document.createElement("div");
            row.className = "expense-row";

            row.innerHTML = `
                <div class="expense-date">
                    ${formatDate(expense.transaction_date)}
                </div>

                <div>
                    <div class="expense-merchant">
                        ${escapeHtml(expense.merchant)}
                    </div>

                    <div class="expense-details">
                        ${expense.payment_source}
                        ${expense.category ? " · " + escapeHtml(expense.category) : ""}
                    </div>
                </div>

                <div class="expense-amount">
                    ${formatAmount(expense.amount)}
                </div>
            `;

            list.appendChild(row);

        });


        expensesContainer.innerHTML = "";
        expensesContainer.appendChild(list);

    } catch (error) {

        expensesContainer.innerHTML =
            `<p class="empty">Unable to load expenses.</p>`;

        console.error(error);
    }
}


// ---------------------------------
// Basic HTML escaping
// ---------------------------------

function escapeHtml(value) {

    if (value === null || value === undefined) {
        return "";
    }

    return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}


// ---------------------------------
// Submit expense
// ---------------------------------

form.addEventListener("submit", async function(event) {

    event.preventDefault();

    saveButton.disabled = true;
    saveButton.textContent = "Saving...";

    message.className = "message";


    const expense = {

        transaction_date:
            document.getElementById("transaction_date").value,

        merchant:
            document.getElementById("merchant").value.trim(),

        description:
            document.getElementById("description").value.trim() || null,

        amount:
            document.getElementById("amount").value,

        category:
            document.getElementById("category").value.trim() || null,

        payment_source:
            document.getElementById("payment_source").value,

        notes:
            document.getElementById("notes").value.trim() || null
    };


    try {

        const response = await fetch("/app/expenses", {

            method: "POST",

            headers: {
                "Content-Type": "application/json"
            },

            body: JSON.stringify(expense)
        });


        const data = await response.json();


        if (!response.ok) {

            throw new Error(
                data.detail || "Failed to save expense"
            );
        }


        showMessage(
            `Expense saved successfully.`,
            "success"
        );


        // Reset form
        form.reset();

        // Put today's date back
        setToday();

        // Put cursor back on merchant
        document.getElementById("merchant").focus();


        // Refresh expense list
        await loadExpenses();


    } catch (error) {

        console.error(error);

        showMessage(
            error.message || "Something went wrong.",
            "error"
        );

    } finally {

        saveButton.disabled = false;
        saveButton.textContent = "Save Expense";

    }

});


// ---------------------------------
// Refresh button
// ---------------------------------

refreshButton.addEventListener(
    "click",
    loadExpenses
);


// ---------------------------------
// Initial page load
// ---------------------------------

setToday();
loadExpenses();

const paymentOptions = document.querySelectorAll(".payment-option");
const paymentSource = document.getElementById("payment_source");

paymentOptions.forEach(button => {
    button.addEventListener("click", () => {

        paymentSource.value = button.dataset.value;

        paymentOptions.forEach(option => {
            option.classList.remove("selected");
        });

        button.classList.add("selected");
    });
});