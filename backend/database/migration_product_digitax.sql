-- Migration script to add DigiTax package unit code and sync fields to products table

ALTER TABLE products 
ADD COLUMN IF NOT EXISTS package_unit_code VARCHAR(20) DEFAULT 'CT',
ADD COLUMN IF NOT EXISTS unit_of_measure VARCHAR(50) DEFAULT 'kg',
ADD COLUMN IF NOT EXISTS is_digitax_sync_enabled BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS is_synced_with_digitax BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS branch_code VARCHAR(50) DEFAULT '00';

CREATE INDEX IF NOT EXISTS idx_products_branch_code ON products(branch_code);
CREATE INDEX IF NOT EXISTS idx_products_digitax_sync ON products(is_synced_with_digitax);
