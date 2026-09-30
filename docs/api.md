# API Documentation

## Overview

The Finance Data Platform exposes a FastAPI backend for transaction capture and retrieval.

The API accepts JSON requests from the web application and persists validated transaction data in PostgreSQL.

The transaction creation API also supports optional credit-card installment creation.

Recurring expenses are currently generated through the database-controlled recurring process rather than through a dedicated recurring-expense CRUD API.

## Base URL

When running locally:

```text
http://<TAIL_SCALE_IP>:8000
```

For LAN access from another device:

```text
http://<SERVER_IP>:8000
```

The application must be running and accessible on the network before using the LAN address.

## Endpoints

### Application Interface

#### `GET /app`

Returns the web application interface.

The route is protected using HTTP Basic authentication.

#### `GET /app/expenses`

Returns recent transaction records for display in the web application.

The response includes transaction details and the associated payment-source information, including `payment_name`.

Recurring-generated transactions are excluded from this normal recent-expense display. They remain stored in the canonical `transactions` table.

#### `POST /app/expenses`

Creates a new transaction from the web application.

The request is validated before the transaction is inserted into PostgreSQL.

The endpoint also supports optional installment creation for eligible credit-card transactions.

Example request:

```json
{
  "transaction_date": "2026-09-12",
  "merchant": "Example Store",
  "description": "Household supplies",
  "amount": 500.00,
  "category": "Household",
  "payment_source_id": 4,
  "notes": "Example transaction"
}
```

A credit-card transaction may optionally include:

```json
{
  "installment_count": 6
}
```

The `payment_source_id` must reference an active payment source.

## API Endpoints

### `GET /expenses`

Returns transaction records through the API.

The endpoint uses bearer-token verification.

The retrieval response includes transaction information and the associated payment-source information.

### `POST /expenses`

Creates a transaction through the API.

The endpoint uses bearer-token verification.

Example request:

```json
{
  "transaction_date": "2026-09-12",
  "merchant": "Example Store",
  "description": "Household supplies",
  "amount": 5000.00,
  "category": "Shopping",
  "payment_source_id": 4,
  "notes": "Example transaction",
  "installment_count": 6
}
```

`installment_count` is optional.

When provided:

- it must be at least `2`;
- the selected payment source must resolve to an eligible credit-card transaction;
- the database creates the installment plan and schedule;
- the original transaction remains the spending record.

## Request Validation

Transaction requests are validated using Pydantic models before database insertion.

Validation covers the expected transaction fields and data types.

The transaction amount is represented as a decimal value and stored in PostgreSQL using `NUMERIC(12,2)`.

The payment source is represented by `payment_source_id` rather than a free-text payment-source name.

The optional `installment_count` field must be an integer greater than or equal to `2` when supplied.

Credit-card eligibility and installment creation are controlled by the database implementation.

`obligation_type` is not accepted as a user-controlled request field.

## Payment Sources

Payment sources are maintained as reference data in PostgreSQL.

Current payment-source types include:

- `CASH`
- `E_WALLET`
- `BANK_ACCOUNT`
- `DEBIT_CARD`
- `CREDIT_CARD`
- `BNPL`
- `OTHER`

Transactions reference payment sources through:

```text
transactions.payment_source_id
        |
        v
payment_sources.payment_source_id
```

Only active payment sources can be assigned to new transactions.

## Response Data

### Transaction Creation Response

The POST transaction-creation response returns the inserted transaction fields.

When installment creation occurs, the response additionally includes `installment_plan_id`.

The POST creation response does not include `payment_name`.

Example:

```json
{
  "expense_id": 1,
  "transaction_date": "2026-09-12",
  "merchant": "Example Store",
  "description": "Household supplies",
  "amount": 5000.00,
  "category": "Shopping",
  "payment_source_id": 4,
  "notes": "Example transaction",
  "created_at": "2026-09-12T23:00:00",
  "installment_plan_id": 12
}
```

For a transaction without installments, `installment_plan_id` is not returned as an installment-plan identifier.

### Transaction Retrieval Response

Transaction retrieval endpoints provide transaction information together with the associated payment-source information.

The retrieval response can include `payment_name`.

Example:

```json
{
  "expense_id": 1,
  "transaction_date": "2026-09-12",
  "merchant": "Example Store",
  "description": "Household supplies",
  "amount": 5000.00,
  "category": "Shopping",
  "payment_source_id": 4,
  "payment_name": "Credit Card",
  "notes": "Example transaction",
  "created_at": "2026-09-12T23:00:00"
}
```

The creation and retrieval response contracts should therefore be treated separately.

## Recurring Transaction Behavior

Recurring transaction occurrences are system-generated through the database-controlled recurring process.

The frontend does not submit `obligation_type` as a user-controlled transaction attribute.

The implemented classification behavior is:

| Context | `obligation_type` |
|---|---|
| Normal non-recurring transaction | `NORMAL` |
| Credit-card transaction without installment | `SINGLE_PAYMENT` |
| Credit-card transaction with installment | `INSTALLMENT` |
| Recurring-generated transaction | `RECURRING` |

For normal transaction creation, the application derives the appropriate classification from the transaction context.

For recurring-generated transactions, the database recurring process assigns `RECURRING` during transaction materialization.

The recurring flow is:

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
```

Creating a recurring expense therefore causes the bounded schedule and its corresponding future-dated transaction records to be generated immediately through the database-controlled process. The scheduled `payment_date` is used as the generated transaction's `transaction_date`.

There is currently no dedicated recurring-expense CRUD endpoint in the FastAPI application.

Clients must not be permitted to arbitrarily assign an obligation type.

## Installment Creation Flow

When a transaction is submitted with an `installment_count`, the application follows this flow:

```text
Client
  |
  v
FastAPI
  |
  +-- Validate request
  |
  +-- Insert original transaction
  |
  +-- Call create_installment_plan()
  |
  v
PostgreSQL
  |
  +-- Validate installment requirements
  +-- Resolve credit-card eligibility
  +-- Read authoritative transaction amount
  +-- Resolve credit-card configuration
  +-- Create installment plan
  +-- Generate installment schedule
  +-- Reconcile schedule to original amount
  +-- Validate installment count
  |
  v
Return response
  |
  v
Commit
```

The original transaction and installment-plan creation occur within the same database transaction.

If installment creation fails, the transaction is rolled back.

FastAPI does not independently calculate:

- installment amounts;
- installment payment dates;
- schedule allocation;
- payment-obligation aggregation.

These responsibilities remain within the database implementation.

## Database Interaction

The FastAPI application connects to PostgreSQL using environment-based configuration.

The application does not expose PostgreSQL directly to clients.

For normal transactions, the workflow is:

```text
Client
  |
  v
FastAPI
  |
  +-- Validate request
  |
  +-- Validate payment_source_id
  |
  v
PostgreSQL
  |
  v
transactions
```

For installment transactions, the workflow extends to the database-controlled installment process:

```text
transactions
      |
      v
create_installment_plan()
      |
      +-- installment_plans
      |
      +-- installment_schedule
```

For recurring expenses, the current application boundary is different:

```text
recurring_expenses
      |
      v
PostgreSQL AFTER INSERT trigger
      |
      +-- generate_recurring_schedule()
      |
      +-- generate_recurring_transactions()
      |
      v
future-dated transactions
```

The database remains responsible for recurring schedule generation and recurring transaction materialization.

The generated recurring transactions remain in the canonical `transactions` table and participate in the downstream payment-obligation and analytical layers.

## Authentication

The application uses two authentication mechanisms for different API surfaces.

### HTTP Basic Authentication

HTTP Basic authentication protects the web application interface.

Credentials are configured through environment variables and are not stored in the source repository.

### Bearer Token Authentication

Bearer-token verification protects the API transaction endpoints.

The API token is configured through an environment variable.

Example request header:

```text
Authorization: Bearer <API_TOKEN>
```

Sensitive credentials and tokens must not be committed to Git.

## Error Handling

The API returns JSON responses for successful transaction operations.

Validation or application errors may return an HTTP error response.

Clients should check the HTTP status code before attempting to parse a successful response.

Typical status codes include:

| Status | Meaning |
|---:|---|
| `200` | Request completed successfully |
| `201` | Resource created successfully, where applicable |
| `400` | Invalid request |
| `401` | Authentication required or invalid credentials/token |
| `404` | Resource or route not found |
| `422` | Request validation failed |
| `500` | Internal application or database error |

When installment creation fails during transaction creation, the database transaction is rolled back.

## Security Considerations

The application follows these practices:

- Credentials are stored in environment variables.
- The `.env` file is excluded from Git.
- API access uses bearer-token verification.
- The web application uses HTTP Basic authentication.
- Database credentials are not hardcoded in application source code.
- PostgreSQL is accessed by the application rather than directly by browser clients.

## Current Scope

The API currently supports:

- Transaction creation
- Transaction retrieval
- Active payment-source validation
- Optional credit-card installment creation
- Database-controlled installment schedule generation
- Transactional rollback when installment creation fails
- System-derived transaction obligation classification
- Database-controlled recurring transaction materialization

The current recurring implementation does not expose dedicated FastAPI endpoints for:

- Creating recurring commitments
- Updating recurring commitments
- Deleting recurring commitments
- Manually managing recurring schedules

The current V1 API does not implement:

- Generalized interest or amortization calculations
- Installment refunds or cancellation
- Installment modification
- Automatic historical conversion of existing transactions
- Cash-flow forecasting
