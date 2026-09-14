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
│   └── credit_cards
│
└── Analytical Views
    ├── vw_transactions
    └── vw_monthly_payments
              │
              ▼
       Apache Superset
```

The operational tables remain the underlying source of financial transaction data. Analytical views provide purpose-specific datasets for reporting and visualization without requiring Superset charts to query the raw transactional structures directly.

---

## Analytical Views

The current analytics layer contains two PostgreSQL views:

| View | Grain | Primary Purpose |
|---|---|---|
| `vw_transactions` | One row per transaction | Transaction-level reporting and visualization |
| `vw_monthly_payments` | One row per payment month/payment-day grouping | Monthly payment analysis |

These views are derived from the core PostgreSQL tables and are intended to provide stable analytical interfaces for Superset.

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

The view exposes the following analytical fields:

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

`vw_transactions` is the dataset used for transaction-level Superset visualizations, including:

- **KPI — Total Transactions**
- **Bar Chart — Used Payment Source**
- **Pie Chart — Categorical Transactions**
- **Table — Daily Expenses**
- **Line Chart — Daily Expenses**

---

## `vw_monthly_payments`

### Purpose

`vw_monthly_payments` provides a monthly payment-level analytical dataset for analyzing expected payment timing and aggregated payment amounts.

The view derives payment-month information from transaction data, payment-source information, and credit-card payment configuration.

### Grain

**One row represents a payment-month and payment-day grouping.**

Multiple transactions may contribute to a single row when they belong to the same calculated payment month and payment day.

### Dependencies

```text
transactions
      │
      ├──────────────┐
      │              │
      ▼              ▼
payment_sources   credit_cards
      │              │
      └──────┬───────┘
             ▼
   vw_monthly_payments
```

The view depends on:

- `transactions`
- `payment_sources`
- `credit_cards`

The relationships are used to determine the applicable payment schedule and aggregate transactions into monthly payment groups.

### Transformation Logic

The view performs the following conceptual steps:

1. Retrieves transaction records.
2. Resolves the associated payment source.
3. Resolves applicable credit-card payment configuration where relevant.
4. Determines the transaction's statement month based on the transaction date and configured statement day.
5. Determines the corresponding payment month based on the statement cutoff and payment schedule.
6. Groups transactions by calculated payment month and payment day.
7. Calculates the total payment amount and transaction count for each group.

The exact SQL implementation is maintained separately from this documentation. This document describes the analytical contract and transformation behavior rather than duplicating the implementation.

### Output

The view provides:

| Column | Description |
|---|---|
| `monthyear` | Formatted payment month/year representation |
| `year` | Payment year |
| `month` | Payment month |
| `payment_day` | Planned payment day associated with the payment group |
| `payment_due` | Calculated payment date |
| `total_payment` | Total transaction amount assigned to the payment group |
| `transaction_count` | Number of transactions assigned to the payment group |

### Superset Usage

`vw_monthly_payments` is used by the:

- **Line Chart — Monthly Payments**

This visualization provides a monthly view of aggregated payment amounts.

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
| Line Chart — Monthly Payments | `vw_monthly_payments` | Payment month/payment day |

This mapping should be updated whenever a visualization changes its underlying dataset or a new analytical dataset is introduced.

---

## Analytics Layer Design

The analytics layer follows a simple separation of responsibilities:

### Operational Tables

The core tables store the platform's underlying financial data and relationships:

- `transactions`
- `payment_sources`
- `credit_cards`

These tables support the application's operational data requirements.

### Analytical Views

Analytical views provide derived datasets for reporting and visualization:

- `vw_transactions` provides an enriched transaction-level dataset.
- `vw_monthly_payments` provides aggregated monthly payment information.

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

The authoritative implementation of each analytical view should be maintained in the repository's database SQL implementation.

The SQL implementation should be treated as the source of truth for exact query logic. This documentation should be updated when the implementation changes in a way that affects the documented contract, grain, dependencies, output, or downstream usage.

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
- monthly payment analysis through `vw_monthly_payments`
- aggregation of payment amounts and transaction counts

The analytics layer should not be interpreted as implementing functionality that is not represented by the underlying database implementation or documented project requirements.
