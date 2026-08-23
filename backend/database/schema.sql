-- PostgreSQL Multi-Store Database Schema for Beleka POS

-- Enable UUID extension if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. STORES / BRANCHES TABLE
CREATE TABLE IF NOT EXISTS stores (
    id SERIAL PRIMARY KEY,
    store_code VARCHAR(50) UNIQUE NOT NULL,
    bhf_id VARCHAR(10) DEFAULT '00', -- ZRA DigiTax Branch Code ('00' = HQ, '01' = Branch 1, etc.)
    name VARCHAR(255) NOT NULL,
    address TEXT,
    contact_number VARCHAR(50),
    email VARCHAR(255),
    tax_id VARCHAR(100),
    tpin VARCHAR(100),
    sdc_id VARCHAR(100),
    mrc_no VARCHAR(100),
    currency_symbol VARCHAR(10) DEFAULT 'K',
    branch_name VARCHAR(100),
    business_tax_type VARCHAR(50) DEFAULT 'VAT_STANDARD', -- 'VAT_STANDARD', 'TURNOVER_TAX', 'EXEMPT', 'COMPOSITE'
    digitax_api_key VARCHAR(255),
    digitax_environment VARCHAR(20) DEFAULT 'sandbox', -- 'sandbox', 'production'
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. USERS TABLE (PER STORE / MULTI-STORE ADMIN)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    store_id INT REFERENCES stores(id) ON DELETE CASCADE,
    numeric_id VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'cashier', -- 'admin', 'manager', 'cashier'
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_user_store_numeric UNIQUE (store_id, numeric_id)
);

-- 3. CATEGORIES TABLE
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    store_id INT REFERENCES stores(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    sector VARCHAR(50) DEFAULT 'other',
    icon_path VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. PRODUCTS / INVENTORY TABLE
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    store_id INT REFERENCES stores(id) ON DELETE CASCADE,
    category_id INT REFERENCES categories(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    sku VARCHAR(100) NOT NULL,
    price NUMERIC(12,2) NOT NULL,
    unit_cost NUMERIC(12,2) DEFAULT 0.00,
    stock_level INT DEFAULT 0,
    sizes TEXT[],
    colors TEXT[],
    image_path TEXT,
    is_tax_inclusive BOOLEAN DEFAULT TRUE,
    tax_rate NUMERIC(5,2) DEFAULT 16.00,
    zra_tax_code VARCHAR(10) DEFAULT 'A', -- 'A' (Standard 16%), 'B' (Zero 0%), 'C' (Exempt), 'E' (Non-VAT), 'TOT' (Turnover)
    item_cls_cd VARCHAR(50) DEFAULT '10101501',
    is_archived BOOLEAN DEFAULT FALSE,
    discount_price NUMERIC(12,2),
    discount_start_date TIMESTAMP WITH TIME ZONE,
    discount_end_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_product_store_sku UNIQUE (store_id, sku)
);

-- 5. CUSTOMERS TABLE
CREATE TABLE IF NOT EXISTS customers (
    id SERIAL PRIMARY KEY,
    store_id INT REFERENCES stores(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    phone_number VARCHAR(50) NOT NULL,
    email VARCHAR(255),
    accumulated_points INT DEFAULT 0,
    total_spend NUMERIC(12,2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_customer_store_phone UNIQUE (store_id, phone_number)
);

-- 6. SALE TRANSACTIONS TABLE
CREATE TABLE IF NOT EXISTS sale_transactions (
    id SERIAL PRIMARY KEY,
    transaction_uuid VARCHAR(100) UNIQUE NOT NULL,
    store_id INT REFERENCES stores(id) ON DELETE CASCADE,
    total_amount NUMERIC(12,2) NOT NULL,
    subtotal NUMERIC(12,2) NOT NULL,
    tax_amount NUMERIC(12,2) DEFAULT 0.00,
    discount_amount NUMERIC(12,2) DEFAULT 0.00,
    total_cost NUMERIC(12,2) DEFAULT 0.00,
    gross_profit NUMERIC(12,2) DEFAULT 0.00,
    tendered_amount NUMERIC(12,2) DEFAULT 0.00,
    change_amount NUMERIC(12,2) DEFAULT 0.00,
    payment_method VARCHAR(50) NOT NULL,
    cashier_id VARCHAR(50),
    cashier_name VARCHAR(255),
    terminal_name VARCHAR(100),
    customer_id INT REFERENCES customers(id) ON DELETE SET NULL,
    points_earned INT DEFAULT 0,
    points_redeemed INT DEFAULT 0,
    status VARCHAR(50) DEFAULT 'completed',
    -- ZRA Smart Invoice / DigiTax Compliance Data
    zra_receipt_number VARCHAR(100),
    zra_mark_id VARCHAR(100),
    zra_qr_code TEXT,
    zra_status VARCHAR(50) DEFAULT 'pending',
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_synced BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7. PURCHASE ORDERS TABLE
CREATE TABLE IF NOT EXISTS purchase_orders (
    id SERIAL PRIMARY KEY,
    po_number VARCHAR(100) UNIQUE NOT NULL,
    store_id INT REFERENCES stores(id) ON DELETE CASCADE,
    supplier_name VARCHAR(255) NOT NULL,
    supplier_tpin VARCHAR(100),
    status VARCHAR(50) DEFAULT 'pending', -- 'draft', 'pending', 'approved', 'received'
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    approved_at TIMESTAMP WITH TIME ZONE
);

-- 8. PURCHASE ORDER ITEMS TABLE
CREATE TABLE IF NOT EXISTS purchase_order_items (
    id SERIAL PRIMARY KEY,
    purchase_order_id INT REFERENCES purchase_orders(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id) ON DELETE SET NULL,
    product_name VARCHAR(255) NOT NULL,
    unit_cost NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    quantity_ordered INT NOT NULL DEFAULT 1,
    quantity_received INT DEFAULT 0
);

-- 7. SALE ITEMS TABLE
CREATE TABLE IF NOT EXISTS sale_items (
    id SERIAL PRIMARY KEY,
    sale_transaction_id INT REFERENCES sale_transactions(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id) ON DELETE SET NULL,
    product_name VARCHAR(255) NOT NULL,
    price_at_sale NUMERIC(12,2) NOT NULL,
    unit_cost_at_sale NUMERIC(12,2) DEFAULT 0.00,
    quantity INT NOT NULL DEFAULT 1,
    tax_rate_at_sale NUMERIC(5,2) DEFAULT 0.00,
    is_tax_inclusive_at_sale BOOLEAN DEFAULT TRUE,
    is_refunded BOOLEAN DEFAULT FALSE
);

-- 8. ATTENDANCE LOGS TABLE
CREATE TABLE IF NOT EXISTS attendance_logs (
    id SERIAL PRIMARY KEY,
    store_id INT REFERENCES stores(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE SET NULL,
    username VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL, -- 'clock_in', 'clock_out'
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- INDEXES FOR MULTI-STORE HIGH PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_products_store_sku ON products(store_id, sku);
CREATE INDEX IF NOT EXISTS idx_products_store_archived ON products(store_id, is_archived);
CREATE INDEX IF NOT EXISTS idx_sales_store_timestamp ON sale_transactions(store_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_sales_uuid ON sale_transactions(transaction_uuid);
CREATE INDEX IF NOT EXISTS idx_users_store_numeric ON users(store_id, numeric_id);
CREATE INDEX IF NOT EXISTS idx_customers_store_phone ON customers(store_id, phone_number);

-- DEFAULT INITIAL STORE SEED DATA FOR QUICKSTART
INSERT INTO stores (store_code, name, address, currency_symbol, branch_name)
VALUES ('STORE-001', 'Beleka Main Store', 'Main Mall, Lusaka', 'K', 'Main Branch')
ON CONFLICT (store_code) DO NOTHING;
