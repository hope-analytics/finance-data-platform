-- Finance Data Platform PostgreSQL schema

-- Reference data for payment sources used by transactions.
CREATE TABLE payment_sources (
    payment_source_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_name VARCHAR(100) NOT NULL UNIQUE,
    payment_type VARCHAR(30) NOT NULL CHECK (
        payment_type IN (
            'CASH',
            'E_WALLET',
            'BANK_ACCOUNT',
            'DEBIT_CARD',
            'CREDIT_CARD',
            'BNPL',
            'OTHER'
        )
    ),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Credit-card-specific reference data.
CREATE TABLE credit_cards (
    credit_card_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    card_name VARCHAR(100) NOT NULL UNIQUE,
    statement_day SMALLINT NOT NULL CHECK (statement_day BETWEEN 1 AND 31),
    payment_day SMALLINT NOT NULL CHECK (payment_day IN (1, 15)),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    payment_source_id BIGINT NOT NULL,
    CONSTRAINT credit_cards_payment_source_fk
        FOREIGN KEY (payment_source_id)
        REFERENCES payment_sources(payment_source_id)
);

COMMENT ON COLUMN credit_cards.payment_day IS
'Planned payment and cash-flow marker (1st or 15th), not the bank contractual due date.';

-- Transaction records.
CREATE TABLE transactions (
    expense_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_date DATE NOT NULL,
    merchant VARCHAR(150) NOT NULL,
    description TEXT,
    amount NUMERIC(12,2) NOT NULL,
    category VARCHAR(100),
    payment_source_id BIGINT NOT NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT transactions_payment_source_fk
        FOREIGN KEY (payment_source_id)
        REFERENCES payment_sources(payment_source_id)
);

-- Reference values currently used by the application.
INSERT INTO payment_sources (payment_name, payment_type) VALUES
    ('BPI - Amore Cashback', 'CREDIT_CARD'),
    ('UB - Rewards', 'CREDIT_CARD'),
    ('UB - Platinum', 'CREDIT_CARD'),
    ('Cash', 'CASH'),
    ('Gcash', 'E_WALLET');

-- Credit-card reference values.
INSERT INTO credit_cards (
    card_name,
    statement_day,
    payment_day,
    payment_source_id
)
SELECT
    v.card_name,
    v.statement_day,
    v.payment_day,
    ps.payment_source_id
FROM (
    VALUES
        ('BPI - Amore Cashback', 28, 15),
        ('UB - Rewards', 18, 1),
        ('UB - Platinum', 12, 1)
) AS v(card_name, statement_day, payment_day)
JOIN payment_sources AS ps
    ON ps.payment_name = v.card_name
WHERE ps.payment_type = 'CREDIT_CARD';

-- Analytical view exposing transaction records with payment-source information.
CREATE OR REPLACE VIEW vw_transactions AS
SELECT
    t.expense_id,
    t.transaction_date,
    t.merchant,
    t.description,
    t.amount,
    t.category,
    t.notes,
    t.created_at,
    ps.payment_name
FROM transactions t
JOIN payment_sources ps
    ON t.payment_source_id = ps.payment_source_id;


-- Analytical view calculating planned monthly credit-card payments.
CREATE OR REPLACE VIEW vw_monthly_payments AS
WITH payment_schedule AS (
    SELECT
        t.expense_id,
        t.transaction_date,
        t.amount,
        ps.payment_name,
        cc.statement_day,
        cc.payment_day,

        CASE
            WHEN EXTRACT(DAY FROM t.transaction_date) <= cc.statement_day
                THEN DATE_TRUNC('month', t.transaction_date)
            ELSE DATE_TRUNC('month', t.transaction_date) + INTERVAL '1 month'
        END AS statement_month,

        CASE
            WHEN EXTRACT(DAY FROM t.transaction_date) <= cc.statement_day
                THEN DATE_TRUNC('month', t.transaction_date) + INTERVAL '1 month'
            ELSE DATE_TRUNC('month', t.transaction_date) + INTERVAL '2 month'
        END AS payment_month

    FROM transactions t
    JOIN payment_sources ps
        ON t.payment_source_id = ps.payment_source_id
    JOIN credit_cards cc
        ON ps.payment_source_id = cc.payment_source_id
)

SELECT
    TO_CHAR(payment_month, 'Mon YYYY') AS monthyear,
    EXTRACT(YEAR FROM payment_month)::INTEGER AS year,
    EXTRACT(MONTH FROM payment_month)::INTEGER AS month,
    payment_day,

    MAKE_DATE(
        EXTRACT(YEAR FROM payment_month)::INTEGER,
        EXTRACT(MONTH FROM payment_month)::INTEGER,
        payment_day::INTEGER
    ) AS payment_due,

    SUM(amount) AS total_payment,
    COUNT(*) AS transaction_count

FROM payment_schedule
GROUP BY
    payment_month,
    payment_day
ORDER BY
    payment_month DESC;