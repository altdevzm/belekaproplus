-- Migration script to add Lenco Payment Gateway columns to PostgreSQL

-- 1. Add Lenco columns to stores table
ALTER TABLE stores 
ADD COLUMN IF NOT EXISTS lenco_api_key VARCHAR(255),
ADD COLUMN IF NOT EXISTS lenco_environment VARCHAR(20) DEFAULT 'sandbox',
ADD COLUMN IF NOT EXISTS lenco_account_id VARCHAR(100),
ADD COLUMN IF NOT EXISTS lenco_enabled BOOLEAN DEFAULT FALSE;

-- 2. Add Lenco columns to sale_transactions table
ALTER TABLE sale_transactions 
ADD COLUMN IF NOT EXISTS lenco_reference VARCHAR(100),
ADD COLUMN IF NOT EXISTS lenco_status VARCHAR(50),
ADD COLUMN IF NOT EXISTS payment_details JSONB;

-- 3. Create index for lenco_reference for fast webhook lookups
CREATE INDEX IF NOT EXISTS idx_sale_transactions_lenco_ref ON sale_transactions(lenco_reference);
