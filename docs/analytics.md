# Analytics Layer

## Overview

The analytics layer provides PostgreSQL datasets specifically intended for analytical and visualization workloads.

The platform separates the operational database tables from the datasets consumed by Apache Superset:

```text
PostgreSQL
│
├── Operational Tables
│   ├── transactions
│   ├── payment_sources
│   ├── credit_cards
│   ├── installment_plans
│   └── installment_schedule
│
├── Payment Semantic Layer
│   └── payment_obligations
│
└── Analytical Views
    ├── vw_transactions
    └── vw_monthly_payments
              │
              ▼
       Apache Superset
       (Reporting & Visualization)
```

The operational tables remain the underlying source of financial transaction data.

The payment semantic layer provides the current credit-card payment-level representation used by payment-oriented analytical logic.

Analytical views provide purpose-specific datasets for reporting and visualization without requiring Superset charts to query the raw transactional structures directly.

Apache Superset is the current reporting and visualization platform for the project.      

---

## Analytical Views

The current analytics layer contains two PostgreSQL views:

| View | Grain | Primary Purpose |
|---|---|---|
| `vw_transactions` | One row per transaction | Transaction-level reporting and visualization |
| `vw_monthly_payments` | One row per payment due date/payment-day grouping | Monthly credit-card payment analysis |

These views provide stable analytical interfaces for Apache Superset.

---

## `vw_transactions`

### Purpose

`vw_transactions` provides a transaction-level analytical dataset for visualization and reporting.

It is based on the `transactions` table and enriches each transaction with the human-readable payment source name from `payment_sources`.

The view allows Superset to work with transaction data while exposing `payment_name` directly, rather than requiring each visualization to resolve the payment-source relationship independently.

### Grain

**One row represents one transaction.**

The view preserves the transaction-level grain of the underlying `transactions` table.

### Dependencies

```text
transactions
      │
      │ payment_source_id
      ▼
payment_sources
      │
      ▼
vw_transactions
```

The view joins:

- `transactions`
- `payment_sources`

using `payment_source_id`.

### Output

The view exposes analytical fields derived from the transaction and payment-source data, including:

| Column | Source | Description |
|---|---|---|
| `expense_id` | `transactions` | Transaction identifier |
| `transaction_date` | `transactions` | Date of the transaction |
| `merchant` | `transactions` | Merchant associated with the transaction |
| `description` | `transactions` | Transaction description |
| `amount` | `transactions` | Transaction amount |
| `category` | `transactions` | Transaction category |
| `notes` | `transactions` | Additional transaction notes |
| `created_at` | `transactions` | Record creation timestamp |
| `payment_name` | `payment_sources` | Human-readable payment source name |

### Transformation Logic

The view performs a relational enrichment:

1. Reads transaction records from `transactions`.
2. Matches each transaction to its payment source using `payment_source_id`.
3. Exposes the corresponding `payment_name`.
4. Presents the resulting transaction-level dataset to the analytics layer.

The view does not replace or modify the underlying `transactions` table.

### Superset Usage

`vw_transactions` is the current analytical dataset used for transaction-level Superset visualizations, including:

- **KPI — Total Transactions**
- **Bar Chart — Categorical Transactions**
- **Table — Daily Expenses**
- **Line Chart — Daily Expenses**

---

## `payment_obligations`

### Purpose

`payment_obligations` provides the current **credit-card payment-level semantic layer** for the analytics model.

It represents payment obligations derived from credit-card transaction and installment information without changing the original spending transaction.

### Current Semantics

For a credit-card transaction without an installment plan, the view represents the transaction as a normal credit-card payment obligation.

For a credit-card transaction with an installment plan, the view represents the installment schedule as installment payment obligations.

An installment transaction does not additionally produce a normal full-amount payment obligation.

### Current Scope

The current `payment_obligations` view is credit-card-specific.

It does not currently provide payment obligations for non-credit-card payment sources.

Therefore it should not be interpreted as a universal payment-obligation layer for all payment types.

---

## `vw_monthly_payments`

### Purpose

`vw_monthly_payments` provides an aggregated credit-card payment-level analytical dataset for monthly payment reporting.

The view consumes the current `payment_obligations` semantic layer rather than independently recreating installment payment logic from the underlying transaction records.

### Analytical Flow

```text
transactions
      |
      v
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

`payment_obligations` provides the payment-level semantic representation.

`credit_cards` provides the applicable credit-card reference information used by the analytical view.

### Grain

**One row represents a payment due date and payment-day grouping.**

Multiple payment obligations may contribute to a single row when they share the same payment timing.

### Dependencies

The view depends on:

- `payment_obligations`
- `credit_cards`

The payment-obligation layer provides the payment amounts represented by the analytical dataset.

### Transformation Logic

The view performs the following conceptual steps:

1. Reads the payment obligations represented by `payment_obligations`.
2. Resolves the applicable credit-card reference information.
3. Groups payment obligations by payment timing.
4. Aggregates the payment amounts.
5. Counts the payment obligations represented by each group.
6. Produces the monthly payment analytical dataset.

The exact SQL implementation is maintained separately from this documentation. This document describes the analytical contract and transformation behavior rather than duplicating the implementation.

### Output

The view provides:

| Column | Description |
|---|---|
| `monthyear` | Formatted payment month/year representation |
| `year` | Payment year |
| `month` | Payment month |
| `payment_day` | Payment day associated with the payment group |
| `payment_due` | Payment due date |
| `total_payment` | Aggregated payment amount |
| `transaction_count` | Count represented by the payment group |

### Superset Usage

`vw_monthly_payments` is the analytical dataset used by:

- **Line Chart — Monthly Payments**

This visualization provides a monthly view of aggregated credit-card payment amounts.

---

## Superset Visualization Mapping

The following mapping documents which PostgreSQL analytical dataset powers each current Superset visualization.

| Visualization | Analytical Dataset | Grain |
|---|---|---|
| KPI — Total Transactions | `vw_transactions` | Transaction |
| Bar Chart — Used Payment Source | `vw_transactions` | Transaction |
| Pie Chart — Categorical Transactions | `vw_transactions` | Transaction |
| Table — Daily Expenses | `vw_transactions` | Transaction |
| Line Chart — Daily Expenses | `vw_transactions` | Transaction |
| Line Chart — Monthly Payments | `vw_monthly_payments` | Payment due date/payment-day grouping |

This mapping should be updated whenever a visualization changes its underlying dataset or a new analytical dataset is introduced.

---

## Reporting and Visualization Platform

Apache Superset is the current reporting and visualization platform for the Finance Data Platform.

Superset consumes PostgreSQL analytical datasets rather than querying the FastAPI application layer.

The current visualization datasets are:

- `vw_transactions` for transaction-level reporting and visualization
- `vw_monthly_payments` for monthly credit-card payment reporting

The current reporting and visualization flow is:

```text
PostgreSQL
     |
     +-- vw_transactions
     |
     +-- vw_monthly_payments
              |
              v
       Apache Superset
              |
              v
     Reporting & Visualization
```

Power BI is not part of the current reporting and visualization architecture.

This documentation reflects the current implementation and does not prevent a future architectural decision from introducing another reporting or visualization platform.

---

## Analytics Layer Design

The analytics layer follows a separation of responsibilities.

### Operational Tables

The core tables store the platform's underlying financial data and relationships:

- `transactions`
- `payment_sources`
- `credit_cards`
- `installment_plans`
- `installment_schedule`

These tables support the application's operational data requirements.

### Payment Semantic Layer

`payment_obligations` provides the current credit-card payment-level semantic representation.

It separates the concept of the original spending event from the payment obligations used for credit-card payment analysis.

### Analytical Views

Analytical views provide derived datasets for reporting and visualization:

- `vw_transactions` provides an enriched transaction-level dataset.
- `vw_monthly_payments` provides aggregated monthly credit-card payment information.

### Apache Superset

Apache Superset consumes the analytical views to provide reporting and visualization.

This separation keeps visualization-oriented transformations in PostgreSQL while allowing the operational tables to remain focused on storing the underlying financial data.

---

## Documentation and Implementation Source of Truth

This document describes the **analytical contract** of the views:

- purpose
- grain
- dependencies
- output fields
- transformation behavior
- downstream visualization usage

The authoritative implementation of each analytical view is maintained in the repository's database SQL implementation.

The SQL implementation should be treated as the source of truth for exact query logic.

This documentation should be updated when the implementation changes in a way that affects the documented contract, grain, dependencies, output, or downstream usage.

This document should not duplicate the complete SQL definition of the views.

---

## Maintenance Guidelines

When modifying an analytical view:

1. Confirm the intended change with the appropriate project owner.
2. Update the authoritative SQL implementation.
3. Review whether the view's grain, dependencies, output columns, or transformation behavior changed.
4. Update this document when the documented analytical contract changes.
5. Review affected Superset datasets and visualizations.
6. Verify that downstream visualizations still use the intended analytical dataset.
7. Ensure documentation and implementation remain consistent.

Changes to analytical views should be reviewed for downstream impact because Superset visualizations depend on their structure and semantics.

---

## Current Scope

The current analytics layer supports:

- transaction-level visualization through `vw_transactions`
- payment-source analysis
- category analysis
- daily expense reporting
- credit-card payment-level semantics through `payment_obligations`
- monthly credit-card payment analysis through `vw_monthly_payments`
- aggregation of payment amounts and payment-obligation counts
- Apache Superset reporting and visualization

The analytics layer does not implement:

- generalized interest or amortization calculations
- installment refunds or cancellation
- installment modification
- automatic historical conversion of existing transactions
- cash-flow forecasting
- universal payment obligations across all payment types