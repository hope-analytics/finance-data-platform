# Data Model

## Overview

The Finance Data Platform uses PostgreSQL to separate transaction records from reusable payment-source reference data and credit-card-specific information.

The current data model consists of three core tables:

```text
payment_sources
      |
      +--------------------+
      |                    |
      v                    v
transactions         credit_cards
```

`transactions` stores individual financial transactions.

`payment_sources` stores reusable payment-source reference values.

`credit_cards` stores credit-card-specific reference information.

PostgreSQL also provides analytical views used by the analytics layer and Apache Superset for transaction-level and payment-level reporting.

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

### payment_sources

The `payment_sources` table stores reusable payment-source reference values.

| Column | Type | Description |
|---|---|---|
| `payment_source_id` | BIGINT | Unique identifier for the payment source |
| `payment_name` | VARCHAR(100) | Name of the payment source |
| `payment_type` | VARCHAR(50) | Type of payment source |
| `is_active` | BOOLEAN | Indicates whether the payment source is active |

Supported payment types and reference values are maintained in this table.

### credit_cards

The `credit_cards` table stores credit-card-specific reference information.

| Column | Type | Description |
|---|---|---|
| `credit_card_id` | BIGINT | Unique identifier for the credit card |
| `payment_source_id` | BIGINT | References the associated payment source |
| `card_name` | VARCHAR(100) | Name or identifier for the credit card |
| `statement_day` | INTEGER | Day of the month used as the statement cutoff |
| `payment_day` | INTEGER | Planned payment day for the credit card |

### Analytical Views

The PostgreSQL analytical layer provides views for reporting and visualization. These views do not replace the core tables; they provide reporting-oriented representations of the underlying transaction data.

#### `vw_transactions`

`vw_transactions` provides a transaction-level analytical dataset based on `transactions` joined with `payment_sources`.

- **Grain:** One row per transaction
- **Source tables:** `transactions`, `payment_sources`
- **Purpose:** Provides transaction records with the associated payment source name for analytical use
- **Output:** Transaction fields from `transactions` plus `payment_name` from `payment_sources`
- **Usage:** Used by Apache Superset for transaction-level visualizations

#### `vw_monthly_payments`

`vw_monthly_payments` provides an aggregated payment-level analytical dataset based on transaction, payment-source, and credit-card data.

- **Grain:** One row per payment month and payment day
- **Source tables:** `transactions`, `payment_sources`, `credit_cards`
- **Purpose:** Provides monthly payment totals and transaction counts for reporting
- **Transformation:** Determines the statement month from the transaction date and credit-card statement day, then derives the corresponding payment month
- **Output:** Payment month, year, month, payment day, payment due date, total payment, and transaction count
- **Usage:** Used by Apache Superset for monthly payment reporting

The analytical views are maintained separately from the core table definitions and are intended to provide stable datasets for the analytics layer.

## Referential Integrity

The database enforces referential integrity between the core tables through foreign-key relationships.

- `transactions.payment_source_id` references `payment_sources.payment_source_id`.
- `credit_cards.payment_source_id` references `payment_sources.payment_source_id`.

These relationships ensure that transaction and credit-card records reference valid payment-source records.

## Design Decisions

### Separate Payment Sources from Transactions

Payment-source information is stored separately from transactions to avoid repeating reference values and to allow payment-source metadata to be maintained independently.

### Separate Credit Card Information

Credit-card-specific attributes are stored separately from general payment-source information because not all payment sources are credit cards.

### Preserve Transaction-Level Records

The `transactions` table remains the operational source of transaction records. Analytical views provide reporting-oriented representations without replacing the underlying transaction data.

### Analytical Views for Reporting

Analytical views are used to provide stable, purpose-specific datasets for reporting and visualization while keeping analytical transformations separate from the operational transaction table.

## Current Scope

The current data model supports:

- Financial transaction capture
- Payment-source reference data
- Credit-card reference data
- Transaction-to-payment-source relationships
- Credit-card-to-payment-source relationships
- Planned payment-day information
- Transaction-level analytical reporting through `vw_transactions`
- Monthly payment reporting through `vw_monthly_payments`

The current data model does not currently implement:

- Credit-card statement records
- Automated contractual due-date calculations
- Cash-flow forecasting
- Installment schedules
- Automated payment allocation
