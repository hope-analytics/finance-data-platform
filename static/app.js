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
const ownerSelect = document.getElementById("owner_id");
const participantsDropdown = document.getElementById("participantsDropdown");
const participantsDropdownButton = document.getElementById("participantsDropdownButton");
const participantsDropdownPanel = document.getElementById("participantsDropdownPanel");
const participantsDropdownLabel = document.getElementById("participantsDropdownLabel");
const participantChecklist = document.getElementById("participantChecklist");

let selectedPaymentType = null;

function updateInstallmentVisibility() {
    const isCreditCard = selectedPaymentType === "CREDIT_CARD";

    installmentGroup.hidden = !isCreditCard;
    installmentCount.disabled = !isCreditCard;

    if (!isCreditCard) {
        installmentCount.value = "";
    }
}

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

function updateParticipantsLabel() {
    const selected = participantChecklist.querySelectorAll(
        'input[name="participant_ids"]:checked'
    );

    if (selected.length === 0) {
        participantsDropdownLabel.textContent = "Select participants";
    } else if (selected.length === 1) {
        participantsDropdownLabel.textContent = "1 participant selected";
    } else {
        participantsDropdownLabel.textContent =
            `${selected.length} participants selected`;
    }
}

participantsDropdownButton.addEventListener("click", () => {
    const isOpen = !participantsDropdownPanel.hidden;

    participantsDropdownPanel.hidden = isOpen;
    participantsDropdownButton.setAttribute("aria-expanded", String(!isOpen));
});

document.addEventListener("click", (event) => {
    if (!participantsDropdown.contains(event.target)) {
        participantsDropdownPanel.hidden = true;
        participantsDropdownButton.setAttribute("aria-expanded", "false");
    }
});


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

async function loadPeople() {
    ownerSelect.disabled = true;
    participantsDropdownButton.disabled = true;

    try {
        const response = await fetch("/app/people");
        const data = await parseResponse(response);

        if (!response.ok) {
            throw new Error(
                data?.detail ||
                `People request failed (HTTP ${response.status}).`
            );
        }

        if (!Array.isArray(data)) {
            console.error("Expected an array of people, received:", data);
            throw new Error("The people API returned an unexpected response.");
        }

        ownerSelect.replaceChildren(
            new Option(
                data.length === 0
                    ? "No people available"
                    : "Select an owner",
                ""
            )
        );

        participantChecklist.replaceChildren();

        data.forEach((person) => {
            const ownerOption = new Option(
                person.name,
                String(person.person_id)
            );
            ownerSelect.add(ownerOption);

            const label = document.createElement("label");
            label.className = "participant-option";

            const checkbox = document.createElement("input");
            checkbox.type = "checkbox";
            checkbox.name = "participant_ids";
            checkbox.value = String(person.person_id);
            checkbox.addEventListener("change", updateParticipantsLabel);

            const name = document.createElement("span");
            name.textContent = person.name;

            label.append(checkbox, name);
            participantChecklist.appendChild(label);
        });

        updateParticipantsLabel();

        if (data.length === 0) {
            showMessage("No household members are available.", "error");
        }
    } catch (error) {
        ownerSelect.replaceChildren(
            new Option("Unable to load people", "")
        );
        participantChecklist.replaceChildren();
        updateParticipantsLabel();

        showMessage(error.message, "error");
        console.error("People loading failed:", error);
    } finally {
        ownerSelect.disabled = false;
        participantsDropdownButton.disabled = false;
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
            document.getElementById("notes").value.trim() || null,
    
        owner_id:
            Number(ownerSelect.value),

        participant_ids: Array.from(
            participantChecklist.querySelectorAll(
                'input[name="participant_ids"]:checked'
            )
        ).map((checkbox) => Number(checkbox.value))

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

        participantChecklist
            .querySelectorAll('input[name="participant_ids"]')
            .forEach((checkbox) => {
                checkbox.checked = false;
            });

        updateParticipantsLabel();

        participantsDropdownPanel.hidden = true;
        participantsDropdownButton.setAttribute("aria-expanded", "false");

        // Put today's date back
        
        setToday();

        // Reset Payment Source state.

        paymentSourceId.value = "";
        selectedPaymentType = null;
        installmentCount.value = "";
        updateInstallmentVisibility();

        // Reset installment state.
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
    updateInstallmentVisibility();

    await Promise.allSettled([
        loadPaymentSources(),
        loadCategories(),
        loadPeople()
    ]);

    await loadExpenses();
}

window.addEventListener("load", initializeApp);
// ---------------------------------
// Load payment sources
// ---------------------------------


async function loadPaymentSources() {
    paymentSourceId.disabled = true;
    paymentSourceId.replaceChildren(
        new Option("Loading payment sources...", "")
    );

    try {
        const response = await fetch("/app/payment-sources");
        const data = await parseResponse(response);

        if (!response.ok) {
            throw new Error(
                data?.detail || "Failed to load payment sources."
            );
        }

        if (!Array.isArray(data)) {
            throw new Error("Unexpected payment sources response.");
        }

        paymentSourceId.replaceChildren(
            new Option(
                data.length
                    ? "Choose a payment source"
                    : "No payment sources available",
                ""
            )
        );

        data.forEach((source) => {
            const option = new Option(
                source.payment_name,
                String(source.payment_source_id)
            );

            option.dataset.paymentType = source.payment_type;
            paymentSourceId.add(option);
        });

        paymentSourceId.disabled = data.length === 0;
        selectedPaymentType = null;
        updateInstallmentVisibility();

    } catch (error) {
        console.error(error);

        paymentSourceId.replaceChildren(
            new Option("Unable to load payment sources", "")
        );
        paymentSourceId.disabled = true;

        showMessage(
            "Unable to load payment sources. Please refresh and try again.",
            "error"
        );
    }
}

paymentSourceId.addEventListener("change", () => {
    const selectedOption =
        paymentSourceId.options[paymentSourceId.selectedIndex];

    selectedPaymentType =
        selectedOption?.dataset.paymentType || null;

    updateInstallmentVisibility();
});

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