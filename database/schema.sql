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
    category_id BIGINT,
    obligation_type VARCHAR(20) NOT NULL,
    owner_id BIGINT NOT NULL,
    participant_ids BIGINT[] NOT NULL DEFAULT '{}', 
    
    CONSTRAINT transactions_payment_source_fk
        FOREIGN KEY (payment_source_id)
        REFERENCES payment_sources(payment_source_id),
    
    CONSTRAINT transactions_category_fk
        FOREIGN KEY (category_id)
        REFERENCES transactions_category(category_id),

    CONSTRAINT transactions_obligation_type_check
        CHECK (
            obligation_type IN (
                'NORMAL',
                'SINGLE_PAYMENT',
                'RECURRING',
                'INSTALLMENT'
                )
        ),
    
    CONSTRAINT transactions_owner_fk
        FOREIGN KEY (owner_id)
        REFERENCES people (person_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

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

-- Credit-card single-payment obligations
SELECT
    t.expense_id,
    t.payment_source_id,
    calculate_payment_due(
        t.transaction_date,
        cc.statement_day,
        cc.payment_day
    ) AS payment_due,
    t.amount AS payment_amount,
    'SINGLE_PAYMENT'::VARCHAR(20) AS obligation_type,
    NULL::BIGINT AS plan_id,
    NULL::SMALLINT AS installment_number,
    t.merchant
FROM transactions AS t
JOIN payment_sources AS ps
    ON ps.payment_source_id = t.payment_source_id
JOIN credit_cards AS cc
    ON cc.payment_source_id = t.payment_source_id
WHERE t.obligation_type = 'SINGLE_PAYMENT'

UNION ALL

-- Credit-card installment obligations
SELECT
    ip.expense_id,
    t.payment_source_id,
    s.payment_due,
    s.amount AS payment_amount,
    'INSTALLMENT'::VARCHAR(20) AS obligation_type,
    ip.plan_id,
    s.installment_number,
    t.merchant
FROM installment_plans AS ip
JOIN transactions AS t
    ON t.expense_id = ip.expense_id
JOIN installment_schedule AS s
    ON s.plan_id = ip.plan_id

UNION ALL

-- Recurring payment obligations
SELECT
    t.expense_id,
    t.payment_source_id,
    t.transaction_date AS payment_due,
    t.amount AS payment_amount,
    'RECURRING'::VARCHAR(20) AS obligation_type,
    NULL::BIGINT AS plan_id,
    NULL::SMALLINT AS installment_number,
    t.merchant
FROM transactions AS t
WHERE t.obligation_type = 'RECURRING';

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
    ps.payment_name,
    t.obligation_type
FROM transactions AS t
LEFT JOIN payment_sources AS ps
    ON ps.payment_source_id = t.payment_source_id;

-- Analytical view calculating planned monthly credit-card payments.

CREATE OR REPLACE VIEW vw_monthly_payments AS
SELECT
    TO_CHAR(DATE_TRUNC('month', po.payment_due), 'Mon YYYY') AS monthyear,
    EXTRACT(YEAR FROM po.payment_due)::INTEGER AS year,
    EXTRACT(MONTH FROM po.payment_due)::INTEGER AS month,
    EXTRACT(DAY FROM po.payment_due)::SMALLINT AS payment_day,
    po.payment_due,
    SUM(po.payment_amount) AS total_payment,
    COUNT(*) AS transaction_count,
    po.obligation_type
FROM payment_obligations AS po
GROUP BY
    DATE_TRUNC('month', po.payment_due),
    po.payment_due,
    po.obligation_type
ORDER BY
    po.payment_due DESC;

CREATE TABLE transactions_category (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL,
    CONSTRAINT category_table_name_unique UNIQUE (category_name)
);

CREATE OR REPLACE VIEW vw_transaction_category_status AS
SELECT
    t.expense_id,
    t.transaction_date,
    t.merchant,
    t.description,
    t.amount,
    COALESCE(t.category, 'Uncategorized')::VARCHAR(100) AS category,
    t.category_id,
    tc.category_name,
    CASE
        WHEN t.category_id IS NULL THEN 'UNBRIDGED'
        ELSE 'BRIDGED'
    END AS category_status
FROM transactions AS t
LEFT JOIN transactions_category AS tc
    ON tc.category_id = t.category_id;

CREATE OR REPLACE FUNCTION sync_transaction_category_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.category IS NULL THEN
        NEW.category_id := NULL;
    ELSE
        SELECT tc.category_id
        INTO NEW.category_id
        FROM transactions_category AS tc
        WHERE tc.category_name = NEW.category
        LIMIT 1;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER transactions_category_bridge_trg
BEFORE INSERT OR UPDATE OF category
ON transactions
FOR EACH ROW
EXECUTE FUNCTION sync_transaction_category_id();

CREATE TABLE recurring_expenses (
    recurring_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    merchant VARCHAR(255) NOT NULL,
    description TEXT,
    amount NUMERIC(12,2) NOT NULL 
        CHECK(amount > 0),
    category VARCHAR(100),
    payment_source_id BIGINT NOT NULL,
    contract_start_date DATE NOT NULL,
    contract_end_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL
        CHECK(
            status IN (
                'ACTIVE',
                'COMPLETED',
                'CANCELLED'
            )
        ),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ownder_id BIGINT NOT NULL,
    participant_ids BIGINT[] NOT NULL DEFAULT '{}',

    CONSTRAINT recurring_contract_dates_check
        CHECK(contract_end_date >= contract_start_date),

    CONSTRAINT recurring_payment_source_fk
        FOREIGN KEY(payment_source_id)
        REFERENCES payment_sources(payment_source_id),

    CONSTRAINT recurring_expenses_owner_fk
        FOREIGN KEY (owner_id)
        REFERENCES people (person_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

CREATE TABLE recurring_schedule (
    schedule_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recurring_id BIGINT NOT NULL,
    occurrence_number SMALLINT NOT NULL
        CHECK(occurrence_number >= 1),
    payment_date DATE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT recurring_schedule_recurring_fk
        FOREIGN KEY (recurring_id)
        REFERENCES recurring_expenses(recurring_id),

    CONSTRAINT recurring_schedule_occurrence_unique
        UNIQUE (recurring_id, occurrence_number)
);

CREATE INDEX idx_recurring_schedule_payment_date
    ON recurring_schedule(payment_date)
;

CREATE INDEX idx_recurring_schedule_status
    ON recurring_expenses(status)
;

CREATE OR REPLACE FUNCTION generate_recurring_schedule(
    p_recurring_id BIGINT
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_contract_start_date DATE;
    v_contract_end_date DATE;
    v_occurrence_number SMALLINT := 1;
    v_current_date DATE;
    v_generated_count INTEGER := 0;
BEGIN

    SELECT
        contract_start_date,
        contract_end_date
    INTO
        v_contract_start_date,
        v_contract_end_date
    FROM recurring_expenses
    WHERE recurring_id = p_recurring_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Recurring expense % does not exist',
            p_recurring_id;
    END IF;

    IF v_contract_start_date IS NULL
       OR v_contract_end_date IS NULL THEN
        RAISE EXCEPTION
            'Recurring expense % has NULL contract dates',
            p_recurring_id;
    END IF;

    IF v_contract_end_date < v_contract_start_date THEN
        RAISE EXCEPTION
            'Recurring expense % has an end date before its start date',
            p_recurring_id;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM recurring_schedule
        WHERE recurring_id = p_recurring_id
    ) THEN
        RAISE EXCEPTION
            'Recurring expense % already has generated schedule rows',
            p_recurring_id;
    END IF;

    v_current_date := v_contract_start_date;

    WHILE v_current_date <= v_contract_end_date
    LOOP

        INSERT INTO recurring_schedule (
            recurring_id,
            occurrence_number,
            payment_date
        )
        VALUES (
            p_recurring_id,
            v_occurrence_number,
            v_current_date
        );

        v_generated_count := v_generated_count + 1;
        v_occurrence_number := v_occurrence_number + 1;

        v_current_date :=
            (
                DATE_TRUNC('month', v_current_date)
                + INTERVAL '1 month'
                + (
                    LEAST(
                        EXTRACT(
                            DAY FROM v_contract_start_date
                        )::INTEGER,
                        EXTRACT(
                            DAY FROM (
                                DATE_TRUNC('month', v_current_date)
                                + INTERVAL '2 month - 1 day'
                            )
                        )::INTEGER
                    ) - 1
                ) * INTERVAL '1 day'
            )::DATE;

    END LOOP;

    RETURN v_generated_count;

END;
$$;

CREATE OR REPLACE FUNCTION generate_recurring_transactions(
    p_recurring_id BIGINT
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_merchant VARCHAR(255);
    v_description TEXT;
    v_amount NUMERIC(12,2);
    v_category VARCHAR(100);
    v_payment_source_id BIGINT;
    v_owner_id BIGINT;
    v_participant_ids BIGINT[];
    v_generated_count INTEGER := 0;
    v_schedule RECORD;
BEGIN
    -- Lock the recurring definition while generating transactions.
    SELECT
        merchant,
        description,
        amount,
        category,
        payment_source_id,
        owner_id,
        participant_ids
    INTO
        v_merchant,
        v_description,
        v_amount,
        v_category,
        v_payment_source_id,
        v_owner_id,
        v_participant_ids
    FROM recurring_expenses
    WHERE recurring_id = p_recurring_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Recurring expense % does not exist',
            p_recurring_id;
    END IF;

    IF v_amount <= 0 THEN
        RAISE EXCEPTION
            'Recurring expense % has invalid amount',
            p_recurring_id;
    END IF;

    -- Schedule must already exist.
    IF NOT EXISTS (
        SELECT 1
        FROM recurring_schedule
        WHERE recurring_id = p_recurring_id
    ) THEN
        RAISE EXCEPTION
            'Recurring expense % has no generated schedule',
            p_recurring_id;
    END IF;

    -- Materialize one transaction for each scheduled occurrence.
    FOR v_schedule IN
        SELECT
            schedule_id,
            payment_date
        FROM recurring_schedule
        WHERE recurring_id = p_recurring_id
        ORDER BY occurrence_number
        FOR UPDATE
    LOOP

        INSERT INTO transactions (
            transaction_date,
            merchant,
            description,
            amount,
            category,
            payment_source_id,
            owner_id,
            participant_ids,
            obligation_type
        )
        VALUES (
            v_schedule.payment_date,
            v_merchant,
            v_description,
            v_amount,
            v_category,
            v_payment_source_id,
            v_owner_id,
            v_participant_ids,
            'RECURRING'
        );

        v_generated_count := v_generated_count + 1;
    END LOOP;

    RETURN v_generated_count;
END;
$$;

CREATE OR REPLACE FUNCTION trg_materialize_recurring_expense()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    PERFORM generate_recurring_schedule(NEW.recurring_id);

    PERFORM generate_recurring_transactions(NEW.recurring_id);

    RETURN NEW;

END;
$$;

CREATE TRIGGER recurring_expenses_materialize_trg
AFTER INSERT
ON recurring_expenses
FOR EACH ROW
EXECUTE FUNCTION trg_materialize_recurring_expense();

CREATE OR REPLACE VIEW vw_recurring_expenses AS
SELECT
    re.recurring_id,
    re.merchant,
    re.description,
    re.amount,
    re.category,
    re.payment_source_id,
    re.contract_start_date,
    re.contract_end_date,
    CASE
        WHEN CURRENT_DATE >= re.contract_end_date 
            THEN 'COMPLETED'
        WHEN CURRENT_DATE > re.contract_end_date AND CURRENT_DATE >= DATE_TRUNC('month', re.contract_end_date) - INTERVAL '1 month'
            THEN 'CONTRACT REVIEW'
        ELSE 'ACTIVE'
    END AS status,
    re.created_at
FROM recurring_expenses AS re;

CREATE TABLE people (
    person_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR (20),
    create_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION set_transaction_participants(
    p_expense_id BIGINT,
    p_participant_ids BIGINT[]
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_participant_id BIGINT;
BEGIN
    -- Lock the transaction so the participant update is atomic.
    PERFORM 1
    FROM transactions
    WHERE expense_id = p_expense_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transaction % does not exist', p_expense_id;
    END IF;

    -- Treat NULL as an empty participant set.
    p_participant_ids := COALESCE(p_participant_ids, '{}'::BIGINT[]);

    -- Reject duplicate participant IDs.
    IF EXISTS (
        SELECT 1
        FROM unnest(p_participant_ids) AS p
        GROUP BY p
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'Duplicate participant IDs are not allowed';
    END IF;

    -- Every participant must exist in people.
    FOREACH v_participant_id IN ARRAY p_participant_ids
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM people
            WHERE person_id = v_participant_id
        ) THEN
            RAISE EXCEPTION
                'Participant person_id % does not exist',
                v_participant_id;
        END IF;
    END LOOP;

    -- Replace the participant membership atomically.
    UPDATE transactions
    SET participant_ids = p_participant_ids
    WHERE expense_id = p_expense_id;
END;
$$;

CREATE OR REPLACE VIEW vw_payment_obligation_participants AS
WITH obligation_participants AS (
    SELECT
        po.expense_id,
        po.payment_due,
        po.obligation_type,
        po.plan_id,
        po.installment_number,
        po.payment_amount,
        t.transaction_date,
        t.merchant,
        t.category,
        t.payment_source_id,
        t.owner_id,
        p.person_id AS participant_id,
        p.name AS participant_name,
        COUNT(*) OVER (
            PARTITION BY po.expense_id, po.payment_due
        ) AS participant_count,
        ROW_NUMBER() OVER (
            PARTITION BY po.expense_id, po.payment_due
            ORDER BY p.person_id
        ) AS participant_position
    FROM payment_obligations AS po
    JOIN transactions AS t
        ON t.expense_id = po.expense_id
    CROSS JOIN LATERAL unnest(
        CASE
            WHEN cardinality(t.participant_ids) > 0
                THEN t.participant_ids
            ELSE ARRAY[t.owner_id]::BIGINT[]
        END
    ) AS participant(person_id)
    JOIN people AS p
        ON p.person_id = participant.person_id
)
SELECT
    expense_id,
    payment_due,
    obligation_type,
    plan_id,
    installment_number,
    payment_amount,
    transaction_date,
    merchant,
    category,
    payment_source_id,
    owner_id,
    participant_id,
    participant_name,
    participant_count,
    CASE
        WHEN participant_position < participant_count
            THEN ROUND(
                payment_amount / participant_count,
                2
            )
        ELSE
            payment_amount
            - ROUND(
                payment_amount / participant_count,
                2
            ) * (participant_count - 1)
    END AS allocation_amount
FROM obligation_participants;

CREATE TABLE cash_settlements (
    expense_id BIGINT NOT NULL,
    owner_id BIGINT NOT NULL,
    participant_id BIGINT NOT NULL,

    due_date DATE NOT NULL,
    amount_due NUMERIC(12,2) NOT NULL,

    CONSTRAINT cash_settlements_pkey
        PRIMARY KEY (expense_id, participant_id),

    CONSTRAINT cash_settlements_expense_fk
        FOREIGN KEY (expense_id)
        REFERENCES transactions (expense_id)
        ON DELETE RESTRICT,

    CONSTRAINT cash_settlements_owner_fk
        FOREIGN KEY (owner_id)
        REFERENCES payment_sourcespeople (person_id)
        ON DELETE RESTRICT,

    CONSTRAINT cash_settlements_participant_fk
        FOREIGN KEY (participant_id)
        REFERENCES people (person_id)
        ON DELETE RESTRICT,

    CONSTRAINT cash_settlements_amount_positive
        CHECK (amount_due > 0),

    CONSTRAINT cash_settlements_not_self
        CHECK (owner_id <> participant_id)
);

CREATE INDEX idx_cash_settlements_owner_due_date
    ON payment_sourcescash_settlements (owner_id, due_date);

CREATE INDEX idx_cash_settlements_participant_due_date
    ON payment_sourcescash_settlements (participant_id, due_date);

CREATE OR REPLACE FUNCTION generate_cash_settlements()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    inserted_count INTEGER;
BEGIN
    -- Reject duplicate participant IDs for eligible transactions.
    IF EXISTS (
        SELECT 1
        FROM transactions AS t
        JOIN payment_sources AS ps
            ON ps.payment_source_id = t.payment_source_id
        CROSS JOIN LATERAL unnest(
            CASE
                WHEN cardinality(t.participant_ids) > 0
                    THEN t.participant_ids
                ELSE ARRAY[t.owner_id]
            END
        ) AS p(participant_id)
        WHERE ps.payment_type IN ('CASH', 'E_WALLET')
          AND t.obligation_type = 'NORMAL'
        GROUP BY t.expense_id, p.participant_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Duplicate participant IDs found in eligible transactions';
    END IF;

    -- Reject participant IDs that do not exist in people.
    IF EXISTS (
        SELECT 1
        FROM transactions AS t
        JOIN payment_sources AS ps
            ON ps.payment_source_id = t.payment_source_id
        CROSS JOIN LATERAL unnest(
            CASE
                WHEN cardinality(t.participant_ids) > 0
                    THEN t.participant_ids
                ELSE ARRAY[t.owner_id]
            END
        ) AS p(participant_id)
        LEFT JOIN people AS person
            ON person_id = p.participant_id
        WHERE ps.payment_type IN ('CASH', 'E_WALLET')
          AND t.obligation_type = 'NORMAL'
          AND person.person_id IS NULL
    ) THEN
        RAISE EXCEPTION
            'Unknown participant IDs found in eligible transactions';
    END IF;

    WITH eligible_transactions AS (
        SELECT
            t.expense_id,
            t.owner_id,
            t.transaction_date,
            t.amount,
            t.participant_ids
        FROM transactions AS t
        JOIN payment_sources AS ps
            ON ps.payment_source_id = t.payment_source_id
        WHERE ps.payment_type IN ('CASH', 'E_WALLET')
          AND t.obligation_type = 'NORMAL'
    ),
    expanded_participants AS (
        SELECT
            t.expense_id,
            t.owner_id,
            t.transaction_date,
            t.amount,
            p.participant_id,
            COUNT(*) OVER (
                PARTITION BY t.expense_id
            ) AS participant_count,
            ROW_NUMBER() OVER (
                PARTITION BY t.expense_id
                ORDER BY p.participant_id
            ) AS participant_number
        FROM eligible_transactions AS t
        CROSS JOIN LATERAL unnest(
            CASE
                WHEN cardinality(t.participant_ids) > 0
                    THEN t.participant_ids
                ELSE ARRAY[t.owner_id]
            END
        ) AS p(participant_id)
    ),
    allocations AS (
        SELECT
            expense_id,
            owner_id,
            participant_id,
            transaction_date,
            CASE
                WHEN participant_number = participant_count
                    THEN amount
                         - ROUND(amount / participant_count, 2)
                           * (participant_count - 1)
                ELSE ROUND(amount / participant_count, 2)
            END AS allocation_amount
        FROM expanded_participants
    )
    INSERT INTO payment_sourcescash_settlements (
        expense_id,
        owner_id,
        participant_id,
        due_date,
        amount_due
    )
    SELECT
        expense_id,
        owner_id,
        participant_id,
        (
            transaction_date
            + (
                (
                    5 - EXTRACT(ISODOW FROM transaction_date)::INTEGER + 7
                ) % 7
            )
        )::DATE,
        allocation_amount::NUMERIC(12,2)
    FROM allocations
    WHERE participant_id <> owner_id
      AND allocation_amount > 0
    ON CONFLICT (expense_id, participant_id) DO NOTHING;

    GET DIAGNOSTICS inserted_count = ROW_COUNT;

    RETURN inserted_count;
END;
$$;

CREATE TABLE IF NOT EXISTS payment_sourcescash_statements (
    owner_id BIGINT NOT NULL,
    participant_id BIGINT NOT NULL,
    due_date DATE NOT NULL,

    status VARCHAR(10) NOT NULL DEFAULT 'PENDING',
    paid_at TIMESTAMP WITHOUT TIME ZONE,

    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description VARCHAR(255),

    amount_due NUMERIC(12,2) NOT NULL,

    CONSTRAINT pk_cash_statements
        PRIMARY KEY (owner_id, participant_id, due_date),

    CONSTRAINT fk_cash_statements_owner
        FOREIGN KEY (owner_id)
        REFERENCES payment_sourcespeople(person_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_cash_statements_participant
        FOREIGN KEY (participant_id)
        REFERENCES payment_sourcespeople(person_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_cash_statements_different_people
        CHECK (owner_id <> participant_id),

    CONSTRAINT chk_cash_statements_status
        CHECK (status IN ('PENDING', 'PAID')),

    CONSTRAINT chk_cash_statements_paid_at
        CHECK (
            (status = 'PENDING' AND paid_at IS NULL)
            OR
            (status = 'PAID' AND paid_at IS NOT NULL)
        )
);

CREATE OR REPLACE FUNCTION payment_sourcescreate_cash_statement_for_settlement()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO payment_sourcescash_statements (
        owner_id,
        participant_id,
        due_date,
        description,
        amount_due
    )
    SELECT
        NEW.owner_id,
        NEW.participant_id,
        NEW.due_date,
        'Payment to ' || p.name,
        NEW.amount_due
    FROM payment_sourcespeople AS p
    WHERE p.person_id = NEW.owner_id
    ON CONFLICT (owner_id, participant_id, due_date)
    DO UPDATE SET
        amount_due =
            payment_sourcescash_statements.amount_due + EXCLUDED.amount_due,
        updated_at = CURRENT_TIMESTAMP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_create_cash_statement
AFTER INSERT ON payment_sourcescash_settlements
FOR EACH ROW
EXECUTE FUNCTION payment_sourcescreate_cash_statement_for_settlement();

-- Backfill any statement groups that are missing.
INSERT INTO payment_sourcescash_statements (
    owner_id,
    participant_id,
    due_date,
    description
)
SELECT DISTINCT
    cs.owner_id,
    cs.participant_id,
    cs.due_date,
    'Payment to ' || p.name
FROM payment_sourcescash_settlements AS cs
JOIN payment_sourcespeople AS p
    ON p.person_id = cs.owner_id
ON CONFLICT (owner_id, participant_id, due_date)
DO NOTHING;

CREATE OR REPLACE VIEW payment_sourcesvw_cash_statements AS
SELECT
    cs.owner_id,
    owner.name AS owner_name,
    cs.participant_id,
    participant.name AS participant_name,
    cs.description,
    cs.amount_due,
    cs.due_date,
    cs.status,
    cs.paid_at,
    cs.created_at,
    cs.updated_at
FROM payment_sourcescash_statements AS cs
JOIN payment_sourcespeople AS owner
    ON owner.person_id = cs.owner_id
JOIN payment_sourcespeople AS participant
    ON participant.person_id = cs.participant_id;
