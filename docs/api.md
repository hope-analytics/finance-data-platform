# API Documentation

## Overview

The Finance Data Platform exposes a FastAPI backend for transaction capture and retrieval.

The API accepts JSON requests from the web application and persists validated transaction data in PostgreSQL.

## Base URL

When running locally:

```text
http://<TAIL_SCALE_IP>:8000
```

For LAN access from another device:

```text
http://<SERVER_IP>>:8000
```

The application must be running and accessible on the network before using the LAN address.

## Endpoints

### Application Interface

#### `GET /app`

Returns the web application interface.

The route is protected using HTTP Basic authentication.

#### `GET /app/expenses`

Returns recent transaction records for display in the web application.

The response includes transaction details and the associated payment-source name.

#### `POST /app/expenses`

Creates a new transaction from the web application.

The request is validated before the transaction is inserted into PostgreSQL.

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

The `payment_source_id` must reference an active record in the `payment_sources` table.

A successful request returns the created transaction as JSON.

### API Endpoints

#### `GET /expenses`

Returns transaction records through the API.

The endpoint uses bearer-token verification.

#### `POST /expenses`

Creates a transaction through the API.

The endpoint uses bearer-token verification.

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

## Request Validation

Transaction requests are validated using Pydantic models before database insertion.

Validation covers the expected transaction fields and data types.

The transaction amount is represented as a decimal value and stored in PostgreSQL using `NUMERIC(12,2)`.

The payment source is represented by `payment_source_id` rather than a free-text payment-source name.

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

Transaction responses include the stored transaction fields and the user-visible payment-source information.

The payment-source name is obtained by joining the transaction to the `payment_sources` reference table.

Example response:

```json
{
  "expense_id": 1,
  "transaction_date": "2026-09-12",
  "merchant": "Example Store",
  "description": "Household supplies",
  "amount": 500.00,
  "category": "Household",
  "payment_source_id": 4,
  "payment_name": "Cash",
  "notes": "Example transaction",
  "created_at": "2026-09-12T23:00:00"
}
```

## Authentication

The application uses two authentication mechanisms for different API surfaces:

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

## Database Interaction

The FastAPI application connects to PostgreSQL using environment-based configuration.

The application does not expose PostgreSQL directly to clients.

The transaction workflow is:

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

The application uses the `payment_sources` table to resolve the selected payment source and store its identifier in the transaction record.

## Security Considerations

The application follows these practices:

- Credentials are stored in environment variables.
- The `.env` file is excluded from Git.
- API access uses bearer-token verification.
- The web application uses HTTP Basic authentication.
- Database credentials are not hardcoded in application source code.
- PostgreSQL is accessed by the application rather than directly by browser clients.

## Current Scope

The API currently focuses on transaction capture and retrieval.

The platform does not yet implement a dedicated cash-flow engine or automated credit-card payment calculations.

Credit-card reference data is stored separately and can be used by future application features.
