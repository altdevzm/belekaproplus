ALTER TABLE sale_transactions
    ADD COLUMN IF NOT EXISTS external_payment_reference VARCHAR(100),
    ADD COLUMN IF NOT EXISTS external_payment_confirmed_by VARCHAR(255),
    ADD COLUMN IF NOT EXISTS external_payment_confirmed_at TIMESTAMP WITH TIME ZONE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_external_payment_reference
    ON sale_transactions (store_id, external_payment_reference)
    WHERE external_payment_reference IS NOT NULL;
