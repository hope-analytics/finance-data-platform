# System Architecture

## Overview

The Finance Data Platform separates financial transaction capture, application processing, persistent storage, payment-obligation processing, interpersonal settlement tracking, and analytics into distinct layers.

The architecture is designed so that transaction capture and application logic remain independent from analytical reporting and visualization.

PostgreSQL is the central source of truth for transaction data and database-controlled financial processing. Apache Superset is the current reporting and visualization platform.

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
  +-- Reference and Operational Tables
  |     |
  |     +-- people
  |     |
  |     +-- transactions
  |     |       +-- payment_source_id
  |     |       +-- owner_id
  |     |       +-- participant_ids
  |     |
  |     +-- payment_sources
  |     +-- credit_cards
  |     +-- installment_plans
  |     +-- installment_schedule
  |     +-- recurring_expenses
  |     +-- recurring_schedule
  |
  +-- Payment Semantic Layer
  |     +-- payment_obligations
  |
  +-- Interpersonal Settlement Layer
  |     +-- cash_settlements
  |     +-- cash_statements
  |
  +-- Analytical Views
        +-- vw_transactions
        +-- vw_payment_obligation_participants
        +-- vw_monthly_payments
                |
                v
        Apache Superset
        (Reporting & Visualization)
```

The diagram describes the logical architecture. It does not imply that every table is joined into every analytical view or that the cash settlement tables are currently exposed as Superset datasets.

## Data Flow

1. A user enters a financial transaction through the web application.
2. The frontend sends the transaction data to FastAPI as a JSON request.
3. FastAPI validates the submitted data using Pydantic models.
4. The application connects to PostgreSQL using environment-based database configuration.
5. The original transaction is stored in `transactions`.
6. The transaction references a record in `payment_sources` through `payment_source_id`.
7. Transaction ownership and explicit participant membership are represented through `owner_id` and `participant_ids`.
8. Credit-card-specific information is maintained separately in the `credit_cards` reference table.
9. When a credit-card transaction includes an installment request, FastAPI invokes the database-controlled `create_installment_plan()` function.
10. The database uses the authoritative transaction amount to create the corresponding `installment_plans` and `installment_schedule` records.
11. The `payment_obligations` layer represents the applicable payment obligations for single-payment credit-card transactions, installment transactions, and recurring-generated transactions.
12. Eligible cash and e-wallet transactions can produce interpersonal reimbursement allocations in `cash_settlements`, which are grouped into `cash_statements`.
13. PostgreSQL analytical views provide datasets for analytics and reporting.
14. Apache Superset connects to PostgreSQL and uses the analytical views for reporting and visualization.

The original transaction remains the source of truth for the spending event. Installment schedule records represent derived payment obligations rather than additional purchases. Cash settlement allocations track reimbursement between people and are also not additional spending transactions.

### Transaction Ownership and Participants

The `owner_id` identifies the person associated with the transaction as its owner/payer. The `participant_ids` array records explicit participant membership for that transaction.

Participant handling follows these rules:

- An empty participant array means the owner is the implicit participant and does not create a reimbursement allocation.
- When the owner is included in a non-empty participant list, the owner's own share is excluded from reimbursement allocation.
- When the owner is absent from a non-empty participant list, the owner is not automatically inserted into that list.
- A transaction with multiple non-owner beneficiaries can produce separate allocation rows for those beneficiaries.
- Participant-level allocation data must not be counted as additional original spending transactions.

The participant-level payment-obligation view supports analysis at payment-obligation × participant grain. It is distinct from the transaction-level view and from the interpersonal cash settlement tables.

### Recurring Expenses

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

The generated transactions use the scheduled `payment_date` as their `transaction_date` and are classified as `RECURRING` through `obligation_type`.

The recurring schedule maintains its relationship to the recurring definition through `recurring_id`. The current implementation does not maintain a persistent foreign-key relationship between `recurring_schedule` and generated transactions.

### Cash Payment and Interpersonal Settlement

The cash settlement flow handles eligible cash-based reimbursements separately from the payment-obligation semantic layer.

```text
transactions
(owner_id, participant_ids)
        |
        v
Eligibility:
CASH or E_WALLET source
and obligation_type = NORMAL
        |
        v
cash_settlements
(transaction × beneficiary allocation)
        |
        v
cash_statements
(owner × beneficiary × due date)
```

V1 behavior:

- Eligibility requires `payment_sources.payment_type` to be `CASH` or `E_WALLET` and `transactions.obligation_type` to be `NORMAL`.
- GCash is represented by an e-wallet payment source.
- `cash_settlements` stores transaction-level reimbursement allocations between the owner and each eligible non-owner beneficiary.
- The due date is the first Friday on or after the transaction date. Monday through Friday transactions use that week's Friday; Saturday and Sunday transactions use the following Friday.
- `cash_statements` groups settlement amounts by owner, beneficiary, and due date.
- Statement status is tracked as `PENDING` or `PAID`. Partial payments are not supported in V1.
- Cash settlement records are separate from `payment_obligations` and do not create additional spending transactions.

Automatic synchronization or reconciliation of existing settlement and statement records after upstream transaction or participant changes is deferred. The architecture must not be interpreted as guaranteeing that changes to an upstream transaction automatically refresh downstream cash settlement records.

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

PostgreSQL provides persistent storage, relational integrity, payment-obligation processing, recurring transaction generation, interpersonal settlement tracking, and analytical datasets for the platform.

The database separates the original spending event from derived installment and payment-obligation information, as well as from reimbursement allocations between people.

### Transactions

The `transactions` table stores the core financial transaction records, including:

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
- `owner_id`
- `participant_ids`

The transaction identifier is generated automatically using a PostgreSQL identity column.

Financial amounts use `NUMERIC(12,2)` to preserve decimal precision.

The original transaction remains the authoritative spending record. Creating an installment plan does not create additional spending transactions.

`obligation_type` is a system-derived classification used to distinguish the implemented transaction contexts:

- `NORMAL` — normal non-recurring transaction
- `SINGLE_PAYMENT` — credit-card transaction without installments
- `RECURRING` — transaction generated from a recurring expense
- `INSTALLMENT` — credit-card transaction associated with an installment plan

The value is derived by the application or database-controlled process as appropriate and is not a user-controlled frontend field.

`owner_id` identifies the transaction owner/payer. `participant_ids` stores the explicit participant membership associated with the transaction. These fields support participant allocation and interpersonal settlement processing.

### People

The `people` reference entity represents people who can be associated with transaction ownership, participant membership, and interpersonal settlement records.

The transaction's `owner_id` and `participant_ids` provide ownership and participant information used by downstream processing. The exact physical constraints and reference enforcement should be confirmed against the current database implementation.

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

For Cash Payment and Interpersonal Settlement V1, eligible payment types are `CASH` and `E_WALLET`, and the transaction must have `obligation_type = NORMAL`.

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

### Cash Settlements and Statements

The interpersonal settlement layer consists of `cash_settlements` and `cash_statements`.

`cash_settlements` records transaction-level reimbursement allocations between a transaction owner and eligible non-owner beneficiaries. A transaction with multiple non-owner beneficiaries can produce a separate settlement allocation for each beneficiary.

Allocation uses equal participant shares with two-decimal monetary precision. Any rounding residual is assigned deterministically to the final participant so that allocations reconcile to the relevant transaction amount.

`cash_statements` groups settlement allocations by owner, beneficiary, and due date. The statement identifies the beneficiary and tracks settlement status using `PENDING` or `PAID`. Partial payments are not supported in V1.

The due date is the first Friday on or after the transaction date:

- Monday through Friday: that week's Friday
- Saturday or Sunday: the following Friday

The cash settlement layer is limited to transactions whose payment source type is `CASH` or `E_WALLET` and whose `obligation_type` is `NORMAL`.

These records are not additional spending transactions and do not belong to the `payment_obligations` semantic layer.

Automatic synchronization of settlement and statement records after upstream transaction or participant updates is deferred. Until that behavior is implemented and validated, the system should not be assumed to automatically reconcile downstream records when their source data changes.

### Analytical Views

PostgreSQL provides analytical views used by Apache Superset.

- `vw_transactions` provides transaction-level data enriched with the human-readable `payment_name` from `payment_sources` and the system-derived `obligation_type`.
- `vw_payment_obligation_participants` provides participant-level allocation analysis at payment-obligation × participant grain.
- `vw_monthly_payments` provides aggregated payment-level data based on the current `payment_obligations` semantic layer.

`vw_monthly_payments` consumes resolved `payment_due` values from `payment_obligations`. It does not independently reconstruct payment timing from `credit_cards`.

`vw_payment_obligation_participants` is not a transaction-grain dataset. Joining it to transaction-level data can multiply rows when an obligation has multiple participants. Aggregations must account for the intended grain.

The analytical views do not imply that cash settlement tables are currently exposed as Superset datasets.

## Analytics Layer

Apache Superset serves as the current reporting and visualization layer.

Superset connects directly to PostgreSQL rather than to the web application. This separates operational transaction capture from analytical reporting and visualization.

The current analytical datasets are:

- `vw_transactions` for transaction-level reporting and visualization
- `vw_payment_obligation_participants` for participant-level allocation analysis associated with payment obligations
- `vw_monthly_payments` for payment-level reporting

The conceptual analytical flow for payment reporting is:

```text
transactions / installment schedules / recurring transactions
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

Participant-level payment-obligation analysis uses:

```text
payment_obligations
        +
participant allocation data
        |
        v
vw_payment_obligation_participants
```

Recurring-generated transactions participate in the existing analytical layer through `payment_obligations`, `vw_transactions`, and `vw_monthly_payments`.

Cash settlement tables are operational settlement records and should not be described as active Superset datasets unless a dataset or visualization is explicitly implemented.

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
- PostgreSQL: persistent data storage, relational integrity, installment processing, recurring schedule and transaction generation, payment-obligation semantics, cash settlement allocation and statement persistence, and analytical datasets
- Apache Superset: reporting and visualization

### Separation of Spending and Payment Obligations

The original transaction represents the spending event.

Installment plans and schedules represent the relationship and derived payment allocation associated with that spending event.

The payment-obligation layer represents the current payment obligations used for payment-level analysis, including single-payment credit-card, installment, and recurring obligations.

Cash settlements represent interpersonal reimbursement allocations and are not additional spending transactions or payment obligations.

This separation prevents installment payments and reimbursement allocations from being interpreted as separate purchases.

### Reference Data Separation

Reusable reference data is separated from transaction records.

Transactions store stable identifiers such as `payment_source_id`, while descriptive payment-source information is maintained in the `payment_sources` table.

Credit-card-specific attributes are maintained separately in `credit_cards`. People are represented through the `people` reference entity and associated with transactions and settlement records through ownership and participant data.

### Centralized Data

PostgreSQL acts as the central source of transaction data for both the application and analytics layer.

The database also acts as the authority for installment payment-date calculation, installment schedule generation, recurring schedule generation, recurring transaction materialization, and payment-obligation semantics.

### Analytical Separation

Analytical datasets are provided through PostgreSQL views rather than requiring Superset to reproduce operational business logic.

This allows the operational database model and the reporting layer to remain separated while maintaining a consistent analytical contract.

### Extensibility

The separation between transaction data, reference data, installment processing, recurring commitments, payment obligations, interpersonal settlement processing, application processing, and analytics provides a foundation for extending the platform with additional financial use cases.

### Portfolio Focus

The platform demonstrates how an application can capture structured business data, validate and persist it in a relational database, derive payment obligations from transactional data, manage interpersonal reimbursement allocations, and make purpose-specific datasets available for reporting and visualization.

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
