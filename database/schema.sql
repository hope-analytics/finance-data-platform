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

-- Installment plan for applicable payment source

CREATE TABLE installment_plans (
    plan_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    expense_id BIGINT NOT NULL,
    original_amount NUMERIC(12,2) NOT NULL CHECK (original_amount > 0),
    installment_count SMALLINT NOT NULL CHECK (installment_count >= 2),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT installment_plans_expense_fk
        FOREIGN KEY (expense_id)
        REFERENCES transactions(expense_id),

    CONSTRAINT installment_plans_expense_unique
        UNIQUE (expense_id)
);

-- Installment schedule for transactions with installment plan

CREATE TABLE installment_schedule (
    schedule_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_id BIGINT NOT NULL,
    installment_number SMALLINT NOT NULL CHECK (installment_number >= 1),
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    payment_due DATE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT installment_schedule_plan_fk
        FOREIGN KEY (plan_id)
        REFERENCES installment_plans(plan_id),

    CONSTRAINT installment_schedule_plan_number_unique
        UNIQUE (plan_id, installment_number)
);

-- Payment due function

CREATE OR REPLACE FUNCTION calculate_payment_due(
    p_transaction_date DATE,
    p_statement_day SMALLINT,
    p_payment_day SMALLINT
)
RETURNS DATE
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT MAKE_DATE(
        EXTRACT(
            YEAR FROM
            CASE
                WHEN EXTRACT(DAY FROM p_transaction_date) <= p_statement_day
                    THEN DATE_TRUNC('month', p_transaction_date) + INTERVAL '1 month'
                ELSE DATE_TRUNC('month', p_transaction_date) + INTERVAL '2 month'
            END
        )::INTEGER,
        EXTRACT(
            MONTH FROM
            CASE
                WHEN EXTRACT(DAY FROM p_transaction_date) <= p_statement_day
                    THEN DATE_TRUNC('month', p_transaction_date) + INTERVAL '1 month'
                ELSE DATE_TRUNC('month', p_transaction_date) + INTERVAL '2 month'
            END
        )::INTEGER,
        p_payment_day::INTEGER
    );
$$;

-- Installment plan function

CREATE OR REPLACE FUNCTION create_installment_plan(
    p_expense_id BIGINT,
    p_installment_count SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_plan_id BIGINT;
    v_amount NUMERIC(12,2);
    v_payment_source_id BIGINT;
    v_payment_type VARCHAR(30);
    v_statement_day SMALLINT;
    v_payment_day SMALLINT;
    v_first_payment_due DATE;
    v_base_amount NUMERIC(12,2);
    v_final_amount NUMERIC(12,2);
    v_previous_total NUMERIC(12,2);
    v_installment_number SMALLINT;
BEGIN
    
    -- Validate installment count.

    IF p_installment_count IS NULL OR p_installment_count < 2 THEN
        RAISE EXCEPTION
            'installment_count must be at least 2; received %',
            p_installment_count;
    END IF;

    -- Lock the source transaction and read its authoritative amount.

    SELECT
        t.amount,
        t.payment_source_id,
        ps.payment_type
    INTO
        v_amount,
        v_payment_source_id,
        v_payment_type
    FROM transactions AS t
    JOIN payment_sources AS ps
        ON ps.payment_source_id = t.payment_source_id
    WHERE t.expense_id = p_expense_id
    FOR UPDATE OF t;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Transaction % does not exist',
            p_expense_id;
    END IF;

    -- Installments are credit-card only.

    IF v_payment_type <> 'CREDIT_CARD' THEN
        RAISE EXCEPTION
            'Transaction % is not a credit-card transaction',
            p_expense_id;
    END IF;

    -- Retrieve the credit-card payment-cycle configuration.
    -- The current model expects the payment source to resolve to one credit-card configuration.

    SELECT
        cc.statement_day,
        cc.payment_day
    INTO STRICT
        v_statement_day,
        v_payment_day
    FROM credit_cards AS cc
    WHERE cc.payment_source_id = v_payment_source_id;

    -- Prevent duplicate installment plans.

    IF EXISTS (
        SELECT 1
        FROM installment_plans AS ip
        WHERE ip.expense_id = p_expense_id
    ) THEN
        RAISE EXCEPTION
            'Transaction % already has an installment plan',
            p_expense_id;
    END IF;

    -- The source transaction amount is authoritative.

    INSERT INTO installment_plans (
        expense_id,
        original_amount,
        installment_count
    )
    VALUES (
        p_expense_id,
        v_amount,
        p_installment_count
    )
    RETURNING plan_id
    INTO v_plan_id;

    -- First installment uses the single payment-cycle authority.

    v_first_payment_due := calculate_payment_due(
        (
            SELECT transaction_date
            FROM transactions
            WHERE expense_id = p_expense_id
        ),
        v_statement_day,
        v_payment_day
    );

    -- Deterministic monetary allocation.

    v_base_amount := TRUNC(
        v_amount / p_installment_count,
        2
    );

    --Generate installments 1 through N-1.
    
    FOR v_installment_number IN 1..(p_installment_count - 1)
    LOOP
        INSERT INTO installment_schedule (
            plan_id,
            installment_number,
            amount,
            payment_due
        )
        VALUES (
            v_plan_id,
            v_installment_number,
            v_base_amount,
            v_first_payment_due
                + ((v_installment_number - 1) * INTERVAL '1 month')
        );
    END LOOP;

    -- Calculate the exact remaining amount for the final installment.

    SELECT COALESCE(SUM(amount), 0)
    INTO v_previous_total
    FROM installment_schedule
    WHERE plan_id = v_plan_id;

    v_final_amount := v_amount - v_previous_total;

    INSERT INTO installment_schedule (
        plan_id,
        installment_number,
        amount,
        payment_due
    )
    VALUES (
        v_plan_id,
        p_installment_count,
        v_final_amount,
        v_first_payment_due
            + ((p_installment_count - 1) * INTERVAL '1 month')
    );

    -- Final reconciliation.
    
    SELECT COALESCE(SUM(amount), 0)
    INTO v_previous_total
    FROM installment_schedule
    WHERE plan_id = v_plan_id;

    IF v_previous_total <> v_amount THEN
        RAISE EXCEPTION
            'Installment reconciliation failed for plan %: schedule total % != transaction amount %',
            v_plan_id,
            v_previous_total,
            v_amount;
    END IF;

    -- Validate schedule cardinality.
    
    IF (
        SELECT COUNT(*)
        FROM installment_schedule
        WHERE plan_id = v_plan_id
    ) <> p_installment_count THEN
        RAISE EXCEPTION
            'Installment schedule count mismatch for plan %',
            v_plan_id;
    END IF;

    RETURN v_plan_id;
END;
$$;

CREATE OR REPLACE VIEW payment_obligations AS

-- Normal credit-card transactions:
-- one obligation for the full transaction amount,
-- but only when no installment plan exists.

SELECT
    t.expense_id,
    t.payment_source_id,
    calculate_payment_due(
        t.transaction_date,
        cc.statement_day,
        cc.payment_day
    ) AS payment_due,
    t.amount AS payment_amount,
    'NORMAL'::VARCHAR(20) AS obligation_type,
    NULL::BIGINT AS plan_id,
    NULL::SMALLINT AS installment_number
FROM transactions AS t
JOIN payment_sources AS ps
    ON ps.payment_source_id = t.payment_source_id
JOIN credit_cards AS cc
    ON cc.payment_source_id = t.payment_source_id
WHERE ps.payment_type = 'CREDIT_CARD'
  AND NOT EXISTS (
      SELECT 1
      FROM installment_plans AS ip
      WHERE ip.expense_id = t.expense_id
  )

UNION ALL

-- Installment transactions:
-- obligations come exclusively from the installment schedule.

SELECT
    ip.expense_id,
    t.payment_source_id,
    s.payment_due,
    s.amount AS payment_amount,
    'INSTALLMENT'::VARCHAR(20) AS obligation_type,
    ip.plan_id,
    s.installment_number
FROM installment_plans AS ip
JOIN transactions AS t
    ON t.expense_id = ip.expense_id
JOIN installment_schedule AS s
    ON s.plan_id = ip.plan_id;

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
SELECT
    TO_CHAR(DATE_TRUNC('month', po.payment_due), 'Mon YYYY') AS monthyear,
    EXTRACT(YEAR FROM po.payment_due)::INTEGER AS year,
    EXTRACT(MONTH FROM po.payment_due)::INTEGER AS month,
    cc.payment_day,
    po.payment_due,
    SUM(po.payment_amount) AS total_payment,
    COUNT(*) AS transaction_count
FROM payment_obligations AS po
JOIN credit_cards AS cc
    ON cc.payment_source_id = po.payment_source_id
GROUP BY
    DATE_TRUNC('month', po.payment_due),
    cc.payment_day,
    po.payment_due
ORDER BY
    po.payment_due DESC;