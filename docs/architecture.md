# System Architecture

## Overview

The Finance Data Platform separates financial transaction capture, application processing, persistent storage, and analytics into distinct layers.

The architecture is designed so that transaction capture and business logic remain independent from analytical reporting.

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
  +-- transactions
  |       |
  |       +-- payment_source_id
  |                |
  |                v
  |         payment_sources
  |
  +-- credit_cards
  |
  v
Apache Superset
(Analytics & Reporting)
```

## Data Flow

1. A user enters a financial transaction through the web application.
2. The frontend sends the transaction data to the FastAPI application as a JSON request.
3. FastAPI validates the submitted data using Pydantic models.
4. The application connects to PostgreSQL using environment-based database configuration.
5. The transaction is stored in the `transactions` table.
6. Each transaction references a record in `payment_sources` through `payment_source_id`.
7. Credit-card-specific information is maintained separately in the `credit_cards` reference table.
8. Apache Superset connects to PostgreSQL and uses the stored transaction data for analytics and reporting.

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

PostgreSQL provides persistent storage for the platform.

The database separates transaction records from payment-source reference data.

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

### Payment Sources

The `payment_sources` table stores reusable payment-source reference data, including:

- Payment source name
- Payment type
- Active status
- Creation timestamp

Transactions reference payment sources through `payment_source_id` rather than storing the payment-source name directly.

When transaction data is returned to the application, the payment-source reference is joined to provide the user-visible `payment_name`.

### Credit Cards

The `credit_cards` table stores credit-card-specific reference information:

- Card name
- Statement day
- Planned payment day
- Active status
- Payment-source reference
- Creation timestamp

The `payment_day` represents the planned payment and cash-flow marker used by the application. It is not intended to represent the bank's contractual payment due date.

This separation allows credit-card-specific payment timing to be maintained independently from individual transaction records.

## Analytics Layer

Apache Superset serves as the analytics and reporting layer.

Superset connects directly to PostgreSQL rather than to the web application. This separates operational transaction capture from analytical reporting.

PostgreSQL acts as the centralized source of transaction data for the analytics layer.

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
- FastAPI: application logic, validation, and API processing
- PostgreSQL: persistent data storage and relational data management
- Superset: analytics and reporting

### Reference Data Separation

Reusable reference data is separated from transaction records.

Transactions store stable identifiers such as `payment_source_id`, while descriptive payment-source information is maintained in the `payment_sources` table.

Credit-card-specific attributes are maintained separately in `credit_cards`.

### Centralized Data

PostgreSQL acts as the central source of transaction data for both the application and analytics layer.

### Extensibility

The separation between transaction data, reference data, application processing, and analytics provides a foundation for extending the platform with additional financial use cases.

Future development can build on this architecture without coupling analytical logic directly to the transaction-entry interface.

### Portfolio Focus

The platform demonstrates how an application can capture structured business data, validate and persist it in a relational database, and make that data available for analytics.
