# Data Model

## Overview

The Finance Data Platform uses PostgreSQL to separate original transaction records, reusable payment-source reference data, credit-card-specific information, installment relationships, derived installment schedules, and payment-level analytical semantics.

The current data model consists of the following operational and semantic objects:

```text
payment_sources
      |
      +--------------------+
      |                    |
      v                    v
transactions         credit_cards
      |
      v
installment_plans
      |
      v
installment_schedule
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

`payment_obligations` provides the current credit-card payment-level semantic representation.

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

### Installment Plans → Installment Schedule

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

The original transaction remains the authoritative spending record.

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

`payment_obligations` is the current **credit-card payment-level semantic layer**.

The current implementation represents two cases.

### Normal Credit-Card Transaction

For a credit-card transaction without an installment plan:

```text
transactions
      |
      v
normal credit-card payment obligation
```

The payment obligation represents the full transaction amount.

### Installment Credit-Card Transaction

For a credit-card transaction with an installment plan:

```text
transactions
      |
      v
installment_schedule
      |
      v
installment payment obligations
```

The installment payment obligations represent the scheduled payment amounts.

The installment transaction does not additionally generate a normal full-amount credit-card payment obligation.

### Current Scope of `payment_obligations`

The current view is credit-card-specific.

It does not currently provide payment obligations for:

- cash;
- e-wallet;
- bank account;
- debit card;
- BNPL; or
- other non-credit-card payment sources.

Therefore, `payment_obligations` should not be interpreted as a universal payment-obligation model across all payment types.

## Analytical Views

PostgreSQL provides analytical views for reporting and visualization.

### `vw_transactions`

`vw_transactions` provides a transaction-level analytical dataset based on `transactions` joined with `payment_sources`.

- **Grain:** One row per transaction
- **Source tables:** `transactions`, `payment_sources`
- **Purpose:** Provides transaction records with the associated payment source name for analytical use
- **Output:** Transaction fields from `transactions` plus `payment_name` from `payment_sources`
- **Usage:** Current transaction-level analytical dataset for Apache Superset

### `vw_monthly_payments`

`vw_monthly_payments` provides an aggregated credit-card payment-level analytical dataset based on the current payment-obligation semantic layer.

Conceptually:

```text
payment_obligations
        |
        v
credit_cards
        |
        v
vw_monthly_payments
        |
        v
Apache Superset
```

- **Grain:** One row per payment due date and payment-day grouping
- **Primary dependency:** `payment_obligations`
- **Additional reference:** `credit_cards`
- **Purpose:** Provides monthly credit-card payment totals and obligation counts for reporting
- **Transformation:** Aggregates the payment obligations represented by the semantic layer by payment timing
- **Usage:** Current monthly payment analytical dataset for Apache Superset

The analytical views provide reporting-oriented representations without replacing the underlying operational records.

## Referential Integrity

The database enforces referential integrity through foreign-key relationships.

- `transactions.payment_source_id` references `payment_sources.payment_source_id`.
- `credit_cards.payment_source_id` references `payment_sources.payment_source_id`.
- `installment_plans.expense_id` references `transactions.expense_id`.
- `installment_schedule.plan_id` references `installment_plans.plan_id`.

Unique constraints also prevent multiple installment plans from being associated with the same transaction and prevent duplicate installment numbers within the same plan.

## Design Decisions

### Separate Payment Sources from Transactions

Payment-source information is stored separately from transactions to avoid repeating reference values and to allow payment-source metadata to be maintained independently.

### Separate Credit Card Information

Credit-card-specific attributes are stored separately from general payment-source information because not all payment sources are credit cards.

### Preserve Transaction-Level Records

The `transactions` table remains the operational source of the spending event.

Installment schedules and payment obligations are derived representations of how that spending event is paid and must not be interpreted as additional purchases.

### Separate Installment Relationships from Spending Records

Installment information is represented through `installment_plans` and `installment_schedule` rather than adding installment-specific identity fields to the original transaction.

This preserves the original transaction as the single spending record.

### Payment-Obligation Semantic Layer

The current `payment_obligations` view provides a credit-card payment-level semantic representation.

It allows normal credit-card payment obligations and installment payment obligations to be represented through a common analytical concept without changing the original transaction record.

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
- Credit-card payment-obligation semantics
- Transaction-level analytical reporting through `vw_transactions`
- Monthly credit-card payment reporting through `vw_monthly_payments`
- Apache Superset as the current reporting and visualization platform

The current V1 implementation does not implement:

- Generalized interest or amortization calculations
- Installment refunds or cancellation
- Installment modification
- Automatic historical conversion of existing transactions
- Cash-flow forecasting
- Universal payment obligations across all payment types