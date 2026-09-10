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

Use Apache Superset as the analytics and reporting layer.

### Reason

Superset can connect directly to the PostgreSQL data source. This keeps analytical reporting separate from the transaction-entry application while allowing the same centralized data to be used for analysis.

## 4. Layered Architecture

### Decision

Separate the platform into frontend, application, database, and analytics layers.

### Reason

Each layer has a distinct responsibility:

- Frontend: user interaction and transaction entry
- FastAPI: application logic, validation, and authentication
- PostgreSQL: persistent transaction storage
- Apache Superset: analytics and reporting

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

The current project is designed as a self-hosted financial data platform. PostgreSQL runs locally, the FastAPI application provides the transaction interface, and Apache Superset provides analytics.

Keeping the components locally hosted gives the project a controlled development environment and demonstrates how the application, database, and analytics layers can operate together.

## 10. Keep the Initial Data Model Simple

### Decision

Use a single `transactions` table for the current version.

### Reason

The current platform focuses on capturing and analyzing financial transactions. A single central transaction entity is sufficient for the present requirements.

The model can be expanded later if additional financial use cases require more entities or relationships.
