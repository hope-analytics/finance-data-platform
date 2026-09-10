# Finance Data Platform

A self-hosted financial data platform for capturing, storing, and analyzing transaction data.

## Overview

The Finance Data Platform is designed to centralize financial transaction data in PostgreSQL while providing a simple application for transaction capture and Apache Superset for analytics.

## Architecture

```text
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

## Technology Stack

- Python
- FastAPI
- PostgreSQL
- Apache Superset
- HTML
- CSS
- JavaScript

## Current Data Flow

1. Transactions are entered through the web application.
2. FastAPI receives and validates the transaction data.
3. Transactions are stored in PostgreSQL.
4. Apache Superset connects to PostgreSQL for analytics and reporting.

## Database

The current data model uses a `transactions` table containing:

- Transaction date
- Merchant
- Description
- Amount
- Category
- Payment source
- Notes
- Creation timestamp

Transaction IDs are generated automatically using a PostgreSQL identity column.

Financial amounts are stored using `NUMERIC(12,2)` to preserve decimal precision.

## Application

The FastAPI application provides:

- Transaction creation
- Transaction retrieval
- Request validation
- Application authentication
- Database connectivity
- A web interface for entering and viewing transactions

## Repository Structure

```text
app/            FastAPI application
database/       Database schema
static/         Frontend JavaScript and CSS
templates/      HTML templates
docs/           Project documentation
screenshots/    Application and analytics screenshots
```

## Project Goals

- Centralize financial transaction data
- Simplify transaction capture
- Store structured financial data in PostgreSQL
- Separate transaction capture from analytics
- Build a foundation for future financial analysis and reporting

## Current Status

The transaction capture application and PostgreSQL data layer are operational. Apache Superset is used as the analytics layer.
