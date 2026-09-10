# API Documentation

## Overview

The Finance Data Platform uses FastAPI as its application layer between the web interface and PostgreSQL.

The API is responsible for receiving transaction data, validating requests, authenticating access, and reading or writing transaction records.

## Authentication

The application uses two authentication approaches in the current implementation.

### HTTP Basic Authentication

The following application endpoints use HTTP Basic authentication:

- `GET /app`
- `GET /expenses`
- `POST /expenses`

The application username and password are supplied through environment variables:

- `APP_USERNAME`
- `APP_PASSWORD`

### Bearer Token Authentication

The API also defines bearer-token verification using the `Authorization` header.

The expected format is:

```text
Authorization: Bearer <API_TOKEN>
```

The API token is supplied through the `API_TOKEN` environment variable.

## Expense Data Model

Transaction creation uses the `ExpenseCreate` Pydantic model.

| Field | Type | Required | Validation |
|---|---|---|---|
| `transaction_date` | date | Yes | Valid date |
| `merchant` | string | Yes | 1–150 characters |
| `description` | string | No | Optional |
| `amount` | Decimal | Yes | Greater than 0 |
| `category` | string | No | Optional |
| `payment_source` | string | Yes | 1–50 characters |
| `notes` | string | No | Optional |

## Endpoints

### `GET /app`

Returns the main web application interface.

Authentication: HTTP Basic.

### `GET /expenses`

Retrieves transaction records from PostgreSQL.

Authentication: HTTP Basic.

Transactions are returned in descending order by transaction date and transaction ID.

### `POST /expenses`

Creates a new transaction in PostgreSQL.

Authentication: HTTP Basic.

The request body contains the fields defined by `ExpenseCreate`.

The database generates the transaction ID.

### `GET /app/expenses`

Retrieves transaction records for the web application's expense list.

The frontend calls this endpoint to load recent transactions.

### `POST /app/expenses`

Creates a transaction from the web application's expense form.

The frontend sends the transaction as JSON to this endpoint.

## Request Flow

```text
Web Application
       |
       | JSON request
       v
FastAPI
       |
       | Validate with ExpenseCreate
       v
PostgreSQL
       |
       | INSERT / SELECT
       v
Transaction Data
```

## Database Interaction

The application uses the `psycopg` PostgreSQL driver.

Database connection settings are loaded from environment variables:

- `DB_HOST`
- `DB_PORT`
- `DB_NAME`
- `DB_USER`
- `DB_PASSWORD`

The application uses parameterized SQL statements when inserting transaction data.

## Error Handling

Invalid authentication results in an HTTP `401 Unauthorized` response.

The frontend also handles unsuccessful API responses and displays an error message to the user.

## Security Considerations

Sensitive configuration is kept outside the source code using environment variables.

The application also adds security-related HTTP response headers, including:

- `X-Content-Type-Options`
- `X-Frame-Options`
- `Referrer-Policy`
- `Permissions-Policy`

The actual `.env` file is excluded from the Git repository.
