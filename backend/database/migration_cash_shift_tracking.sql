ALTER TABLE sale_transactions
    ADD COLUMN IF NOT EXISTS cash_shift_number VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_sales_cash_shift_number
    ON sale_transactions (cash_shift_number);
