# Technical Decisions

This document records the key technical decisions made while building the Finance Data Platform and the reasoning behind them.

## 1. FastAPI for the Application Layer

### Decision

Use FastAPI as the backend application framework.

### Reason

FastAPI provides the application layer between the web interface and PostgreSQL. It handles request processing, validation, authentication, and transaction operations while keeping database access separate from the frontend.

Pydantic models are used to validate transaction input before it is written to the database.

## 2. PostgreSQL for Persistent Storage

### Decision

Use PostgreSQL as the central database for financial transaction data.

### Reason

The platform requires structured, persistent storage for transaction records. PostgreSQL provides a relational data model that fits the current transaction-based design and supports SQL-based analytical access.

## 3. Apache Superset for Analytics

### Decision

Use Apache Superset as the current reporting and visualization layer.

### Reason

Superset connects directly to the PostgreSQL data source and consumes purpose-specific analytical views.

The current analytical datasets are:

- `vw_transactions` for transaction-level reporting and visualization
- `vw_monthly_payments` for monthly credit-card payment reporting

This keeps analytical reporting separate from the transaction-entry application while allowing the same centralized PostgreSQL data to be used for analysis and visualization.

## 4. Layered Architecture

### Decision

Separate the platform into frontend, application, database, and analytics layers.

### Reason

Each layer has a distinct responsibility:

- Frontend: user interaction and transaction entry
- FastAPI: application logic, validation, and authentication
- PostgreSQL: persistent transaction storage and database processing
- Apache Superset: analytics, reporting, and visualization

This separation makes the system easier to understand and maintain.

## 5. Environment-Based Configuration

### Decision

Store credentials and other sensitive configuration in environment variables.

### Reason

Database credentials, API tokens, and application credentials should not be embedded directly in source code.

The application reads configuration such as:

- `DB_HOST`
- `DB_PORT`
- `DB_NAME`
- `DB_USER`
- `DB_PASSWORD`
- `API_TOKEN`
- `APP_USERNAME`
- `APP_PASSWORD`

The actual `.env` file is excluded from version control.

## 6. Parameterized SQL

### Decision

Use parameterized SQL statements when inserting transaction data.

### Reason

Transaction values are passed separately from the SQL statement rather than being constructed directly into SQL strings. This provides a safer pattern for handling user-supplied data.

## 7. NUMERIC for Financial Amounts

### Decision

Store transaction amounts using `NUMERIC(12,2)`.

### Reason

Financial values require fixed decimal precision. `NUMERIC(12,2)` provides two decimal places for transaction amounts without relying on floating-point representation.

## 8. PostgreSQL Identity Column for Transaction IDs

### Decision

Use a PostgreSQL identity column for `expense_id`.

### Reason

The database generates unique transaction identifiers automatically. This keeps identifier generation within the database rather than requiring the application to calculate IDs.

## 9. Self-Hosted Deployment

### Decision

Run the platform using locally hosted services.

### Reason

The current project is designed as a self-hosted financial data platform. PostgreSQL runs locally, the FastAPI application provides the transaction interface, and Apache Superset provides analytics and visualization.

Keeping the components locally hosted gives the project a controlled development environment and demonstrates how the application, database, and analytics layers can operate together.

## 10. Keep the Initial Data Model Simple

### Decision

Use a single `transactions` table as the source of the original spending event.

### Reason

The current platform focuses on capturing and analyzing financial transactions. The original transaction remains the central spending entity.

Additional financial concepts such as installment relationships and payment obligations are represented through separate database objects rather than creating additional spending transactions.

This allows the original transaction to remain the source of truth while supporting derived payment-level analysis.

## 11. Separate Spending Events from Installment Payment Obligations

### Decision

Keep the original transaction separate from installment plans, installment schedules, and payment obligations.

### Reason

A credit-card installment purchase remains one spending event even though it produces multiple future payment obligations.

The data model therefore separates:

- `transactions` for the original spending event;
- `installment_plans` for the installment relationship;
- `installment_schedule` for derived installment payment allocations; and
- `payment_obligations` for the current credit-card payment-level semantic representation.

This prevents installment payments from being interpreted as separate purchases and preserves transaction-level reporting integrity.

## 12. Centralize Installment Payment-Due Calculation

### Decision

Use the PostgreSQL `calculate_payment_due()` function as the reusable authority for the first installment payment-due calculation.

### Reason

Payment-date calculation is part of the database-controlled installment process.

Centralizing the calculation prevents the application from independently reproducing payment-date logic and provides a single implementation point for the current V1 rules.

Subsequent installment dates are generated by the controlled installment creation process.

The function is not intended to represent a generalized credit-card statement or contractual due-date engine.

## 13. Controlled Database Installment Creation

### Decision

Use the PostgreSQL `create_installment_plan()` function as the controlled mechanism for installment creation.

### Reason

Installment creation requires coordinated database operations involving the original transaction, installment plan, installment schedule, payment-date calculation, allocation, and reconciliation.

The database-controlled function is responsible for:

- validating installment requirements;
- locating and locking the source transaction;
- using the authoritative transaction amount;
- validating credit-card eligibility;
- resolving the applicable credit-card configuration;
- preventing duplicate installment plans;
- creating the installment plan;
- generating the installment schedule;
- reconciling the schedule to the original amount; and
- validating the generated installment count.

FastAPI invokes this operation but does not independently calculate installment amounts or payment dates.

The original transaction creation and installment creation occur within the same database transaction so that a failure during installment creation causes the transaction to be rolled back.