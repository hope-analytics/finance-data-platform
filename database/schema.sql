-- Finance Data Platform
-- PostgreSQL schema

CREATE TABLE transactions (
    expense_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_date DATE NOT NULL,
    merchant VARCHAR(150) NOT NULL,
    description TEXT,
    amount NUMERIC(12,2) NOT NULL,
    category VARCHAR(100),
    payment_source VARCHAR(50) NOT NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Credit card reference data
CREATE TABLE credit_cards (
    credit_card_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    card_name VARCHAR(100) NOT NULL UNIQUE,
    statement_day SMALLINT NOT NULL CHECK (statement_day BETWEEN 1 AND 31),
    payment_day SMALLINT NOT NULL CHECK (payment_day IN (1, 15)),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

COMMENT ON COLUMN credit_cards.payment_day IS
'Planned payment and cash-flow marker (1st or 15th), not the bank contractual due date.';
