# Data Model

## Overview

The Finance Data Platform uses PostgreSQL to separate transaction records from reusable payment-source reference data and credit-card-specific information.

The current data model consists of three core tables:

```text
payment_sources
      |
      +--------------------+
      |                    |
      v                    v
transactions         credit_cards
```

`transactions` stores individual financial transactions.

`payment_sources` stores reusable payment-source reference values.

`credit_cards` stores credit-card-specific reference information.

## Entity Relationships

### Payment Sources → Transactions

One payment source can be associated with many transactions.

```text
payment_sources
      |
      | 1
      |
      | N
      v
transactions
```

Relationship:

```text
payment_sources.payment_source_id
        |
        +----< transactions.payment_source_id
```

The transaction table stores the `payment_source_id` foreign key rather than the payment-source name.

### Payment Sources → Credit Cards

A credit card is associated with a payment source.

```text
payment_sources
      |
      | 1
      |
      | N
      v
credit_cards
```

Relationship:

```text
payment_sources.payment_source_id
        |
        +----< credit_cards.payment_source_id
```

This allows a credit card to use the same payment-source reference used by transactions.

## Tables

### `transactions`

Stores individual financial transaction records.

| Column | Type | Constraints / Purpose |
|---|---|---|
| `expense_id` | BIGINT | Primary key, generated identity |
| `transaction_date` | DATE | Required transaction date |
| `merchant` | VARCHAR(150) | Required merchant name |
| `description` | TEXT | Optional transaction description |
| `amount` | NUMERIC(12,2) | Required financial amount |
| `category` | VARCHAR(100) | Optional transaction category |
| `payment_source_id` | BIGINT | Required foreign key to `payment_sources` |
| `notes` | TEXT | Optional transaction notes |
| `created_at` | TIMESTAMP | Record creation timestamp |

### `payment_sources`

Stores reusable payment-source reference data.

| Column | Type | Constraints / Purpose |
|---|---|---|
| `payment_source_id` | BIGINT | Primary key, generated identity |
| `payment_name` | VARCHAR(100) | Required and unique payment-source name |
| `payment_type` | VARCHAR(30) | Required; controlled payment-source type |
| `active` | BOOLEAN | Indicates whether the source can be used |
| `created_at` | TIMESTAMP | Record creation timestamp |

Current supported payment types are:

- `CASH`
- `E_WALLET`
- `BANK_ACCOUNT`
- `DEBIT_CARD`
- `CREDIT_CARD`
- `BNPL`
- `OTHER`

Current reference values include:

| Payment Source | Type |
|---|---|
| BPI - Amore Cashback | CREDIT_CARD |
| UB - Rewards | CREDIT_CARD |
| UB - Platinum | CREDIT_CARD |
| Cash | CASH |
| Gcash | E_WALLET |

### `credit_cards`

Stores credit-card-specific reference information.

| Column | Type | Constraints / Purpose |
|---|---|---|
| `credit_card_id` | BIGINT | Primary key, generated identity |
| `card_name` | VARCHAR(100) | Required and unique card name |
| `statement_day` | SMALLINT | Required; day from 1 to 31 |
| `payment_day` | SMALLINT | Required; planned payment day of 1 or 15 |
| `active` | BOOLEAN | Indicates whether the card is active |
| `created_at` | TIMESTAMP | Record creation timestamp |
| `payment_source_id` | BIGINT | Required foreign key to `payment_sources` |

### Credit Card Payment Day

The `payment_day` field represents the user's planned payment and cash-flow marker.

It is intentionally separate from the bank's contractual payment due date.

The current application supports:

- `1` — planned payment on the 1st
- `15` — planned payment on the 15th

This field is intended to support future cash-flow planning without changing individual transaction records.

## Referential Integrity

Foreign-key relationships enforce valid references between the tables.

### Transactions

```text
transactions.payment_source_id
        |
        v
payment_sources.payment_source_id
```

A transaction must reference an existing payment-source record.

### Credit Cards

```text
credit_cards.payment_source_id
        |
        v
payment_sources.payment_source_id
```

A credit-card record must reference an existing payment-source record.

## Design Decisions

### Separate Payment Sources from Transactions

Payment-source information is stored in a reference table rather than repeated as text in every transaction.

This provides:

- Consistent payment-source naming
- Controlled payment types
- Referential integrity
- Easier maintenance of payment-source metadata

### Separate Credit-Card Data

Credit-card-specific attributes are stored in `credit_cards` rather than directly in `transactions`.

This keeps transaction records focused on individual purchases while allowing card-level information such as statement and planned payment days to be managed independently.

### Planned Payment Day vs. Contractual Due Date

The model intentionally uses `payment_day` rather than `due_date`.

`payment_day` represents the user's planned payment schedule for cash-flow planning. It should not be interpreted as the bank's contractual due date.

### Transaction Amount

Financial amounts are stored using:

```text
NUMERIC(12,2)
```

This preserves two decimal places for financial calculations and avoids floating-point representation issues.

### Generated Identifiers

Primary keys use PostgreSQL identity columns.

This allows PostgreSQL to generate unique identifiers for transactions and reference records.

## Current Scope

The current data model supports:

- Financial transaction capture
- Payment-source reference data
- Credit-card reference data
- Transaction-to-payment-source relationships
- Credit-card-to-payment-source relationships
- Planned payment-day information

The model does not currently implement:

- Credit-card statement records
- Automated contractual due-date calculations
- Cash-flow forecasting
- Installment schedules
- Automated payment allocation

These can be introduced as separate capabilities in future development without changing the core transaction structure.
