# Finance Data Platform

A self-hosted financial data platform for capturing, storing, and analyzing transaction data.

## Why I Built This

Financial transactions are often scattered across different sources, making it difficult to maintain a consistent and structured view of spending.

This project addresses that problem by separating **transaction capture, data storage, and analytics** into distinct layers.

The goal is to create a simple but extensible foundation where transaction data can be captured through an application, stored reliably in PostgreSQL, and analyzed through Apache Superset.

## What I Built

The platform currently provides:

- A web interface for transaction capture
- A FastAPI backend for request handling and validation
- PostgreSQL for structured transaction storage
- Apache Superset as the analytics layer
- Application authentication and API authentication
- A documented data model and system architecture

## Architecture

```text
                    Finance Data Platform

Transactions
     |
     v
Web Application
     |
     v
FastAPI
     |
     v
PostgreSQL
     |
     v
Apache Superset
```

### Data Flow

1. A transaction is entered through the web application.
2. FastAPI receives and validates the transaction.
3. The validated transaction is stored in PostgreSQL.
4. Apache Superset connects to PostgreSQL for analytics and reporting.

This separation keeps the transaction capture layer independent from the analytics layer and provides a foundation for future expansion.

## Technology Stack

| Layer | Technology |
|---|---|
| Frontend | HTML, CSS, JavaScript |
| Application | Python, FastAPI |
| Database | PostgreSQL |
| Analytics | Apache Superset |
| Database Driver | psycopg |
| Authentication | HTTP Basic Authentication / Bearer API Token |

## Database Design

The current platform uses a `transactions` table designed around the core attributes of a financial transaction:

- Transaction date
- Merchant
- Description
- Amount
- Category
- Payment source
- Notes
- Creation timestamp

Transaction IDs are generated using a PostgreSQL identity column.

Financial amounts use `NUMERIC(12,2)` to preserve decimal precision.

More detail is available in [`docs/data-model.md`](docs/data-model.md).

## Application

The FastAPI application handles:

- Transaction creation
- Transaction retrieval
- Request validation
- Authentication
- Database connectivity
- Web-based transaction capture and viewing

Database credentials and application secrets are stored through environment variables rather than hard-coded into the application.

The API uses parameterized SQL for database operations.

See [`docs/api.md`](docs/api.md) for the API design and endpoint documentation.

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
database/               Database schema
static/                 Frontend JavaScript and CSS
templates/              HTML templates
docs/                   Architecture and technical documentation
requirements.txt        Python dependencies
.env.example            Example environment configuration
```

## Documentation

- [`Architecture`](docs/architecture.md) — system architecture and data flow
- [`Data Model`](docs/data-model.md) — database structure and design
- [`API Documentation`](docs/api.md) — API endpoints and request flow
- [`Technical Decisions`](docs/technical-decisions.md) — key technology and architecture decisions

## Current Status

The transaction capture application, PostgreSQL data layer, and Apache Superset analytics layer are operational.

The current implementation focuses on establishing a reliable foundation for structured financial transaction data and future analytics capabilities.

## Project Direction

Future development can extend the platform toward:

- More comprehensive financial analytics
- Additional transaction sources
- Data transformation and validation workflows
- Expanded reporting capabilities
- Additional automation around transaction processing

---

Built as a personal data engineering and analytics project.
