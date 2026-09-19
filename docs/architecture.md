# System Architecture

## Overview

The Finance Data Platform separates financial transaction capture, application processing, persistent storage, payment-obligation processing, and analytics into distinct layers.

The architecture is designed so that transaction capture and application logic remain independent from analytical reporting and visualization.

Apache Superset is the current reporting and visualization platform for the project.

## Architecture

```text
User
  |
  v
Web Application
(HTML / CSS / JavaScript)
  |
  | JSON
  v
FastAPI
  |
  +-- Authentication
  +-- Request Validation
  +-- Transaction API
  |
  v
PostgreSQL
  |
  +-- Operational Tables
  |     |
  |     +-- transactions
  |     |       |
  |     |       +-- payment_source_id
  |     |                |
  |     |                v
  |     |         payment_sources
  |     |
  |     +-- credit_cards
  |     |
  |     +-- installment_plans
  |     |
  |     +-- installment_schedule
  |
  +-- Payment Semantic Layer
  |     |
  |     +-- payment_obligations
  |
  +-- Analytical Views
        |
        +-- vw_transactions
        |
        +-- vw_monthly_payments
                |
                v
        Apache Superset
        (Reporting & Visualization)
```

## Data Flow

1. A user enters a financial transaction through the web application.
2. The frontend sends the transaction data to the FastAPI application as a JSON request.
3. FastAPI validates the submitted data using Pydantic models.
4. The application connects to PostgreSQL using environment-based database configuration.
5. The original transaction is stored in the `transactions` table.
6. Each transaction references a record in `payment_sources` through `payment_source_id`.
7. Credit-card-specific information is maintained separately in the `credit_cards` reference table.
8. When a credit-card transaction includes an installment request, FastAPI invokes the database-controlled `create_installment_plan()` function.
9. The database uses the authoritative transaction amount to create the corresponding `installment_plans` and `installment_schedule` records.
10. The `payment_obligations` view provides the current credit-card payment-level semantic representation, distinguishing normal credit-card obligations from installment obligations.
11. PostgreSQL analytical views provide datasets for analytics and reporting.
12. Apache Superset connects to PostgreSQL and uses the analytical views for reporting and visualization.

The original transaction remains the source of truth for the spending event. Installment schedule records represent derived payment obligations rather than additional purchases.

## Application Layer

The application layer consists of a browser-based interface and a FastAPI backend.

### Web Application

The frontend provides:

- Transaction entry
- Payment source selection
- Category and description fields
- Installment selection for eligible credit-card transactions
- Recent transaction display
- Transaction refresh
- Success and error feedback

### FastAPI

FastAPI provides the backend API and application logic.

Responsibilities include:

- Receiving transaction requests
- Validating transaction fields
- Creating transactions
- Retrieving transactions
- Managing database connections
- Application authentication
- API token verification
- Invoking the database-controlled installment creation function when applicable
- Managing transaction commit and rollback behavior

The application accepts an optional `installment_count` for transaction creation.

FastAPI does not independently calculate installment amounts, installment payment dates, or payment-obligation aggregations. These responsibilities remain within the database implementation.

## Database Layer

PostgreSQL provides persistent storage, relational integrity, payment-obligation processing, and analytical datasets for the platform.

The database separates the original spending event from derived installment and payment-obligation information.

### Transactions

The `transactions` table stores the core financial transaction records:

- `expense_id`
- `transaction_date`
- `merchant`
- `description`
- `amount`
- `category`
- `payment_source_id`
- `notes`
- `created_at`

The transaction identifier is generated automatically using a PostgreSQL identity column.

Financial amounts use `NUMERIC(12,2)` to preserve decimal precision.

The original transaction remains the authoritative spending record. Creating an installment plan does not create additional spending transactions.

### Payment Sources

The `payment_sources` table stores reusable payment-source reference data, including:

- Payment source name
- Payment type
- Active status
- Creation timestamp

Transactions reference payment sources through `payment_source_id` rather than storing the payment-source name directly.

When transaction data is retrieved through the appropriate application query path, the payment-source reference can be joined to provide the user-visible `payment_name`.

### Credit Cards

The `credit_cards` table stores credit-card-specific reference information:

- Card name
- Statement day
- Planned payment day
- Active status
- Payment-source reference
- Creation timestamp

The `payment_day` represents the configured payment day used by the database payment-due logic.

Credit-card-specific payment timing is maintained separately from individual transaction records.

### Installment Plans

The `installment_plans` table represents the relationship between an original transaction and its installment plan.

An installment plan:

- references the original transaction through `expense_id`;
- stores the authoritative `original_amount`;
- stores the requested `installment_count`;
- allows one installment plan per transaction.

The installment plan does not replace the original transaction.

### Installment Schedule

The `installment_schedule` table stores the derived payment allocation for an installment plan.

Each schedule row represents one installment payment obligation and contains:

- the installment plan;
- installment number;
- allocated payment amount;
- payment due date.

The schedule uses `NUMERIC(12,2)` for monetary values. The database allocation logic ensures that the schedule reconciles exactly to the original transaction amount, with the final installment absorbing any rounding remainder.

Installment schedule rows represent payment obligations and are not separate purchases.

### Payment-Due Calculation

The database function `calculate_payment_due()` is the reusable authority for calculating the first installment payment due date.

The function uses the transaction date, configured statement day, and configured payment day to determine the applicable payment date.

Subsequent installment dates are generated by the controlled installment creation process.

FastAPI does not independently reproduce this payment-date calculation.

### Controlled Installment Creation

The database function `create_installment_plan()` is the controlled database mechanism for creating an installment plan.

The function is responsible for the implemented installment-creation behavior, including:

- validating installment requirements;
- locating and locking the source transaction;
- using the authoritative transaction amount;
- validating credit-card eligibility;
- resolving the applicable credit-card configuration;
- preventing duplicate installment plans;
- creating the installment plan;
- generating the installment schedule;
- reconciling the schedule to the original transaction amount; and
- validating that the generated schedule matches the requested installment count.

FastAPI supplies the request information and invokes the database-controlled operation.

The original transaction creation and installment-plan creation occur within the same database transaction. If installment creation fails, the transaction is rolled back.

### Payment Obligations

`payment_obligations` is the current **credit-card payment-level semantic layer**.

Its current implementation represents:

- a normal credit-card payment obligation for a non-installment credit-card transaction; or
- installment payment obligations for a credit-card transaction with an installment plan.

An installment transaction does not additionally produce a normal full-amount credit-card payment obligation.

The current `payment_obligations` view does not provide payment obligations for non-credit-card payment sources.

This semantic layer separates the original spending event from the payment obligations used for credit-card payment analysis.

### Analytical Views

PostgreSQL provides analytical views used by Apache Superset.

- `vw_transactions` provides transaction-level data enriched with the human-readable `payment_name` from `payment_sources`.
- `vw_monthly_payments` provides aggregated credit-card payment-level data based on the current `payment_obligations` semantic layer.

`vw_monthly_payments` consumes the payment-obligation representation rather than independently recreating installment or payment-obligation logic from the underlying transaction records.

## Analytics Layer

Apache Superset serves as the current reporting and visualization layer.

Superset connects directly to PostgreSQL rather than to the web application. This separates operational transaction capture from analytical reporting and visualization.

The current analytical datasets are:

- `vw_transactions` for transaction-level reporting and visualization
- `vw_monthly_payments` for monthly credit-card payment reporting

The conceptual analytical flow is:

```text
transactions
     |
     v
payment_obligations
     |
     v
vw_monthly_payments
     |
     v
Apache Superset
```

`vw_transactions` provides a separate transaction-level analytical dataset:

```text
transactions
     +
payment_sources
     |
     v
vw_transactions
     |
     v
Apache Superset
```

## Security

The application uses environment variables for sensitive configuration rather than hardcoding credentials in source code.

Configuration includes:

- Database credentials
- API token
- Application username
- Application password

The FastAPI application also implements:

- HTTP Basic authentication
- API bearer-token verification
- Security response headers

The actual environment file is excluded from the Git repository.

## Design Principles

### Separation of Responsibilities

Each layer has a defined responsibility:

- Frontend: user interaction and transaction capture
- FastAPI: application logic, validation, authentication, and database operation orchestration
- PostgreSQL: persistent data storage, relational integrity, installment processing, payment-obligation semantics, and analytical datasets
- Apache Superset: reporting and visualization

### Separation of Spending and Payment Obligations

The original transaction represents the spending event.

Installment plans and schedules represent the relationship and derived payment allocation associated with that spending event.

The payment-obligation layer represents the current credit-card payment obligations used for payment-level analysis.

This prevents installment payments from being interpreted as separate purchases.

### Reference Data Separation

Reusable reference data is separated from transaction records.

Transactions store stable identifiers such as `payment_source_id`, while descriptive payment-source information is maintained in the `payment_sources` table.

Credit-card-specific attributes are maintained separately in `credit_cards`.

### Centralized Data

PostgreSQL acts as the central source of transaction data for both the application and analytics layer.

The database also acts as the authority for installment payment-date calculation, installment schedule generation, and payment-obligation semantics.

### Analytical Separation

Analytical datasets are provided through PostgreSQL views rather than requiring Superset to reproduce operational business logic.

This allows the operational database model and the reporting layer to remain separated while maintaining a consistent analytical contract.

### Extensibility

The separation between transaction data, reference data, installment processing, payment obligations, application processing, and analytics provides a foundation for extending the platform with additional financial use cases.

### Portfolio Focus

The platform demonstrates how an application can capture structured business data, validate and persist it in a relational database, derive payment obligations from transactional data, and make purpose-specific datasets available for reporting and visualization.