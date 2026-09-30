# Data Model

## Overview

The Finance Data Platform uses PostgreSQL to separate original transaction records, reusable payment-source reference data, credit-card-specific information, installment relationships, recurring commitments, derived schedules, and payment-level analytical semantics.

The current data model consists of the following operational and semantic objects:

```text
payment_sources
      |
      +--------------------+
      |                    |
      v                    v
transactions         credit_cards
      |                    |
      |                    |
      +----+---------------+
           |
      +----+------------------+
      |                       |
      v                       v
installment_plans      recurring_expenses
      |                       |
      v                       v
installment_schedule  recurring_schedule
      |                       |
      +-----------+-----------+
                  |
                  v
         payment_obligations
                  |
                  v
         vw_monthly_payments
```

`transactions` stores individual financial transactions and remains the source of truth for the spending event.

`payment_sources` stores reusable payment-source reference values.

`credit_cards` stores credit-card-specific reference information.

`installment_plans` associates an original transaction with an installment arrangement.

`installment_schedule` stores the derived installment payment allocations.

`recurring_expenses` stores bounded recurring financial commitments.

`recurring_schedule` stores scheduled occurrences generated from recurring definitions.

`payment_obligations` provides the current payment-obligation semantic representation for single-payment, installment, and recurring-generated transactions.

PostgreSQL also provides analytical views used by Apache Superset for transaction-level and payment-level reporting.

## Entity Relationships

### Payment Sources → Transactions

Each transaction references a payment source through `payment_source_id`.

```text
payment_sources
      |
      | 1
      |
      | N
      v
transactions
```

A payment source can therefore be associated with multiple transactions.

### Payment Sources → Credit Cards

Each credit card references a payment source through `payment_source_id`.

```text
payment_sources
      |
      | 1
      |
      | N
      v
credit_cards
```

A payment source can therefore be associated with multiple credit-card records.

### Transactions → Installment Plans

A transaction can have zero or one installment plan.

```text
transactions
      |
      | 1
      |
      | 0..1
      v
installment_plans
```

The original transaction remains unchanged as the spending record.

## Recurring Expenses

Recurring expenses represent bounded recurring financial commitments that generate scheduled occurrences and future-dated transaction records.

The implemented recurring-expense model consists of two database objects:

- `recurring_expenses` — the recurring commitment definition
- `recurring_schedule` — the scheduled occurrences generated from that definition

The database-controlled generation flow is:

```text
recurring_expenses
      |
      v
AFTER INSERT trigger
      |
      +-----------------------------+
      |                             |
      v                             v
generate_recurring_schedule()  generate_recurring_transactions()
      |                             |
      v                             v
recurring_schedule              transactions
                                    |
                                    v
                            obligation_type = RECURRING
```

Creating a recurring expense immediately generates its bounded schedule and materializes the corresponding future-dated transaction records.

### recurring_expenses

`recurring_expenses` represents the recurring financial commitment.

The implemented physical model includes:

| Column | Type | Description |
|---|---|---|
| `recurring_id` | BIGINT | Unique identifier for the recurring commitment |
| `merchant` | VARCHAR | Merchant or recurring payment source |
| `description` | TEXT | Recurring expense description |
| `amount` | NUMERIC(12,2) | Recurring amount |
| `category` | VARCHAR | Recurring transaction category |
| `payment_source_id` | BIGINT | References the payment source |
| `contract_start_date` | DATE | Start of the recurring commitment |
| `contract_end_date` | DATE | End of the recurring commitment |
| `status` | VARCHAR | Recurring commitment status |
| `created_at` | TIMESTAMP | Record creation timestamp |

Implemented status values are:

- `ACTIVE`
- `COMPLETED`
- `CANCELLED`

The database enforces the recurring amount, contract-period, status, and payment-source relationships defined by the physical schema.

The recurring definition does not require an `obligation_type` because every record in this domain represents a recurring commitment by definition.

Automatic renewal is not part of the current implementation.

### recurring_schedule

`recurring_schedule` represents the scheduled occurrences associated with a recurring expense.

The implemented physical model includes:

| Column | Type | Description |
|---|---|---|
| `schedule_id` | BIGINT | Unique identifier for the schedule row |
| `recurring_id` | BIGINT | References the recurring commitment |
| `occurrence_number` | SMALLINT | Sequential occurrence number |
| `payment_date` | DATE | Scheduled payment date |
| `created_at` | TIMESTAMP | Record creation timestamp |

Implemented constraints include:

- `recurring_id` references `recurring_expenses.recurring_id`.
- `occurrence_number` must be at least 1.
- `(recurring_id, occurrence_number)` is unique.

The schedule maintains lineage to the recurring definition through `recurring_id`.

The current implementation does **not** include:

- an `expense_id` column;
- a transaction foreign key; or
- a persistent schedule-to-generated-transaction relationship.

The schedule therefore represents the generated recurring occurrences, while the generated transaction records exist separately in the canonical `transactions` table.

### Recurring Schedule to Transaction

The database-controlled recurring process generates transactions from the schedule immediately after the recurring definition is created.

```text
recurring_schedule
        |
        | generation relationship
        v
future-dated transactions
```

The generated transaction uses the schedule's `payment_date` as its `transaction_date` and is classified as:

```text
obligation_type = RECURRING
```

The transaction does not require a `recurring_id`.

The schedule retains lineage to the recurring definition through `recurring_id`, but there is no persistent foreign-key relationship from `recurring_schedule` to the generated transaction.

The current implementation therefore does not support recurring correction or deletion through schedule-to-transaction lineage.

## Installment Plans → Installment Schedule

Each installment plan can have multiple installment schedule records.

```text
installment_plans
      |
      | 1
      |
      | N
      v
installment_schedule
```

Each schedule row represents one derived installment payment obligation.

Installment schedule rows are not separate spending transactions.

## Tables

### transactions

The `transactions` table stores individual financial transactions.

| Column | Type | Description |
|---|---|---|
| `expense_id` | BIGINT | Unique identifier for the transaction |
| `transaction_date` | DATE | Date the transaction occurred |
| `merchant` | VARCHAR(255) | Merchant or transaction source |
| `description` | TEXT | Transaction description |
| `amount` | NUMERIC(12,2) | Transaction amount |
| `category` | VARCHAR(100) | Transaction category |
| `payment_source_id` | BIGINT | References the payment source used |
| `notes` | TEXT | Optional transaction notes |
| `created_at` | TIMESTAMP | Record creation timestamp |
| `obligation_type` | VARCHAR | System-derived transaction obligation classification |

The `transactions` table remains the canonical source of truth for financial transaction records.

Transactions may originate from different financial contexts, including:

- normal non-recurring transactions;
- recurring expense occurrences;
- credit-card single payments; and
- credit-card installment transactions.

The implemented transaction classification model uses `obligation_type` to describe the transaction's payment behavior:

| Transaction scenario | `obligation_type` |
|---|---|
| Normal non-recurring transaction | `NORMAL` |
| Recurring transaction | `RECURRING` |
| Credit-card transaction without installment | `SINGLE_PAYMENT` |
| Credit-card transaction with installment | `INSTALLMENT` |

`obligation_type` is system-derived and is not a user-controlled frontend field.

`obligation_type` does not replace `payment_source_id`.

For example, a recurring expense paid using a credit card remains associated with its credit-card payment source while being classified as `RECURRING`.

The physical database implementation constrains `obligation_type` to the supported values above and requires a non-null value.

### payment_sources

The `payment_sources` table stores reusable payment-source reference values.

| Column | Type | Description |
|---|---|---|
| `payment_source_id` | BIGINT | Unique identifier for the payment source |
| `payment_name` | VARCHAR(100) | Name of the payment source |
| `payment_type` | VARCHAR(50) | Type of payment source |
| `active` | BOOLEAN | Indicates whether the payment source is active |

Transactions reference payment sources through `payment_source_id`.

Only active payment sources can be assigned to new transactions.

### credit_cards

The `credit_cards` table stores credit-card-specific reference information.

| Column | Type | Description |
|---|---|---|
| `credit_card_id` | BIGINT | Unique identifier for the credit card |
| `payment_source_id` | BIGINT | References the associated payment source |
| `card_name` | VARCHAR(100) | Name or identifier for the credit card |
| `statement_day` | SMALLINT | Day used as the statement cutoff |
| `payment_day` | SMALLINT | Configured payment day |

The current implementation constrains the configured payment day according to the V1 credit-card payment-cycle rules.

### installment_plans

The `installment_plans` table represents the relationship between an original transaction and its installment plan.

| Column | Type | Description |
|---|---|---|
| `plan_id` | BIGINT | Unique identifier for the installment plan |
| `expense_id` | BIGINT | References the original transaction |
| `original_amount` | NUMERIC(12,2) | Authoritative amount associated with the original transaction |
| `installment_count` | SMALLINT | Number of installments |
| `created_at` | TIMESTAMP | Record creation timestamp |

Constraints include:

- `expense_id` references `transactions.expense_id`.
- Each transaction can have at most one installment plan.
- `original_amount` must be greater than zero.
- `installment_count` must be at least 2.

The installment plan does not create a replacement transaction.

### installment_schedule

The `installment_schedule` table stores the derived payment allocation for an installment plan.

| Column | Type | Description |
|---|---|---|
| `schedule_id` | BIGINT | Unique identifier for the schedule row |
| `plan_id` | BIGINT | References the installment plan |
| `installment_number` | SMALLINT | Sequential installment number |
| `amount` | NUMERIC(12,2) | Allocated installment amount |
| `payment_due` | DATE | Payment due date for the installment |
| `created_at` | TIMESTAMP | Record creation timestamp |

Constraints include:

- `plan_id` references `installment_plans.plan_id`.
- `installment_number` must be at least 1.
- `amount` must be greater than zero.
- Each installment number is unique within an installment plan.

The installment schedule represents derived payment obligations and does not represent separate spending events.

## Payment-Due Logic

The database function `calculate_payment_due()` is the reusable authority for calculating the first installment payment due date.

The function uses:

- transaction date;
- statement day; and
- configured payment day.

The controlled installment creation process uses the function for the first installment and advances subsequent installments by one calendar month from the previous payment date.

FastAPI does not independently calculate installment payment dates.

The V1 implementation does not provide a generalized credit-card statement engine or contractual due-date system.

## Payment Obligations

`payment_obligations` is the current payment-obligation semantic layer.

The current implementation represents three cases.

### Single-Payment Credit-Card Transaction

For a credit-card transaction without an installment plan:

```text
transactions
      |
      v
payment_obligations
```

The payment obligation represents the resolved payment amount and due date for the single-payment credit-card transaction.

### Installment Credit-Card Transaction

For a credit-card transaction with an installment plan:

```text
transactions
      |
      v
installment_schedule
      |
      v
payment_obligations
```

The installment payment obligations represent the scheduled payment amounts.

The installment transaction does not additionally generate a normal full-amount credit-card payment obligation.

### Recurring Transaction

For a transaction generated from a recurring expense:

```text
recurring_expenses
      |
      v
recurring_schedule
      |
      v
future-dated transactions
      |
      v
payment_obligations
```

The recurring-generated transaction is classified as `RECURRING`, and its resolved payment obligation is represented in the payment-obligation layer.

### Current Scope of `payment_obligations`

The current implementation supports:

- `SINGLE_PAYMENT`
- `INSTALLMENT`
- `RECURRING`

It does not currently provide payment obligations for non-credit-card payment sources such as cash, e-wallet, bank account, debit card, or other non-credit-card types.

Therefore, `payment_obligations` should not be interpreted as a universal payment-obligation model across all payment types.

## Analytical Views

PostgreSQL provides analytical views for reporting and visualization.

### `vw_transactions`

`vw_transactions` provides a transaction-level analytical dataset based on `transactions` joined with `payment_sources`.

- **Grain:** One row per transaction
- **Source tables:** `transactions`, `payment_sources`
- **Purpose:** Provides transaction records with the associated payment source name and transaction obligation classification for analytical use
- **Output:** Transaction fields from `transactions` plus `payment_name` from `payment_sources` and `obligation_type`
- **Usage:** Current transaction-level analytical dataset for Apache Superset

### `vw_monthly_payments`

`vw_monthly_payments` provides an aggregated payment-level analytical dataset based on the current `payment_obligations` semantic layer.

Conceptually:

```text
payment_obligations
        |
        v
vw_monthly_payments
        |
        v
Apache Superset
```

- **Grain:** One row per payment due date and payment-day grouping
- **Primary dependency:** `payment_obligations`
- **Purpose:** Provides payment totals and obligation counts for reporting
- **Transformation:** Aggregates resolved payment obligations using `payment_due`; `payment_day` is derived from `payment_due`
- **Usage:** Current payment analytical dataset for Apache Superset

`vw_monthly_payments` does not reconstruct payment timing from `credit_cards`. The resolved `payment_due` in `payment_obligations` is authoritative for the analytical view.

The analytical views provide reporting-oriented representations without replacing the underlying operational records.

## Referential Integrity

The database enforces referential integrity through foreign-key relationships.

- `transactions.payment_source_id` references `payment_sources.payment_source_id`.
- `credit_cards.payment_source_id` references `payment_sources.payment_source_id`.
- `installment_plans.expense_id` references `transactions.expense_id`.
- `installment_schedule.plan_id` references `installment_plans.plan_id`.
- `recurring_schedule.recurring_id` references `recurring_expenses.recurring_id`.

The current recurring model intentionally does **not** include a foreign-key relationship from `recurring_schedule` to `transactions`.

Unique constraints also prevent multiple installment plans from being associated with the same transaction, prevent duplicate installment numbers within the same plan, and prevent duplicate recurring occurrence numbers within the same recurring commitment.

## Design Decisions

### Separate Payment Sources from Transactions

Payment-source information is stored separately from transactions to avoid repeating reference values and to allow payment-source metadata to be maintained independently.

### Separate Credit Card Information

Credit-card-specific attributes are stored separately from general payment-source information because not all payment sources are credit cards.

### Preserve Transaction-Level Records

The `transactions` table remains the operational source of the spending event.

Installment schedules, recurring-generated transaction records, and payment obligations are derived representations of financial processing and must not be interpreted as additional purchases beyond the transaction records they represent.

### Separate Installment Relationships from Spending Records

Installment information is represented through `installment_plans` and `installment_schedule` rather than adding installment-specific identity fields to the original transaction.

This preserves the original transaction as the single spending record.

### Recurring Commitment Model

Recurring commitments are represented through `recurring_expenses` and `recurring_schedule`.

The database-controlled recurring process immediately materializes future-dated transaction records when a recurring expense is created. The generated records remain in the canonical `transactions` table and are classified as `RECURRING`.

The recurring schedule maintains lineage to the recurring definition through `recurring_id`. A persistent schedule-to-generated-transaction foreign key is not part of the current model.

### Payment-Obligation Semantic Layer

The current `payment_obligations` layer provides a common payment-level representation for the implemented single-payment, installment, and recurring contexts.

### Analytical Views for Reporting

Analytical views are used to provide stable, purpose-specific datasets for reporting and visualization while keeping analytical transformations separate from the operational transaction tables.

## Current Scope

The current data model supports:

- Financial transaction capture
- Payment-source reference data
- Credit-card reference data
- Transaction-to-payment-source relationships
- Credit-card-to-payment-source relationships
- Credit-card installment plans
- Derived installment schedules
- Bounded recurring financial commitments
- Recurring schedules and future-dated recurring transactions
- System-derived transaction obligation classification
- Payment-obligation semantics for single-payment, installment, and recurring transactions
- Transaction-level analytical reporting through `vw_transactions`
- Payment-level reporting through `vw_monthly_payments`
- Apache Superset as the current reporting and visualization platform

The current V1 implementation does not implement:

- Generalized interest or amortization calculations
- Installment refunds or cancellation
- Installment modification
- Automatic historical conversion of existing transactions
- Cash-flow forecasting
- Universal payment obligations across all payment types
- Persistent schedule-to-generated-transaction lineage for recurring correction or deletion
