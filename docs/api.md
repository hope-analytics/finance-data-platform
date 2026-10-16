# API Documentation

## Overview

The Finance Data Platform exposes a FastAPI backend for transaction capture and retrieval.

The API accepts JSON requests from the web application and persists validated transaction data in PostgreSQL.

The transaction creation API also supports optional credit-card installment creation. The application derives `obligation_type` from the payment-source type and whether an installment count was supplied; clients do not set this field directly.

Recurring expenses are currently generated through the database-controlled recurring process rather than through a dedicated recurring-expense CRUD API.

Cash Payment and Interpersonal Settlement V1 is a database-backed settlement workflow. The current FastAPI application does not expose dedicated endpoints for creating, retrieving, updating, or reconciling `cash_settlements` or `cash_statements`.

## Base URL

When running locally, use the host and port where FastAPI is running. For example:

```text
http://<SERVER_IP>:8000
```

For LAN access from another device:

```text
http://<SERVER_IP>:8000
```

The application must be running and accessible on the network before using the LAN address. Use the appropriate host address for the actual deployment; do not expose the service publicly without configuring the intended network and security controls.

## Endpoints

### `GET /health`

Returns a simple health-check response.

Example response:

```json
{
  "status": "ok"
}
```

The current health-check route does not require the application's Basic or bearer-token authentication dependency.

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

The request uses the same `ExpenseCreate` validation model as `POST /expenses`. The endpoint also supports optional installment creation for eligible credit-card transactions.

#### `GET /app/payment-sources`

Returns active payment sources for use by the web application. The response includes the payment source identifier, display name, and payment type.

#### `GET /app/categories`

Returns the category reference records used by the web application, including their category identifiers and names.

### API Endpoints

#### `GET /expenses`

Returns recent transaction records through the API.

The endpoint uses bearer-token verification. The retrieval query joins `transactions` to `payment_sources` and returns the associated `payment_name`. Recurring-generated transactions are excluded from this recent-expense query.

#### `POST /expenses`

Creates a transaction through the API.

The endpoint uses bearer-token verification and returns HTTP `201 Created` when the transaction is successfully created.

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

- it must be an integer greater than or equal to `2`;
- the selected payment source must be an active credit-card payment source;
- the database creates the installment plan and schedule through `create_installment_plan()`;
- the original transaction remains the spending record;
- if installment creation fails, the transaction operation is rolled back.

The API rejects an invalid or inactive payment source with a `400 Bad Request` response.

## Request Model

The current `ExpenseCreate` Pydantic model accepts these fields:

| Field | Required | Validation / Meaning |
|---|---|---|
| `transaction_date` | Yes | Date of the transaction |
| `merchant` | Yes | String, 1–150 characters |
| `description` | No | Optional transaction description |
| `amount` | Yes | Decimal value greater than zero |
| `category` | No | Optional category text |
| `payment_source_id` | Yes | Identifier of the selected payment source |
| `notes` | No | Optional notes |
| `installment_count` | No | Optional integer; minimum value is `2` |

The API model currently does **not** accept `owner_id` or `participant_ids` as request fields. Although transaction ownership and participant membership exist in the broader data model, they are not currently part of the `ExpenseCreate` API contract shown by the implementation. Do not send these fields expecting the current API to persist them.

The API model also does not accept `obligation_type` as a user-controlled field. The application derives this classification from the payment-source type and installment request.

## Request Examples

### Normal Transaction

```json
{
  "transaction_date": "2026-09-12",
  "merchant": "Neighborhood Store",
  "description": "Household supplies",
  "amount": 500.00,
  "category": "Household",
  "payment_source_id": 2,
  "notes": "Example cash transaction"
}
```

The application derives `obligation_type = NORMAL` for a non-credit-card payment source when no installment count is supplied.

### Single-Payment Credit-Card Transaction

```json
{
  "transaction_date": "2026-09-12",
  "merchant": "Example Store",
  "description": "Household supplies",
  "amount": 5000.00,
  "category": "Shopping",
  "payment_source_id": 4,
  "notes": "Example credit-card transaction"
}
```

When the selected active payment source has `payment_type = CREDIT_CARD` and no installment count is supplied, the application derives `obligation_type = SINGLE_PAYMENT`.

### Installment Credit-Card Transaction

```json
{
  "transaction_date": "2026-09-12",
  "merchant": "Example Store",
  "description": "Appliance purchase",
  "amount": 12000.00,
  "category": "Appliances",
  "payment_source_id": 4,
  "notes": "Example installment transaction",
  "installment_count": 6
}
```

When the selected active payment source is a credit card and `installment_count` is supplied, the application derives `obligation_type = INSTALLMENT` and invokes the database-controlled installment creation function.

## Request Validation and Obligation Classification

Transaction requests are validated using the `ExpenseCreate` Pydantic model before database insertion.

Validation covers the expected transaction fields and data types.

The transaction amount is represented as a decimal value and stored in PostgreSQL using `NUMERIC(12,2)`.

The payment source is represented by `payment_source_id` rather than a free-text payment-source name.

The optional `installment_count` field must be an integer greater than or equal to `2` when supplied.

The application inserts the transaction by selecting the requested payment source from `payment_sources` and requiring `active = TRUE`. It derives `obligation_type` as follows:

| Condition | Derived `obligation_type` |
|---|---|
| `payment_type = CREDIT_CARD` and `installment_count` is supplied | `INSTALLMENT` |
| `payment_type = CREDIT_CARD` and `installment_count` is not supplied | `SINGLE_PAYMENT` |
| Any other active payment-source type | `NORMAL` |

`obligation_type` is not accepted as a user-controlled request field.

The current API model does not expose transaction ownership or participant membership fields. These are not automatically populated by the current `ExpenseCreate` model or the `create_expense()` insert shown in the application implementation. Any database defaults or additional triggers should be verified against the live schema before relying on their behavior.

## Payment Sources

Payment sources are maintained as reference data in PostgreSQL.

The application currently recognizes these payment-source types in the database model:

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

The transaction-creation query only selects an active payment source.

For Cash Payment and Interpersonal Settlement V1, the eligible source types are `CASH` and `E_WALLET`, and the transaction must have `obligation_type = NORMAL`. These eligibility rules belong to the settlement workflow; the current API does not provide a dedicated cash-settlement endpoint.

## Response Data

### Transaction Creation Response

The transaction-creation response returns the inserted transaction fields, including the derived `obligation_type`.

When installment creation occurs, the response additionally includes `installment_plan_id`.

The POST creation response does not include `payment_name`.

Example response without installments:

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
  "obligation_type": "SINGLE_PAYMENT",
  "created_at": "2026-09-12T23:00:00"
}
```

Example response with installments:

```json
{
  "expense_id": 2,
  "transaction_date": "2026-09-12",
  "merchant": "Example Store",
  "description": "Appliance purchase",
  "amount": 12000.00,
  "category": "Appliances",
  "payment_source_id": 4,
  "notes": "Example installment transaction",
  "obligation_type": "INSTALLMENT",
  "created_at": "2026-09-12T23:00:00",
  "installment_plan_id": 12
}
```

The identifiers and values above are illustrative. The actual response is populated by the database operation.

For a transaction without installments, `installment_plan_id` is not returned as an installment-plan identifier.

### Transaction Retrieval Response

The current retrieval query returns recent transaction records with the associated payment-source information. It excludes `RECURRING` transactions from the recent-expense list.

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

The current retrieval query does not select `obligation_type`, `owner_id`, or `participant_ids`. Do not assume those fields are included in the response unless the retrieval implementation is updated.

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

For normal transaction creation, the application derives the classification from the selected payment source and installment request.

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

Creating a recurring expense causes the bounded schedule and its corresponding future-dated transaction records to be generated immediately through the database-controlled process. The scheduled `payment_date` is used as the generated transaction's `transaction_date`.

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
  +-- Insert original transaction and derive obligation_type
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

For normal transaction creation, the workflow is:

```text
Client
  |
  v
FastAPI
  |
  +-- Validate request
  |
  +-- Select active payment source
  |
  +-- Derive obligation_type
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

HTTP Basic authentication protects the web application interface and related `/app` endpoints.

Credentials are configured through environment variables and are not stored in the source repository.

### Bearer Token Authentication

Bearer-token verification protects the `/expenses` API endpoints.

The API token is configured through an environment variable.

Example request header:

```text
Authorization: Bearer <API_TOKEN>
```

The current `/health` route does not use either authentication dependency.

Sensitive credentials and tokens must not be committed to Git.

## Error Handling

The API returns JSON responses for successful transaction operations.

Validation or application errors may return an HTTP error response.

Clients should check the HTTP status code before attempting to parse a successful response.

Typical status codes include:

| Status | Meaning |
|---:|---|
| `200` | Request completed successfully |
| `201` | Transaction created successfully |
| `400` | Invalid or inactive payment source |
| `401` | Invalid authentication credentials or API token |
| `404` | Resource or route not found |
| `422` | Request validation failed |
| `500` | Internal application or database error |

When installment creation fails during transaction creation, the database transaction is rolled back.

## Security Considerations

The application follows these practices:

- Credentials are loaded from environment-based configuration.
- The `.env` file should be excluded from Git.
- API access uses bearer-token verification.
- The web application uses HTTP Basic authentication.
- Database credentials are not hardcoded in application source code.
- PostgreSQL is accessed by the application rather than directly by browser clients.
- Security response headers are set by FastAPI middleware.

The deployment-specific environment path and network configuration should be reviewed when moving the application to another host.

## Current Scope and Limitations

The API currently supports:

- Health check
- Web application delivery
- Recent transaction retrieval
- Transaction creation
- Active payment-source retrieval for the web application
- Category retrieval for the web application
- Active payment-source validation
- Optional credit-card installment creation
- Database-controlled installment schedule generation
- Transactional rollback when installment creation fails
- System-derived transaction obligation classification
- Database-controlled recurring transaction materialization

The current API does **not** expose dedicated endpoints for:

- Creating, retrieving, updating, or deleting recurring commitments
- Manually managing recurring schedules
- Setting `owner_id` or `participant_ids` through the current transaction request model
- Retrieving transaction ownership and participant membership through the current recent-expense response
- Creating or retrieving cash settlement allocations
- Creating or retrieving beneficiary cash statements
- Marking cash statements as paid
- Reconciling settlement records after upstream transaction or participant changes

The current V1 API does not implement:

- Generalized interest or amortization calculations
- Installment refunds or cancellation
- Installment modification
- Automatic historical conversion of existing transactions
- Cash-flow forecasting
- A universal payment-obligation API across all payment types
