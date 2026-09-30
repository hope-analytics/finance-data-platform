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
  |     |
  |     +-- recurring_expenses
  |     |
  |     +-- recurring_schedule
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
10. The `payment_obligations` layer represents the applicable payment obligations for single-payment credit-card transactions, installment transactions, and recurring-generated transactions.
11. PostgreSQL analytical views provide datasets for analytics and reporting.
12. Apache Superset connects to PostgreSQL and uses the analytical views for reporting and visualization.

The original transaction remains the source of truth for the spending event. Installment schedule records represent derived payment obligations rather than additional purchases.

The platform also supports bounded recurring commitments:

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
recurring_schedule              future-dated transactions
                                      |
                                      v
                              obligation_type = RECURRING
                                      |
                                      v
                              payment_obligations
```

Creating a recurring expense causes the database-controlled recurring process to generate its bounded schedule and immediately materialize the corresponding future-dated transaction records.

The generated transactions use the scheduled `payment_date` as their `transaction_date` and are classified as:

```text
obligation_type = RECURRING
```

The recurring schedule maintains its relationship to the recurring definition through `recurring_id`. The current implementation does not maintain a persistent foreign-key relationship between `recurring_schedule` and generated transactions.

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

Recurring expenses are currently created through the database-controlled recurring process rather than through a dedicated recurring-expense CRUD API in the application.

The application excludes `RECURRING` transactions from its normal recent-expense display. The generated recurring records remain in the canonical `transactions` table.

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
- `obligation_type`

The transaction identifier is generated automatically using a PostgreSQL identity column.

Financial amounts use `NUMERIC(12,2)` to preserve decimal precision.

The original transaction remains the authoritative spending record. Creating an installment plan does not create additional spending transactions.

`obligation_type` is a system-derived classification used to distinguish the implemented transaction contexts:

- `NORMAL` — normal non-recurring transaction
- `SINGLE_PAYMENT` — credit-card transaction without installments
- `RECURRING` — transaction generated from a recurring expense
- `INSTALLMENT` — credit-card transaction associated with an installment plan

The value is derived by the application or database-controlled process as appropriate and is not a user-controlled frontend field.

### Recurring Expenses

Recurring expenses represent predefined recurring financial commitments.

The recurring-expense model separates the definition of a recurring commitment from the future-dated financial transactions generated by that commitment.

The implemented flow is:

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

`recurring_expenses` stores the definition of the recurring commitment.

`recurring_schedule` stores the scheduled occurrences associated with that recurring definition. Each schedule occurrence retains its `recurring_id` so that the scheduled event remains traceable to its originating recurring expense.

The database-controlled recurring process materializes the generated occurrences into `transactions` immediately after the recurring expense is created. The generated transaction uses the scheduled `payment_date` as its `transaction_date`.

The resulting transaction remains part of the canonical transaction domain. Recurring expenses therefore do not introduce a separate transaction table.

The current implementation does not maintain a persistent foreign-key relationship between `recurring_schedule` and generated transactions. The schedule-to-definition relationship is maintained through `recurring_id`; there is no transaction FK on `recurring_schedule`.

The recurring model is bounded by a contract period represented by a start date and an end date.

Automatic renewal is not part of the approved architecture.

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

`payment_obligations` is the current payment-obligation semantic layer.

Its current implementation represents:

- a normal credit-card payment obligation for a non-installment credit-card transaction;
- installment payment obligations for a credit-card transaction with an installment plan; or
- recurring payment obligations for transactions generated from recurring expenses.

An installment transaction does not additionally produce a normal full-amount credit-card payment obligation.

The current `payment_obligations` implementation does not provide payment obligations for non-credit-card payment sources.

This semantic layer separates the original spending event from the payment obligations used for payment-level analysis.

### Analytical Views

PostgreSQL provides analytical views used by Apache Superset.

- `vw_transactions` provides transaction-level data enriched with the human-readable `payment_name` from `payment_sources` and the system-derived `obligation_type`.
- `vw_monthly_payments` provides aggregated payment-level data based on the current `payment_obligations` semantic layer.

`vw_monthly_payments` consumes resolved `payment_due` values from `payment_obligations`. It does not independently reconstruct payment timing from `credit_cards`.

## Analytics Layer

Apache Superset serves as the current reporting and visualization layer.

Superset connects directly to PostgreSQL rather than to the web application. This separates operational transaction capture from analytical reporting and visualization.

The current analytical datasets are:

- `vw_transactions` for transaction-level reporting and visualization
- `vw_monthly_payments` for payment-level reporting

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

Recurring-generated transactions participate in the existing analytical layer through `payment_obligations`, `vw_transactions`, and `vw_monthly_payments`.

A dedicated recurring-expense analytical view or dedicated recurring Superset dashboard is not currently part of the implementation.

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
- PostgreSQL: persistent data storage, relational integrity, installment processing, recurring schedule and transaction generation, payment-obligation semantics, and analytical datasets
- Apache Superset: reporting and visualization

### Separation of Spending and Payment Obligations

The original transaction represents the spending event.

Installment plans and schedules represent the relationship and derived payment allocation associated with that spending event.

The payment-obligation layer represents the current payment obligations used for payment-level analysis, including single-payment credit-card, installment, and recurring obligations.

This prevents installment payments from being interpreted as separate purchases.

### Reference Data Separation

Reusable reference data is separated from transaction records.

Transactions store stable identifiers such as `payment_source_id`, while descriptive payment-source information is maintained in the `payment_sources` table.

Credit-card-specific attributes are maintained separately in `credit_cards`.

### Centralized Data

PostgreSQL acts as the central source of transaction data for both the application and analytics layer.

The database also acts as the authority for installment payment-date calculation, installment schedule generation, recurring schedule generation, recurring transaction materialization, and payment-obligation semantics.

### Analytical Separation

Analytical datasets are provided through PostgreSQL views rather than requiring Superset to reproduce operational business logic.

This allows the operational database model and the reporting layer to remain separated while maintaining a consistent analytical contract.

### Extensibility

The separation between transaction data, reference data, installment processing, recurring commitments, payment obligations, application processing, and analytics provides a foundation for extending the platform with additional financial use cases.

### Portfolio Focus

The platform demonstrates how an application can capture structured business data, validate and persist it in a relational database, derive payment obligations from transactional data, and make purpose-specific datasets available for reporting and visualization.

### Recurring Commitment Separation

Recurring commitments are separated from actual financial events at the definition level.

`recurring_expenses` defines the recurring commitment, while `recurring_schedule` represents its scheduled occurrences. The database-controlled recurring process materializes the generated occurrences into the canonical `transactions` domain immediately after the recurring definition is created.

This allows future-dated recurring activity to exist in the canonical transaction domain while keeping the recurring definition and schedule as the source of the recurring commitment.

The current physical model maintains schedule-to-definition lineage through `recurring_schedule.recurring_id`. It does not maintain a persistent foreign-key relationship from `recurring_schedule` to generated transactions.

Recurring expenses and installments remain separate mechanisms:

```text
Recurring:
recurring_expenses
        ↓
recurring_schedule
        ↓
future-dated transactions
        ↓
payment_obligations

Installment:
transactions
        ↓
installment_plans
        ↓
installment_schedule
        ↓
payment_obligations
```

A recurring expense is a predefined recurring commitment that generates future-dated transaction occurrences.

An installment originates from an actual transaction and distributes its payment across future installment occurrences.

The two mechanisms therefore share the canonical transaction domain without representing the same business concept.
