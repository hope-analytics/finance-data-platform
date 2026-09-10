# Data Model

## Overview

The Finance Data Platform currently uses a `transactions` table as the central entity for financial transaction data.

## Transactions Table

| Column | Data Type | Constraints | Description |
|---|---|---|---|
| `expense_id` | BIGINT | Primary Key, Identity | Unique identifier for each transaction |
| `transaction_date` | DATE | NOT NULL | Date the transaction occurred |
| `merchant` | VARCHAR(150) | NOT NULL | Merchant or transaction source |
| `description` | TEXT | Nullable | Additional transaction description |
| `amount` | NUMERIC(12,2) | NOT NULL | Financial transaction amount |
| `category` | VARCHAR(100) | Nullable | Transaction category |
| `payment_source` | VARCHAR(50) | NOT NULL | Source used to make the payment |
| `notes` | TEXT | Nullable | Additional transaction notes |
| `created_at` | TIMESTAMP | NOT NULL, Default | Timestamp when the record was created |

## Primary Key

`expense_id` is the primary key of the table and is generated automatically using a PostgreSQL identity column.

This provides a unique identifier for each transaction without requiring the application to generate IDs.

## Financial Data Type

The `amount` column uses:

`NUMERIC(12,2)`

This provides fixed decimal precision appropriate for storing financial amounts.

## Required vs Optional Fields

Required fields represent information needed to create a valid transaction:

- `transaction_date`
- `merchant`
- `amount`
- `payment_source`

Optional fields provide additional context:

- `description`
- `category`
- `notes`

## Record Metadata

`created_at` records when the transaction was inserted into the database. It defaults to the current timestamp, allowing the database to automatically capture record creation time.

## Current Design

The current model intentionally keeps the transaction structure simple. The `transactions` table acts as the central source of financial transaction data for the application and analytics layer.

Future iterations can extend the model as additional financial use cases are identified.
