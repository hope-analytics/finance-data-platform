# System Architecture

## Overview

The Finance Data Platform separates financial transaction capture, API processing, persistent storage, and analytics into distinct layers.

## Architecture

```text
User
  |
  v
Web Application
(HTML / CSS / JavaScript)
  |
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
  v
Apache Superset
(Analytics & Reporting)
```

## Data Flow

1. A user enters a financial transaction through the web application.
2. The frontend sends the transaction data to the FastAPI application.
3. FastAPI validates the submitted data using Pydantic models.
4. The application connects to PostgreSQL using environment-based database configuration.
5. The transaction is stored in the `transactions` table.
6. Apache Superset connects to PostgreSQL and uses the stored transaction data for analytics and reporting.

## Application Layer

The application layer consists of a browser-based interface and a FastAPI backend.

### Web Application

The frontend provides:

- Transaction entry
- Payment source selection
- Category and description fields
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

## Database Layer

PostgreSQL provides persistent storage for financial transactions.

The current data model uses a `transactions` table with:

- `expense_id`
- `transaction_date`
- `merchant`
- `description`
- `amount`
- `category`
- `payment_source`
- `notes`
- `created_at`

The transaction identifier is generated automatically using a PostgreSQL identity column.

Financial amounts use `NUMERIC(12,2)` to preserve decimal precision.

## Analytics Layer

Apache Superset serves as the analytics and reporting layer.

It connects to the centralized PostgreSQL data rather than directly to the web application. This separates operational transaction capture from analytical reporting.

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

- Frontend: user interaction
- FastAPI: application logic and validation
- PostgreSQL: persistent data storage
- Superset: analytics and reporting

### Centralized Data

PostgreSQL acts as the central source of transaction data for the platform.

### Portfolio Focus

The platform demonstrates how an application can capture structured business data, persist it in a relational database, and make that data available for analytics.
