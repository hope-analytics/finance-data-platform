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

Use Apache Superset as the reporting and visualization layer.

### Reason

Superset connects to PostgreSQL and consumes purpose-specific analytical views. The current documented analytical views include:

- `vw_transactions` for transaction-level reporting and visualization
- `vw_monthly_payments` for monthly payment reporting
- `vw_payment_obligation_participants` for participant-level analysis of payment obligations

The participant view has a payment-obligation × participant grain. Joining it to other datasets without accounting for that grain can multiply rows and inflate aggregates.

This keeps analytical reporting separate from the transaction-entry application while allowing the same centralized PostgreSQL data to support analysis and visualization.

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

Use `NUMERIC(12,2)` for financial amounts.

### Reason

Financial values require fixed decimal precision. `NUMERIC(12,2)` provides two decimal places without relying on floating-point representation.

This precision is used for transaction amounts and the related installment and cash-settlement amounts documented in the current model.

## 8. PostgreSQL Identity Column for Transaction IDs

### Decision

Use a PostgreSQL identity column for `expense_id`.

### Reason

The database generates unique transaction identifiers automatically. This keeps identifier generation within the database rather than requiring the application to calculate IDs.

## 9. Self-Hosted Deployment

### Decision

Run the platform using locally hosted services.

### Reason

The current project is designed as a self-hosted financial data platform. PostgreSQL stores the data, FastAPI provides the application interface, and Apache Superset provides analytics and visualization.

Keeping the components self-hosted gives the project a controlled operating environment and demonstrates how the application, database, and analytics layers can work together.

## 10. Keep the Initial Data Model Simple

### Decision

Use a single `transactions` table as the source of the original spending event.

### Reason

The platform focuses on capturing and analyzing financial transactions. The original transaction remains the central spending entity.

Additional financial concepts such as installment relationships, recurring commitments, payment obligations, and interpersonal reimbursements are represented through separate database objects rather than being recorded as additional spending transactions.

This keeps the original spending event distinct from derived payment and settlement records.

For recurring expenses, the current V1 implementation materializes scheduled occurrences as future-dated records in `transactions`. These records are identifiable through `obligation_type = 'RECURRING'`.

## 11. Separate Spending Events from Installment Payment Obligations

### Decision

Keep the original transaction separate from installment plans, installment schedules, and payment obligations.

### Reason

A credit-card installment purchase remains one spending event even though it produces multiple future payment obligations.

The data model separates:

- `transactions` for the original spending event
- `installment_plans` for the installment relationship
- `installment_schedule` for derived installment payment allocations
- `payment_obligations` for the payment-obligation representation

This prevents installment payments from being interpreted as separate purchases and preserves transaction-level reporting integrity.

## 12. Centralize Installment Payment-Due Calculation

### Decision

Use the PostgreSQL `calculate_payment_due()` function as the reusable authority for calculating the first installment payment-due date.

### Reason

Payment-date calculation is part of the database-controlled installment process. Centralizing the calculation prevents the application from independently reproducing payment-date logic and provides a single implementation point for the current V1 rules.

Subsequent installment dates advance one calendar month from the previous installment's due date. V1 does not introduce month-end clamping or rollover behavior.

The function is not intended to represent a generalized credit-card statement or contractual due-date engine. In particular, `credit_cards.payment_day` is a planned payment/cash-flow marker, not a bank's contractual payment due date.

## 13. Controlled Database Installment Creation

### Decision

Use the PostgreSQL `create_installment_plan()` function as the controlled mechanism for installment creation.

### Reason

Installment creation requires coordinated database operations involving the original transaction, installment plan, installment schedule, payment-date calculation, allocation, and reconciliation.

The database-controlled function is responsible for the installment creation process, including eligibility checks, schedule generation, amount allocation, and reconciliation with the original transaction amount.

FastAPI invokes this operation but does not independently calculate installment amounts or payment dates.

The original transaction creation and installment creation occur within the same database transaction so that a failure during installment creation causes the transaction to be rolled back.

The current V1 feature is limited to credit-card transactions with 0% interest. It does not implement an interest or amortization engine, statement integration, early settlement, or refund processing. Installment schedule rows are not separate spending transactions, and an installment count must be at least two.

## 14. Keep Recurring Commitments Separate from Transactions

### Decision

Represent recurring financial commitments through a recurring-expense definition and recurring schedule rather than a separate recurring transaction table.

### Reason

`recurring_expenses` represents the recurring commitment definition, while `recurring_schedule` represents its scheduled occurrences. The canonical `transactions` table remains the transaction domain.

In the current V1 implementation, recurring occurrences are materialized after a recurring expense is inserted. A database `AFTER INSERT` trigger invokes the schedule-generation and transaction-generation functions.

The generated transactions use the scheduled payment date as their `transaction_date` and are classified as `RECURRING`. The implemented behavior is immediate creation of future-dated transaction records rather than waiting until each payment date to create a transaction.

## 15. Use a Recurring Schedule for Future Visibility

### Decision

Maintain a recurring schedule containing future occurrences associated with the recurring expense definition.

### Reason

Future recurring expenses should be visible through scheduled payment dates before those dates occur.

The recurring schedule contains `recurring_id` so each scheduled occurrence can be associated with its originating recurring definition. The current physical model does not maintain a permanent foreign-key relationship from `recurring_schedule` to the generated `transactions` rows. The schedule therefore provides recurring-definition association, but it should not be interpreted as a transaction-lineage table.

Recurring commitments are bounded by a contract start date and contract end date. Automatic renewal is not part of the current V1 architecture.

Future correction, deletion, or reconciliation of generated recurring transactions would require an explicit lineage design; the current model does not infer that relationship by matching merchant, amount, date, or other transaction attributes.

## 16. Classify Transaction Payment Behavior Through `obligation_type`

### Decision

Use `obligation_type` to classify the payment behavior of transaction records.

### Reason

The classification allows the transaction domain to distinguish payment behaviors without creating separate transaction structures.

The implemented classifications are:

- `NORMAL` — normal non-recurring transaction
- `RECURRING` — transaction materialized from a recurring schedule
- `SINGLE_PAYMENT` — credit-card transaction without an installment plan and without recurring classification
- `INSTALLMENT` — credit-card transaction associated with an installment plan

`obligation_type` does not replace `payment_source_id`. It is system-determined rather than a user-entered field, preventing clients from arbitrarily assigning payment behavior to transactions.

The `payment_obligations` layer uses these classifications as part of the broader payment-obligation model, including single-payment, installment, and recurring obligations.

## 17. Use Database-Controlled Recurring Materialization

### Decision

Use PostgreSQL functions and an `AFTER INSERT` trigger to generate recurring schedules and materialize recurring transactions.

### Reason

The recurring-expense creation process requires coordinated generation of scheduled occurrences and corresponding future-dated transaction records.

The database-controlled process inserts the recurring definition, generates its schedule, creates corresponding future-dated transactions, and assigns `obligation_type = 'RECURRING'`. Those transactions can then participate in the existing payment-obligation and analytical layers.

This keeps recurring generation within the database and prevents the application from independently reproducing recurring schedule and materialization logic.

The current application does not expose a dedicated recurring-expense CRUD API. Recurring-expense creation and schedule generation are database-controlled.

## 18. Reuse Existing Transaction and Payment-Obligation Analytics for Recurring Data

### Decision

Use the existing transaction and payment-obligation analytical structures for recurring-generated data rather than introducing a dedicated recurring analytical view in V1.

### Reason

Recurring-generated transactions can participate in `vw_transactions`, `payment_obligations`, and `vw_monthly_payments`.

Because recurring-generated transactions are future-dated, downstream analytics must distinguish future scheduled records from realized spending through the current date whenever the reporting question requires that distinction.

A dedicated recurring analytical view or recurring-specific Superset dashboard is outside the current V1 scope.

## 19. Separate Transaction Ownership from Participant Membership

### Decision

Represent transaction ownership and participant membership as separate concepts.

### Reason

`transactions.owner_id` identifies the transaction owner or payer. `transactions.participant_ids` records explicit participant membership, while `people` provides the reference entity for people.

The owner and the participants answer different questions: who paid for the transaction, and who participated in or benefited from it. They should not be treated as interchangeable.

Participant allocation follows the recorded membership rather than automatically inserting the owner into every participant list:

- An empty participant array means the owner is the implicit participant and no reimbursement allocation is generated.
- If the owner appears in a non-empty participant list, the owner's own share is excluded from reimbursement.
- If the owner is absent from a non-empty participant list, the owner is not automatically added.
- Each eligible non-owner beneficiary receives a separate allocation.

The current API documentation identifies a gap: the transaction creation request does not yet accept `owner_id` or `participant_ids`. The database model and participant analysis should not be taken to mean those fields are already supported by the application request contract.

## 20. Keep Cash Settlements Separate from Spending Transactions and Payment Obligations

### Decision

Represent interpersonal reimbursements using `cash_settlements` and aggregate them into `cash_statements`, separately from the original transaction and the existing `payment_obligations` layer.

### Reason

A cash or e-wallet purchase can create an amount owed by a beneficiary to the transaction owner. That reimbursement is a settlement relationship, not another spending event.

For the current Cash Payment & Interpersonal Settlement V1, eligibility is limited to transactions where:

- `payment_sources.payment_type` is `CASH` or `E_WALLET`; and
- `transactions.obligation_type` is `NORMAL`.

GCash is represented through an e-wallet payment source. Credit-card transactions, installment obligations, and recurring transactions are not included in this cash-settlement flow.

`cash_settlements` records individual transaction-to-beneficiary allocations. `cash_statements` groups amounts by owner, beneficiary, and due date so that the beneficiary remains identifiable at statement level.

Cash settlements do not create additional spending transactions and are not part of `payment_obligations`. The existing payment-obligation layer remains focused on single-payment credit-card, installment, and recurring obligations.

## 21. Use a Deterministic Friday Due Date for Cash Settlements

### Decision

Set a cash settlement's due date to the first Friday on or after the transaction date.

### Reason

The V1 rule provides a consistent, predictable date for interpersonal cash and e-wallet reimbursements:

- A transaction dated Monday through Friday is due that same week's Friday.
- A transaction dated Saturday or Sunday is due the following Friday.

This is an application-specific settlement rule, not a bank payment-due calculation. The rule is distinct from `calculate_payment_due()`, which supports installment payment-date calculation.

## 22. Keep Cash Statement Payment Status Simple in V1

### Decision

Use `PENDING` and `PAID` as cash statement statuses and do not support partial payments in V1.

### Reason

The current settlement workflow treats each statement as either outstanding or paid. The model includes payment status and timestamps such as `paid_at`, `created_at`, and `updated_at`.

Partial payment allocation and more complex settlement reconciliation are outside the current V1 scope.

## 23. Defer Automatic Settlement and Statement Synchronization

### Decision

Do not assume that changes to upstream transactions or participants automatically reconcile existing cash settlements and statements.

### Reason

The intended dependency is that transaction or participant changes may affect settlement allocations and the resulting statement totals. Automatic downstream synchronization, reconciliation, and associated trigger changes have been explicitly deferred.

Until that work is implemented and verified, existing `cash_settlements` and `cash_statements` records should not be documented as automatically updating after upstream changes.

## 24. Keep Participant Analytics at an Explicit Grain

### Decision

Use `vw_payment_obligation_participants` for analysis at the payment-obligation × participant grain.

### Reason

The view makes participant-level payment-obligation analysis available without treating each participant allocation as a separate spending transaction.

Because one obligation can be associated with multiple participants, the view may contain multiple rows for one obligation. Aggregations that require one row per obligation must account for this grain to avoid double-counting amounts.

The view is an analytical representation; it does not create new spending transactions or replace the underlying transaction and payment-obligation records.

## 25. Use a Simple Category-Bridge Convention

### Decision

Use the category name as the transaction's category value and represent an unmatched category reference with a `NULL` category identifier.

### Reason

The desired category-standardization convention keeps the entered category label visible while allowing reference-data matching to be assessed separately. If a category is not present in the category reference table, its `category_id` should be `NULL` rather than forcing a match or silently creating a reference record.

A bridged/unbridged semantic view, `vw_transaction_category_status`, is the intended way to expose category matching status for analysis. Do not treat this decision statement alone as confirmation that every related schema change or view is present in the checked-in schema file.

## 26. Do Not Treat the Checked-In Schema as a Complete Record of Every Live Change

### Decision

Verify the live database and implementation before relying on `database/schema.sql` as the complete physical schema specification.

### Reason

The checked-in schema file has lagged behind parts of the evolving model, including ownership, participant, cash-settlement, and participant-analytics changes. Documentation should distinguish confirmed design decisions from physical details that have not been verified against the current database definition.

When a physical column type, constraint, foreign key, or view definition is uncertain, it should be verified before being documented as implemented. This prevents stale DDL from being treated as authoritative evidence of the live model.
