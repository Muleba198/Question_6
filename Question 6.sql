DROP VIEW IF EXISTS v_payroll_report CASCADE;
DROP TABLE IF EXISTS salary_audit, payroll, employees CASCADE;

-- (a) Tables & Seed Data
CREATE TABLE employees (
    employee_id  SERIAL PRIMARY KEY,
    full_name    VARCHAR(120) NOT NULL,
    basic_salary NUMERIC(12, 2) NOT NULL CHECK (basic_salary >= 0),
    allowance    NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (allowance >= 0),
    deduction    NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (deduction >= 0),
    active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE payroll (
    payroll_id  SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employees(employee_id),
    pay_month   DATE NOT NULL CHECK (pay_month = DATE_TRUNC('month', pay_month)::date),
    gross_pay   NUMERIC(12, 2) NOT NULL CHECK (gross_pay >= 0),
    net_pay     NUMERIC(12, 2) NOT NULL CHECK (net_pay >= 0),
    CONSTRAINT uq_payroll_employee_month UNIQUE (employee_id, pay_month)
);

CREATE TABLE salary_audit (
    audit_id    SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employees(employee_id),
    old_salary  NUMERIC(12, 2) NOT NULL CHECK (old_salary >= 0),
    new_salary  NUMERIC(12, 2) NOT NULL CHECK (new_salary >= 0),
    changed_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO employees (full_name, basic_salary, allowance, deduction, active) VALUES
    ('Dr. Musonda Kaluba', 18000.00, 3000.00, 2500.00, TRUE),
    ('Grace Mwamba',       12000.00, 1500.00, 1200.00, TRUE),
    ('Peter Chileshe',      9500.00, 1000.00,  800.00, FALSE);

INSERT INTO payroll (employee_id, pay_month, gross_pay, net_pay) VALUES
    (1, DATE '2026-09-01', 21000.00, 18500.00),
    (2, DATE '2026-09-01', 13500.00, 12300.00),
    (3, DATE '2026-09-01', 10500.00,  9700.00),
    (1, DATE '2026-10-01', 21000.00, 18500.00),
    (2, DATE '2026-10-01', 13500.00, 12300.00);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id INTEGER)
RETURNS NUMERIC(12, 2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_basic     NUMERIC(12, 2);
    v_allowance NUMERIC(12, 2);
    v_deduction NUMERIC(12, 2);
    v_net_pay   NUMERIC(12, 2);
BEGIN
    SELECT basic_salary, allowance, deduction
    INTO v_basic, v_allowance, v_deduction
    FROM employees
    WHERE employee_id = p_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown employee_id: %', p_employee_id;
    END IF;

    v_net_pay := (v_basic + v_allowance) - v_deduction;

    IF v_net_pay < 0 THEN
        RAISE EXCEPTION 'Negative net pay (%) for employee_id %', v_net_pay, p_employee_id;
    END IF;

    RETURN v_net_pay;
END;
$$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    rec     RECORD;
    v_gross NUMERIC(12, 2);
    v_net   NUMERIC(12, 2);
BEGIN
    IF p_month IS NULL OR p_month <> DATE_TRUNC('month', p_month)::date THEN
        RAISE EXCEPTION 'p_month (%) must be the first day of a month', p_month;
    END IF;

    FOR rec IN
        SELECT employee_id, basic_salary, allowance, deduction
        FROM employees
        WHERE active = TRUE
    LOOP
        v_gross := rec.basic_salary + rec.allowance;
        v_net   := fn_net_pay(rec.employee_id);

        INSERT INTO payroll (employee_id, pay_month, gross_pay, net_pay)
        VALUES (rec.employee_id, p_month, v_gross, v_net)
        ON CONFLICT (employee_id, pay_month) DO NOTHING;
    END LOOP;
END;
$$;

CALL pr_process_payroll(DATE '2026-11-01');

-- (d) Trigger
CREATE OR REPLACE FUNCTION fn_log_basic_salary_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.basic_salary IS DISTINCT FROM OLD.basic_salary THEN
        INSERT INTO salary_audit (employee_id, old_salary, new_salary, changed_at)
        VALUES (NEW.employee_id, OLD.basic_salary, NEW.basic_salary, CURRENT_TIMESTAMP);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_employees_basic_salary_audit
AFTER UPDATE OF basic_salary ON employees
FOR EACH ROW
WHEN (OLD.basic_salary IS DISTINCT FROM NEW.basic_salary)
EXECUTE FUNCTION fn_log_basic_salary_change();

-- (e) View
CREATE OR REPLACE VIEW v_payroll_report AS
SELECT
    e.full_name,
    p.pay_month,
    p.gross_pay,
    p.net_pay
FROM payroll p
JOIN employees e ON e.employee_id = p.employee_id;

SELECT * FROM v_payroll_report;

-- (f) Index & EXPLAIN
CREATE INDEX idx_payroll_pay_month
ON payroll (pay_month);

EXPLAIN (ANALYZE, BUFFERS)
SELECT payroll_id, employee_id, pay_month, gross_pay, net_pay
FROM payroll
WHERE pay_month = DATE '2026-10-01';

