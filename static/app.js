const form = document.getElementById("expenseForm");
const message = document.getElementById("message");
const saveButton = document.getElementById("saveButton");
const expensesContainer = document.getElementById("expensesContainer");
const refreshButton = document.getElementById("refreshButton");
const paymentOptionsContainer = document.getElementById("paymentOptions");
const paymentSourceId = document.getElementById("payment_source_id");
const installmentGroup = document.getElementById("installmentGroup");
const installmentCount = document.getElementById("installment_count");
const categoryInput = document.getElementById("category");
const categoryOptions = document.getElementById("categoryOptions");

let selectedPaymentType = null;

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
// Installment visibility
// ---------------------------------

function updateInstallmentVisibility() {

    const isCreditCard =
        selectedPaymentType === "CREDIT_CARD";

    installmentGroup.hidden = !isCreditCard;

    if (!isCreditCard) {
        installmentCount.value = "";
    }
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

    refreshButton.disabled = true;
    refreshButton.textContent = "Refreshing...";

    expensesContainer.innerHTML =
        `<p class="loading">Loading expenses...</p>`;

    try {

        const response = await fetch("/app/expenses");

        if (!response.ok) {
            throw new Error("Failed to load expenses");
        }

        const expenses = await parseResponse(response);

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
                        ${escapeHtml(expense.payment_name)}
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
    } finally {

        refreshButton.disabled = false;
        refreshButton.textContent = "Refresh";
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
// Parse API response
// ---------------------------------

async function parseResponse(response) {

    const contentType =
        response.headers.get("content-type") || "";

    if (contentType.includes("application/json")) {
        return await response.json();
    }

    const text = await response.text();

    return {
        detail: text || "Unexpected server response."
    };
}

// ---------------------------------
// Submit expense
// ---------------------------------

form.addEventListener("submit", async function(event) {

    event.preventDefault();

    if (!paymentSourceId.value) {

        showMessage(
            "Please select a payment source.",
            "error"
        );

        return;
    }

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
            categoryInput.value.trim() || null,

        payment_source_id:
            Number(paymentSourceId.value),

        notes:
            document.getElementById("notes").value.trim() || null
    };

    if (
        selectedPaymentType === "CREDIT_CARD" &&
        installmentCount.value
    ) {
        expense.installment_count =
            Number(installmentCount.value);
    }

    try {

        const response = await fetch("/app/expenses", {

            method: "POST",

            headers: {
                "Content-Type": "application/json"
            },

            body: JSON.stringify(expense)
        });

        const data = await parseResponse(response);

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

        paymentSourceId.value = "";

        paymentOptionsContainer
            .querySelectorAll(".payment-option")
            .forEach(option => option.classList.remove("selected"));

        selectedPaymentType = null;

        installmentCount.value = "";
            
        updateInstallmentVisibility();

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

async function initializeApp() {
    setToday();
    await loadPaymentSources();
    await loadCategories();
    await loadExpenses();
}

window.addEventListener("load", initializeApp);
// ---------------------------------
// Load payment sources
// ---------------------------------

async function loadPaymentSources() {

    try {

        const response = await fetch("/app/payment-sources");

        if (!response.ok) {

            const data = await parseResponse(response);

            throw new Error(
                data.detail || "Failed to load payment sources"
            );
        }

        const paymentSources = await parseResponse(response);

        paymentOptionsContainer.innerHTML = "";

        paymentSources.forEach(source => {

            const button = document.createElement("button");
            button.type = "button";
            button.className = "payment-option";
            button.dataset.value = source.payment_source_id;
            button.setAttribute("aria-pressed", "false")
            button.textContent = source.payment_name;

            button.addEventListener("click", () => {

                paymentSourceId.value = source.payment_source_id;

                selectedPaymentType = source.payment_type;
                updateInstallmentVisibility();

                paymentOptionsContainer
                    .querySelectorAll(".payment-option")
                    .forEach(option => {
                        option.classList.remove("selected");
                        option.setAttribute("aria-pressed", "false");
                    });

                button.classList.add("selected");
                button.setAttribute("aria-pressed", "true");

            });

            paymentOptionsContainer.appendChild(button);
        });

        if (paymentSources.length === 0) {
            paymentOptionsContainer.innerHTML =
                `<p class="empty">No payment sources are available.</p>`;
        }

    } catch (error) {

        paymentOptionsContainer.innerHTML =
            `<p class="empty">Unable to load payment sources.</p>`;

        console.error(error);
    }
}

// ---------------------------------
// Load categories
// ---------------------------------

async function loadCategories() {

    try {

        const response = await fetch("/app/categories");

        if (!response.ok) {

            const data = await parseResponse(response);

            throw new Error(
                data.detail || "Failed to load categories"
            );
        }

        const categories = await parseResponse(response);

        categoryOptions.innerHTML = "";

        categories.forEach(category => {

            const option = document.createElement("option");

            option.value = category.category_name;

            categoryOptions.appendChild(option);
        });

    } catch (error) {

        console.error(error);
    }
}