# Finance Data Platform

A self-hosted financial data platform for capturing, storing, and analyzing transaction data.

## Why I Built This

Financial transactions are often scattered across different sources, making it difficult to maintain a consistent and structured view of spending.

This project addresses that problem by separating **transaction capture, data storage, payment processing, and analytics** into distinct layers.

The goal is to create a simple but extensible foundation where transaction data can be captured through an application, stored reliably in PostgreSQL, and analyzed through purpose-specific analytical datasets.

Apache Superset is the current reporting and visualization platform for the project.

## What I Built

The platform currently provides:

- A web interface for transaction capture
- A FastAPI backend for request handling and validation
- PostgreSQL for structured transaction storage
- Optional credit-card installment scheduling
- Database-controlled installment payment-date and allocation logic
- A credit-card payment-level semantic layer
- PostgreSQL analytical views for reporting and visualization
- Apache Superset as the current reporting and visualization platform
- Application authentication and API authentication
- A documented data model and system architecture

## Architecture

```text
                    Finance Data Platform

User
 |
 v
Web Application
(HTML / CSS / JavaScript)
 |
 v
FastAPI
 |
 v
PostgreSQL
 |
 +-- Operational Tables
 |     |
 |     +-- transactions
 |     +-- payment_sources
 |     +-- credit_cards
 |     +-- installment_plans
 |     +-- installment_schedule
 |
 +-- Payment Semantic Layer
 |     |
 |     +-- payment_obligations
 |
 +-- Analytical Views
       |
       +-- vw_transactions
       +-- vw_monthly_payments
               |
               v
       Apache Superset
       (Reporting & Visualization)
```

### Data Flow

1. A transaction is entered through the web application.
2. FastAPI receives and validates the transaction.
3. The validated transaction is stored in PostgreSQL.
4. For eligible credit-card transactions, an optional installment request can be submitted.
5. PostgreSQL creates the installment plan and derived installment schedule using the database-controlled installment process.
6. The `payment_obligations` layer represents the current credit-card payment obligations.
7. PostgreSQL analytical views provide datasets for reporting and visualization.
8. Apache Superset consumes the analytical views for reporting and visualization.

The original transaction remains the source of truth for the spending event. Installment records represent derived payment obligations rather than additional purchases.

Apache Superset is the current reporting and visualization platform. Power BI is not part of the current reporting and visualization architecture.

## Technology Stack

| Layer | Technology |
|---|---|
| Frontend | HTML, CSS, JavaScript |
| Application | Python, FastAPI |
| Database | PostgreSQL |
| Analytics & Visualization | Apache Superset |
| Database Driver | psycopg |
| Authentication | HTTP Basic Authentication / Bearer API Token |

## Database Design

The platform separates original spending events from derived payment information.

### Core Data Model

- `transactions` — original financial spending events
- `payment_sources` — reusable payment-source reference data
- `credit_cards` — credit-card-specific reference information
- `installment_plans` — relationship between an original transaction and an installment plan
- `installment_schedule` — derived installment payment allocations
- `payment_obligations` — current credit-card payment-level semantic layer

### Analytical Views

PostgreSQL provides purpose-specific analytical views used by Apache Superset:

- `vw_transactions` — transaction-level dataset enriched with the human-readable payment source name
- `vw_monthly_payments` — aggregated credit-card payment-level dataset based on `payment_obligations`

The analytical views provide reporting-oriented datasets without replacing the operational tables.

## Credit-Card Installments

The current V1 implementation supports optional credit-card installments.

The design preserves the original transaction as the single spending event:

```text
Original Transaction
        |
        v
Installment Plan
        |
        v
Installment Schedule
        |
        v
Payment Obligations
```

The database controls:

- Credit-card eligibility
- Authoritative transaction amount
- First installment payment-date calculation
- Installment schedule generation
- Monetary allocation and rounding reconciliation
- Payment-obligation representation

The application invokes the database-controlled installment process but does not independently calculate installment payment dates or allocation logic.

V1 currently supports:

- Credit-card transactions only
- 0% interest
- Optional installment creation
- Deterministic installment allocation
- Exact reconciliation to the original transaction amount

The current implementation does not include:

- Generalized interest or amortization calculations
- Installment refunds or cancellation
- Installment modification
- Automatic historical conversion of existing transactions
- Cash-flow forecasting
- Universal payment obligations across all payment types

## Application

The FastAPI application handles:

- Transaction creation
- Transaction retrieval
- Request validation
- Authentication
- Database connectivity
- Optional credit-card installment creation
- Transactional commit and rollback behavior

The API accepts an optional `installment_count` when creating a transaction.

When an installment request is submitted, the application creates the original transaction and invokes `create_installment_plan()` within the same database transaction.

If installment creation fails, the transaction is rolled back.

See [`docs/api.md`](docs/api.md) for the API design and endpoint documentation.

## Analytics and Reporting

The current analytics architecture uses PostgreSQL analytical views as the interface between the operational database and Apache Superset.

### `vw_transactions`

Used for transaction-level reporting and visualization, including:

- Total Transactions
- Used Payment Source
- Categorical Transactions
- Daily Expenses

### `vw_monthly_payments`

Used for monthly credit-card payment reporting.

It consumes the current `payment_obligations` semantic layer and provides aggregated payment-level information for Superset.

### Current Reporting Flow

```text
PostgreSQL
    |
    +-- vw_transactions
    |
    +-- vw_monthly_payments
             |
             v
      Apache Superset
             |
             v
    Reporting & Visualization
```

See [`docs/analytics.md`](docs/analytics.md) for the analytical view contracts and current Superset dataset mapping.

## Security & Data Handling

This project is designed as a self-hosted application.

Key practices include:

- Credentials stored outside the source code
- `.env` excluded from version control
- Local database dumps excluded from version control
- Parameterized SQL queries
- Application and API authentication
- HTTP security headers

No personal financial transaction data is included in the public repository.

## Repository Structure

```text
app/                    FastAPI application
database/               Database schema and database logic
static/                 Frontend JavaScript and CSS
templates/              HTML templates
docs/                   Architecture and technical documentation
requirements.txt        Python dependencies
.env.example            Example environment configuration
```

## Documentation

- [`Architecture`](docs/architecture.md) — system architecture, layers, and data flow
- [`Data Model`](docs/data-model.md) — database structure, installment model, and payment-obligation semantics
- [`Analytics`](docs/analytics.md) — analytical views and Superset dataset usage
- [`API Documentation`](docs/api.md) — API endpoints, transaction creation, and installment flow
- [`Technical Decisions`](docs/technical-decisions.md) — key technology and architecture decisions

## Current Status

The transaction capture application, PostgreSQL data layer, credit-card installment functionality, and Apache Superset reporting and visualization layer are operational.

The current implementation includes:

- Transaction capture and retrieval
- Credit-card installment scheduling
- Database-controlled payment-date and installment allocation logic
- Credit-card payment-obligation semantics
- Transaction-level analytical reporting
- Monthly credit-card payment reporting
- Apache Superset visualization

The platform provides a foundation for structured financial transaction data and payment-level analytics while remaining extensible for future financial use cases.

## Project Direction

Future development can extend the platform toward:

- More comprehensive financial analytics
- Additional transaction sources
- Data transformation and validation workflows
- Expanded reporting capabilities
- Additional automation around transaction processing
- More advanced financial insights

Future capabilities should be treated as planned extensions rather than current functionality unless implemented and documented.

---

Built as a personal data engineering and analytics project.