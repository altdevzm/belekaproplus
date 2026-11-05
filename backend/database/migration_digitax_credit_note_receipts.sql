-- Keep fiscal credit-note status and receipt details separate from the original sale receipt.
ALTER TABLE sale_transactions
    ADD COLUMN IF NOT EXISTS is_credit_note BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS credit_note_reason TEXT,
    ADD COLUMN IF NOT EXISTS credit_note_status VARCHAR(50) NOT NULL DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS credit_note_receipt_number VARCHAR(100),
    ADD COLUMN IF NOT EXISTS credit_note_mark_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS credit_note_qr_code TEXT;
