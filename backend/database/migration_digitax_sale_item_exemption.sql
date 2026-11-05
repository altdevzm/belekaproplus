-- Preserve the local-only DigiTax exemption on each sale line.
ALTER TABLE sale_items
    ADD COLUMN IF NOT EXISTS is_digitax_exempt BOOLEAN NOT NULL DEFAULT TRUE;
