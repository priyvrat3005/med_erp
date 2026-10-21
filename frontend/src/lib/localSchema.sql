-- Local (desktop) schema, SQLite + SQLCipher. Migration 1.
-- Money columns are TEXT decimal strings (e.g. '45.50'). Use decimal.js for arithmetic.
-- Quantities are INTEGER base units. IDs are UUID TEXT generated on this device.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS schema_version (
  version    INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Local users (PIN hash = Argon2id, computed in Rust)
CREATE TABLE IF NOT EXISTS users (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  role        TEXT NOT NULL CHECK (role IN ('owner','pharmacist','cashier','accountant')),
  pin_hash    TEXT NOT NULL,
  pharmacist_reg_no TEXT,
  is_active   INTEGER NOT NULL DEFAULT 1,
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until TEXT
);

CREATE TABLE IF NOT EXISTS products (
  id               TEXT PRIMARY KEY,
  name             TEXT NOT NULL,
  generic_name     TEXT,
  manufacturer     TEXT,
  hsn_code         TEXT,
  gst_rate_percent TEXT NOT NULL DEFAULT '0',
  schedule         TEXT NOT NULL DEFAULT 'none' CHECK (schedule IN ('none','H','H1','X')),
  pack_size        INTEGER NOT NULL DEFAULT 1 CHECK (pack_size > 0),
  pack_unit        TEXT NOT NULL DEFAULT 'strip',
  base_unit        TEXT NOT NULL DEFAULT 'tablet',
  barcode          TEXT,
  mrp              TEXT,
  reorder_level    INTEGER NOT NULL DEFAULT 0,
  is_active        INTEGER NOT NULL DEFAULT 1,
  hlc              TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS products_barcode ON products(barcode);
CREATE VIRTUAL TABLE IF NOT EXISTS products_fts USING fts5(name, generic_name, content='products', content_rowid='rowid');

CREATE TABLE IF NOT EXISTS suppliers (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, gstin TEXT, drug_license_no TEXT,
  phone TEXT, address TEXT, state_code TEXT, is_active INTEGER NOT NULL DEFAULT 1, hlc TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY, name TEXT, phone TEXT, gstin TEXT,
  is_active INTEGER NOT NULL DEFAULT 1, hlc TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS customer_consents (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL REFERENCES customers(id),
  purpose TEXT NOT NULL CHECK (purpose IN ('bill_delivery','refill_reminder','marketing')),
  channel TEXT NOT NULL CHECK (channel IN ('whatsapp','sms','email')),
  granted_at TEXT NOT NULL,
  notice_version TEXT NOT NULL,
  captured_how TEXT NOT NULL,
  withdrawn_at TEXT
);

CREATE TABLE IF NOT EXISTS batches (
  id TEXT PRIMARY KEY,
  store_id TEXT NOT NULL,
  product_id TEXT NOT NULL REFERENCES products(id),
  batch_no TEXT NOT NULL,
  expiry_date TEXT NOT NULL,            -- YYYY-MM-DD (last day of printed month)
  mrp TEXT NOT NULL,
  purchase_rate TEXT,
  supplier_id TEXT,
  hlc TEXT NOT NULL,
  UNIQUE (store_id, product_id, batch_no, mrp)
);
CREATE INDEX IF NOT EXISTS batches_fefo ON batches(store_id, product_id, expiry_date);

-- Append-only ledger. Stock = SUM(qty_base). NEVER UPDATE OR DELETE.
CREATE TABLE IF NOT EXISTS stock_movements (
  id TEXT PRIMARY KEY,
  store_id TEXT NOT NULL,
  batch_id TEXT NOT NULL REFERENCES batches(id),
  product_id TEXT NOT NULL REFERENCES products(id),
  movement_type TEXT NOT NULL CHECK (movement_type IN
    ('opening','purchase','sale','sale_return','purchase_return','adjustment','expiry_writeoff','transfer_out','transfer_in')),
  qty_base INTEGER NOT NULL CHECK (qty_base <> 0),
  ref_type TEXT, ref_id TEXT, reason TEXT,
  hlc TEXT NOT NULL,
  occurred_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS stock_movements_batch ON stock_movements(batch_id);

CREATE TRIGGER IF NOT EXISTS stock_movements_no_update BEFORE UPDATE ON stock_movements
BEGIN SELECT RAISE(ABORT, 'stock_movements is append-only'); END;
CREATE TRIGGER IF NOT EXISTS stock_movements_no_delete BEFORE DELETE ON stock_movements
BEGIN SELECT RAISE(ABORT, 'stock_movements is append-only'); END;

CREATE VIEW IF NOT EXISTS stock_levels AS
  SELECT store_id, batch_id, product_id, SUM(qty_base) AS qty_base
  FROM stock_movements GROUP BY store_id, batch_id, product_id;

CREATE TABLE IF NOT EXISTS purchase_invoices (
  id TEXT PRIMARY KEY, store_id TEXT NOT NULL, supplier_id TEXT NOT NULL REFERENCES suppliers(id),
  supplier_invoice_no TEXT NOT NULL, invoice_date TEXT NOT NULL,
  taxable_total TEXT NOT NULL, cgst_total TEXT NOT NULL DEFAULT '0', sgst_total TEXT NOT NULL DEFAULT '0',
  igst_total TEXT NOT NULL DEFAULT '0', round_off TEXT NOT NULL DEFAULT '0', grand_total TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'final', source TEXT NOT NULL DEFAULT 'manual',
  file_path TEXT, hlc TEXT NOT NULL, created_by TEXT,
  UNIQUE (supplier_id, supplier_invoice_no)
);

CREATE TABLE IF NOT EXISTS purchase_invoice_lines (
  id TEXT PRIMARY KEY,
  purchase_invoice_id TEXT NOT NULL REFERENCES purchase_invoices(id),
  product_id TEXT NOT NULL REFERENCES products(id),
  batch_id TEXT NOT NULL REFERENCES batches(id),
  qty_base INTEGER NOT NULL CHECK (qty_base > 0),
  free_qty_base INTEGER NOT NULL DEFAULT 0,
  mrp TEXT NOT NULL, rate TEXT NOT NULL, discount_pct TEXT NOT NULL DEFAULT '0',
  gst_rate TEXT NOT NULL, taxable_value TEXT NOT NULL, tax_amount TEXT NOT NULL, line_total TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sales_invoices (
  id TEXT PRIMARY KEY,
  store_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  series TEXT NOT NULL,
  seq_no INTEGER NOT NULL,
  invoice_no TEXT NOT NULL CHECK (length(invoice_no) <= 16),
  invoice_date TEXT NOT NULL,
  customer_id TEXT REFERENCES customers(id),
  customer_name TEXT,
  buyer_gstin TEXT,
  is_b2b INTEGER NOT NULL DEFAULT 0,
  place_of_supply TEXT NOT NULL,
  subtotal TEXT NOT NULL, discount_total TEXT NOT NULL DEFAULT '0', taxable_total TEXT NOT NULL,
  cgst_total TEXT NOT NULL DEFAULT '0', sgst_total TEXT NOT NULL DEFAULT '0', igst_total TEXT NOT NULL DEFAULT '0',
  round_off TEXT NOT NULL DEFAULT '0', grand_total TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'final' CHECK (status IN ('draft','final','cancelled')),
  cancelled_at TEXT, cancel_reason TEXT,
  hlc TEXT NOT NULL, created_by TEXT,
  UNIQUE (store_id, invoice_no)
);
CREATE INDEX IF NOT EXISTS sales_invoices_date ON sales_invoices(store_id, invoice_date);

CREATE TABLE IF NOT EXISTS sales_invoice_lines (
  id TEXT PRIMARY KEY,
  sales_invoice_id TEXT NOT NULL REFERENCES sales_invoices(id),
  product_id TEXT NOT NULL REFERENCES products(id),
  batch_id TEXT NOT NULL REFERENCES batches(id),
  qty_base INTEGER NOT NULL CHECK (qty_base > 0),
  mrp TEXT NOT NULL, rate TEXT NOT NULL, discount_pct TEXT NOT NULL DEFAULT '0',
  taxable_value TEXT NOT NULL, gst_rate TEXT NOT NULL,
  cgst TEXT NOT NULL DEFAULT '0', sgst TEXT NOT NULL DEFAULT '0', igst TEXT NOT NULL DEFAULT '0',
  line_total TEXT NOT NULL, hsn_code TEXT
);

CREATE TABLE IF NOT EXISTS payments (
  id TEXT PRIMARY KEY,
  sales_invoice_id TEXT NOT NULL REFERENCES sales_invoices(id),
  mode TEXT NOT NULL CHECK (mode IN ('cash','upi','card','credit','other')),
  amount TEXT NOT NULL, reference TEXT
);

CREATE TABLE IF NOT EXISTS prescriptions (
  id TEXT PRIMARY KEY,
  sales_invoice_id TEXT NOT NULL REFERENCES sales_invoices(id),
  doctor_name TEXT NOT NULL, doctor_reg_no TEXT, doctor_address TEXT,
  patient_name TEXT NOT NULL, patient_age INTEGER, patient_address TEXT,
  image_path TEXT
);

CREATE TABLE IF NOT EXISTS h1_register_entries (
  id TEXT PRIMARY KEY,
  store_id TEXT NOT NULL,
  sales_invoice_line_id TEXT NOT NULL REFERENCES sales_invoice_lines(id),
  prescription_id TEXT NOT NULL REFERENCES prescriptions(id),
  entry_date TEXT NOT NULL, drug_name TEXT NOT NULL, batch_no TEXT NOT NULL, qty_base INTEGER NOT NULL
);

-- Sync plumbing
CREATE TABLE IF NOT EXISTS outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL UNIQUE,
  entity TEXT NOT NULL,
  op TEXT NOT NULL CHECK (op IN ('upsert','void')),
  payload TEXT NOT NULL,                 -- JSON, snake_case fields, money as strings
  hlc TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  sent_at TEXT,
  rejected INTEGER NOT NULL DEFAULT 0,
  reject_reason TEXT
);
CREATE INDEX IF NOT EXISTS outbox_pending ON outbox(sent_at, rejected, id);

CREATE TABLE IF NOT EXISTS sync_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS device_counters (
  name TEXT PRIMARY KEY,                -- e.g. 'invoice:AB1/26'
  value INTEGER NOT NULL
);

INSERT OR IGNORE INTO schema_version(version) VALUES (1);
