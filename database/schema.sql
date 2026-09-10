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
