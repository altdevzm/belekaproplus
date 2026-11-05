-- Require an explicit opt-in for future DigiTax product synchronization.
-- Existing product choices are preserved.
ALTER TABLE products
    ALTER COLUMN is_digitax_sync_enabled SET DEFAULT FALSE;
