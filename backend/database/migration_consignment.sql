-- Migration script to add Consignment & Commission support to existing Beleka Pro Plus Cloud databases

-- 1. Create Suppliers table if it does not exist
CREATE TABLE IF NOT EXISTS suppliers (
    id SERIAL PRIMARY KEY,
    store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    tpin VARCHAR(100),
    contact_person VARCHAR(255),
    phone_number VARCHAR(50),
    email VARCHAR(255),
    address TEXT,
    balance NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_purchases NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_supplier_store_name UNIQUE (store_id, name)
);

CREATE INDEX IF NOT EXISTS idx_suppliers_store_id ON suppliers(store_id);

-- 2. Add consignment fields to products table
ALTER TABLE products 
ADD COLUMN IF NOT EXISTS is_consignment BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS consignment_supplier_id INTEGER REFERENCES suppliers(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS consignment_supplier_name VARCHAR(255),
ADD COLUMN IF NOT EXISTS consignment_commission_rate NUMERIC(5, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS consignment_supplier_payout_price NUMERIC(12, 2) DEFAULT 0.00;

-- 3. Add consignment split fields to sale_items table
ALTER TABLE sale_items 
ADD COLUMN IF NOT EXISTS is_consignment BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS supplier_share NUMERIC(15, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS commission_share NUMERIC(15, 2) DEFAULT 0.00;
