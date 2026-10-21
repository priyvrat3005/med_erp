-- 001_init.sql : core schema (PostgreSQL 15+)
-- Conventions: see docs/db-schema.md. Money numeric(14,2). Qty = integer base units.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TYPE user_role       AS ENUM ('owner','pharmacist','cashier','accountant');
CREATE TYPE drug_schedule   AS ENUM ('none','H','H1','X');
CREATE TYPE movement_type   AS ENUM ('opening','purchase','sale','sale_return','purchase_return',
                                     'adjustment','expiry_writeoff','transfer_out','transfer_in');
CREATE TYPE doc_status      AS ENUM ('draft','final','cancelled');
CREATE TYPE payment_mode    AS ENUM ('cash','upi','card','credit','other');
CREATE TYPE msg_channel     AS ENUM ('whatsapp','sms','email');
CREATE TYPE msg_status      AS ENUM ('queued','sent','delivered','failed','blocked_no_consent');
CREATE TYPE consent_purpose AS ENUM ('bill_delivery','refill_reminder','marketing');

-- ---------------------------------------------------------------- tenancy
CREATE TABLE tenants (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_name      text NOT NULL,
  trade_name      text,
  gstin           varchar(15),
  pan             varchar(10),
  state_code      char(2) NOT NULL,
  isolation_mode  text NOT NULL DEFAULT 'shared' CHECK (isolation_mode IN ('shared','schema','database')),
  kms_key_id      text,
  status          text NOT NULL DEFAULT 'trial' CHECK (status IN ('trial','active','suspended','closed')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE sync_counters (
  tenant_id uuid PRIMARY KEY REFERENCES tenants(id),
  last_seq  bigint NOT NULL DEFAULT 0
);

CREATE TABLE stores (
  id            uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id),
  code          varchar(2) NOT NULL,            -- used in invoice series
  name          text NOT NULL,
  address       text,
  state_code    char(2) NOT NULL,
  gstin         varchar(15),
  drug_licenses jsonb NOT NULL DEFAULT '[]',    -- [{type:"20", no:"..."},{type:"21", no:"..."}]
  phone         text,
  timezone      text NOT NULL DEFAULT 'Asia/Kolkata',
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, code)
);

CREATE TABLE users (
  id                 uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id),
  phone_e164         text NOT NULL,
  name               text NOT NULL,
  role               user_role NOT NULL,
  pharmacist_reg_no  text,
  totp_secret_enc    bytea,
  is_active          boolean NOT NULL DEFAULT true,
  last_login_at      timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, phone_e164)
);

CREATE TABLE user_store_access (
  tenant_id uuid NOT NULL,
  user_id   uuid NOT NULL,
  store_id  uuid NOT NULL,
  PRIMARY KEY (tenant_id, user_id, store_id),
  FOREIGN KEY (tenant_id, user_id)  REFERENCES users(tenant_id, id),
  FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id)
);

CREATE TABLE devices (
  id                  uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id),
  store_id            uuid NOT NULL,
  code                varchar(1) NOT NULL,      -- used in invoice series; never reused
  label               text,
  public_key          text NOT NULL,
  os                  text,
  app_version         text,
  last_seen_at        timestamptz,
  last_pull_seq       bigint NOT NULL DEFAULT 0,
  license_expires_at  timestamptz,
  revoked_at          timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, store_id, code),
  FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id)
);

CREATE TABLE subscriptions (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id),
  plan               text NOT NULL,
  device_limit       int NOT NULL DEFAULT 1,
  status             text NOT NULL,
  current_period_end timestamptz,
  razorpay_sub_id    text,
  created_at         timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- global reference (no tenant_id)
CREATE TABLE gst_rate_master (
  id             bigserial PRIMARY KEY,
  hsn_prefix     text NOT NULL,            -- e.g. '3004'
  rate_percent   numeric(5,2) NOT NULL,
  effective_from date NOT NULL,
  effective_to   date,
  notification   text,
  UNIQUE (hsn_prefix, effective_from)
);

-- ---------------------------------------------------------------- catalog
CREATE TABLE products (
  id               uuid NOT NULL,                       -- client-generated
  tenant_id        uuid NOT NULL REFERENCES tenants(id),
  name             text NOT NULL,
  generic_name     text,
  manufacturer     text,
  hsn_code         varchar(8),
  gst_rate_percent numeric(5,2) NOT NULL DEFAULT 12.00, -- overwritten by data; never hardcode in code
  schedule         drug_schedule NOT NULL DEFAULT 'none',
  dosage_form      text,
  pack_size        int NOT NULL DEFAULT 1 CHECK (pack_size > 0),   -- base units per pack
  pack_unit        text NOT NULL DEFAULT 'strip',
  base_unit        text NOT NULL DEFAULT 'tablet',
  barcode          text,
  mrp              numeric(12,2),
  reorder_level    int NOT NULL DEFAULT 0,
  is_active        boolean NOT NULL DEFAULT true,
  hlc              text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id)
);
CREATE INDEX products_name_trgm ON products USING gin (lower(name) gin_trgm_ops);
CREATE INDEX products_barcode ON products (tenant_id, barcode) WHERE barcode IS NOT NULL;

CREATE TABLE suppliers (
  id         uuid NOT NULL,
  tenant_id  uuid NOT NULL REFERENCES tenants(id),
  name       text NOT NULL,
  gstin      varchar(15),
  drug_license_no text,
  phone      text,
  address    text,
  state_code char(2),
  is_active  boolean NOT NULL DEFAULT true,
  hlc        text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id)
);

CREATE TABLE customers (
  id          uuid NOT NULL,
  tenant_id   uuid NOT NULL REFERENCES tenants(id),
  name        text,
  phone_hash  bytea,           -- HMAC-SHA256 with tenant key, for lookup
  phone_enc   bytea,           -- application-level encryption with tenant data key
  gstin       varchar(15),     -- for B2B buyers
  is_active   boolean NOT NULL DEFAULT true,
  hlc         text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id)
);
CREATE INDEX customers_phone_hash ON customers (tenant_id, phone_hash);

CREATE TABLE customer_consents (
  id             uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id),
  customer_id    uuid NOT NULL,
  purpose        consent_purpose NOT NULL,
  channel        msg_channel NOT NULL,
  granted_at     timestamptz NOT NULL,
  notice_version text NOT NULL,
  captured_how   text NOT NULL,          -- 'counter_checkbox','otp','paper_scan'
  withdrawn_at   timestamptz,
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, customer_id) REFERENCES customers(tenant_id, id)
);

CREATE TABLE batches (
  id            uuid NOT NULL,
  tenant_id     uuid NOT NULL REFERENCES tenants(id),
  store_id      uuid NOT NULL,
  product_id    uuid NOT NULL,
  batch_no      text NOT NULL,
  expiry_date   date NOT NULL,           -- last day of printed month
  mrp           numeric(12,2) NOT NULL,
  purchase_rate numeric(12,4),
  supplier_id   uuid,
  hlc           text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, store_id, product_id, batch_no, mrp),
  FOREIGN KEY (tenant_id, store_id)   REFERENCES stores(tenant_id, id),
  FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id)
);
CREATE INDEX batches_fefo ON batches (tenant_id, store_id, product_id, expiry_date);

-- ---------------------------------------------------------------- stock ledger (append-only)
CREATE TABLE stock_movements (
  id            uuid NOT NULL,           -- client-generated
  tenant_id     uuid NOT NULL REFERENCES tenants(id),
  store_id      uuid NOT NULL,
  batch_id      uuid NOT NULL,
  product_id    uuid NOT NULL,
  movement_type movement_type NOT NULL,
  qty_base      integer NOT NULL CHECK (qty_base <> 0),   -- signed
  ref_type      text,                    -- 'sales_invoice','purchase_invoice','adjustment'...
  ref_id        uuid,
  reason        text,
  device_id     uuid,
  hlc           text NOT NULL,
  occurred_at   timestamptz NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, store_id)   REFERENCES stores(tenant_id, id),
  FOREIGN KEY (tenant_id, batch_id)   REFERENCES batches(tenant_id, id),
  FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id)
);
CREATE INDEX stock_movements_batch ON stock_movements (tenant_id, store_id, batch_id);

CREATE VIEW stock_levels WITH (security_invoker = true) AS
  SELECT tenant_id, store_id, batch_id, product_id, SUM(qty_base)::bigint AS qty_base
  FROM stock_movements
  GROUP BY tenant_id, store_id, batch_id, product_id;

-- ---------------------------------------------------------------- purchases
CREATE TABLE purchase_invoices (
  id                   uuid NOT NULL,
  tenant_id            uuid NOT NULL REFERENCES tenants(id),
  store_id             uuid NOT NULL,
  supplier_id          uuid NOT NULL,
  supplier_invoice_no  text NOT NULL,
  invoice_date         date NOT NULL,
  taxable_total        numeric(14,2) NOT NULL,
  cgst_total           numeric(14,2) NOT NULL DEFAULT 0,
  sgst_total           numeric(14,2) NOT NULL DEFAULT 0,
  igst_total           numeric(14,2) NOT NULL DEFAULT 0,
  round_off            numeric(6,2)  NOT NULL DEFAULT 0,
  grand_total          numeric(14,2) NOT NULL,
  status               doc_status NOT NULL DEFAULT 'final',
  source               text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','ocr','import')),
  file_key             text,
  device_id            uuid,
  hlc                  text NOT NULL,
  created_by           uuid,
  created_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, supplier_id, supplier_invoice_no),
  FOREIGN KEY (tenant_id, store_id)    REFERENCES stores(tenant_id, id),
  FOREIGN KEY (tenant_id, supplier_id) REFERENCES suppliers(tenant_id, id)
);

CREATE TABLE purchase_invoice_lines (
  id                   uuid NOT NULL,
  tenant_id            uuid NOT NULL REFERENCES tenants(id),
  purchase_invoice_id  uuid NOT NULL,
  product_id           uuid NOT NULL,
  batch_id             uuid NOT NULL,
  qty_base             integer NOT NULL CHECK (qty_base > 0),
  free_qty_base        integer NOT NULL DEFAULT 0 CHECK (free_qty_base >= 0),
  mrp                  numeric(12,2) NOT NULL,
  rate                 numeric(12,4) NOT NULL,
  discount_pct         numeric(5,2) NOT NULL DEFAULT 0,
  gst_rate             numeric(5,2) NOT NULL,
  taxable_value        numeric(14,2) NOT NULL,
  tax_amount           numeric(14,2) NOT NULL,
  line_total           numeric(14,2) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, purchase_invoice_id) REFERENCES purchase_invoices(tenant_id, id),
  FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id),
  FOREIGN KEY (tenant_id, batch_id)   REFERENCES batches(tenant_id, id)
);

-- ---------------------------------------------------------------- sales
CREATE TABLE sales_invoices (
  id                  uuid NOT NULL,
  tenant_id           uuid NOT NULL REFERENCES tenants(id),
  store_id            uuid NOT NULL,
  device_id           uuid NOT NULL,
  series              text NOT NULL,                       -- e.g. 'AB1/26/'
  seq_no              integer NOT NULL,
  invoice_no          varchar(16) NOT NULL CHECK (invoice_no ~ '^[A-Za-z0-9/-]{1,16}$'),
  invoice_date        timestamptz NOT NULL,
  customer_id         uuid,
  customer_name       text,
  buyer_gstin         varchar(15),
  is_b2b              boolean NOT NULL DEFAULT false,
  place_of_supply     char(2) NOT NULL,
  subtotal            numeric(14,2) NOT NULL,
  discount_total      numeric(14,2) NOT NULL DEFAULT 0,
  taxable_total       numeric(14,2) NOT NULL,
  cgst_total          numeric(14,2) NOT NULL DEFAULT 0,
  sgst_total          numeric(14,2) NOT NULL DEFAULT 0,
  igst_total          numeric(14,2) NOT NULL DEFAULT 0,
  round_off           numeric(6,2)  NOT NULL DEFAULT 0,
  grand_total         numeric(14,2) NOT NULL,
  status              doc_status NOT NULL DEFAULT 'final',
  cancelled_at        timestamptz,
  cancel_reason       text,
  hlc                 text NOT NULL,
  created_by          uuid,
  created_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, store_id, invoice_no),
  FOREIGN KEY (tenant_id, store_id)    REFERENCES stores(tenant_id, id),
  FOREIGN KEY (tenant_id, customer_id) REFERENCES customers(tenant_id, id)
);
CREATE INDEX sales_invoices_date ON sales_invoices (tenant_id, store_id, invoice_date);

CREATE TABLE sales_invoice_lines (
  id                uuid NOT NULL,
  tenant_id         uuid NOT NULL REFERENCES tenants(id),
  sales_invoice_id  uuid NOT NULL,
  product_id        uuid NOT NULL,
  batch_id          uuid NOT NULL,
  qty_base          integer NOT NULL CHECK (qty_base > 0),
  mrp               numeric(12,2) NOT NULL,
  rate              numeric(12,4) NOT NULL,
  discount_pct      numeric(5,2) NOT NULL DEFAULT 0,
  taxable_value     numeric(14,2) NOT NULL,
  gst_rate          numeric(5,2) NOT NULL,
  cgst              numeric(14,2) NOT NULL DEFAULT 0,
  sgst              numeric(14,2) NOT NULL DEFAULT 0,
  igst              numeric(14,2) NOT NULL DEFAULT 0,
  line_total        numeric(14,2) NOT NULL,
  hsn_code          varchar(8),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, sales_invoice_id) REFERENCES sales_invoices(tenant_id, id),
  FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id),
  FOREIGN KEY (tenant_id, batch_id)   REFERENCES batches(tenant_id, id)
);

CREATE TABLE payments (
  id                uuid NOT NULL,
  tenant_id         uuid NOT NULL REFERENCES tenants(id),
  sales_invoice_id  uuid NOT NULL,
  mode              payment_mode NOT NULL,
  amount            numeric(14,2) NOT NULL CHECK (amount > 0),
  reference         text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, sales_invoice_id) REFERENCES sales_invoices(tenant_id, id)
);

-- ---------------------------------------------------------------- drug compliance
CREATE TABLE prescriptions (
  id                uuid NOT NULL,
  tenant_id         uuid NOT NULL REFERENCES tenants(id),
  sales_invoice_id  uuid NOT NULL,
  doctor_name       text NOT NULL,
  doctor_reg_no     text,
  doctor_address    text,
  patient_name      text NOT NULL,
  patient_age       int,
  patient_address   text,
  image_key         text,                     -- S3 key, encrypted object
  created_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, sales_invoice_id) REFERENCES sales_invoices(tenant_id, id)
);

CREATE TABLE h1_register_entries (
  id                     uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id              uuid NOT NULL REFERENCES tenants(id),
  store_id               uuid NOT NULL,
  sales_invoice_line_id  uuid NOT NULL,
  prescription_id        uuid NOT NULL,
  entry_date             date NOT NULL,
  drug_name              text NOT NULL,
  batch_no               text NOT NULL,
  qty_base               integer NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id),
  FOREIGN KEY (tenant_id, sales_invoice_line_id) REFERENCES sales_invoice_lines(tenant_id, id),
  FOREIGN KEY (tenant_id, prescription_id) REFERENCES prescriptions(tenant_id, id)
);

-- ---------------------------------------------------------------- GST
CREATE TABLE gst_returns (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id),
  store_id      uuid NOT NULL,
  return_type   text NOT NULL CHECK (return_type IN ('GSTR1','GSTR3B')),
  period        char(6) NOT NULL,                  -- MMYYYY
  status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','ready','submitted','filed','error')),
  payload_key   text,
  arn           text,
  filed_at      timestamptz,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, store_id, return_type, period),
  FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id)
);

CREATE TABLE e_invoices (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES tenants(id),
  sales_invoice_id  uuid NOT NULL,
  irn               varchar(64),
  ack_no            text,
  ack_date          timestamptz,
  signed_qr_key     text,
  status            text NOT NULL DEFAULT 'pending',
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, sales_invoice_id),
  FOREIGN KEY (tenant_id, sales_invoice_id) REFERENCES sales_invoices(tenant_id, id)
);

-- ---------------------------------------------------------------- messaging
CREATE TABLE outbox_messages (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL REFERENCES tenants(id),
  customer_id          uuid,
  channel              msg_channel NOT NULL,
  template             text NOT NULL,
  to_enc               bytea NOT NULL,
  payload              jsonb NOT NULL DEFAULT '{}',
  status               msg_status NOT NULL DEFAULT 'queued',
  provider_message_id  text,
  attempts             int NOT NULL DEFAULT 0,
  last_error           text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  sent_at              timestamptz
);
CREATE INDEX outbox_messages_status ON outbox_messages (tenant_id, status, created_at);

-- ---------------------------------------------------------------- sync + audit + ops
CREATE TABLE sync_events (
  seq          bigint NOT NULL,
  tenant_id    uuid NOT NULL REFERENCES tenants(id),
  event_id     uuid NOT NULL,
  device_id    uuid NOT NULL,
  entity       text NOT NULL,
  op           text NOT NULL CHECK (op IN ('upsert','void')),
  payload      jsonb NOT NULL,
  hlc          text NOT NULL,
  received_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, seq),
  UNIQUE (tenant_id, event_id)
);

CREATE TABLE audit_log (
  id             bigserial PRIMARY KEY,
  tenant_id      uuid NOT NULL REFERENCES tenants(id),
  actor_user_id  uuid,
  device_id      uuid,
  action         text NOT NULL,
  entity         text,
  entity_id      uuid,
  before         jsonb,
  after          jsonb,
  ip             inet,
  prev_hash      bytea,
  hash           bytea,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_log_tenant_time ON audit_log (tenant_id, created_at);

CREATE TABLE backup_snapshots (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id),
  store_id    uuid,
  device_id   uuid,
  object_key  text NOT NULL,
  size_bytes  bigint,
  sha256      text,
  last_seq    bigint,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ai_jobs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id),
  kind        text NOT NULL,                     -- 'purchase_ocr','forecast',...
  status      text NOT NULL DEFAULT 'queued',
  input_key   text,
  output      jsonb,
  model       text,
  cost_paise  integer,
  created_at  timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);
