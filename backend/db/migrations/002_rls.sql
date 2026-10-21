-- 002_rls.sql : Row-Level Security + immutability + runtime role grants
-- Run as the table OWNER (migration role). The app connects as pharmacy_app (no BYPASSRLS).

-- Runtime role (set a real password out-of-band; never commit it)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pharmacy_app') THEN
    CREATE ROLE pharmacy_app LOGIN PASSWORD 'change-me-in-secret-manager' NOBYPASSRLS;
  END IF;
END $$;

GRANT USAGE ON SCHEMA public TO pharmacy_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO pharmacy_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO pharmacy_app;

-- RLS on every table that has tenant_id
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
    WHERE c.table_schema = 'public' AND c.column_name = 'tenant_id'
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.table_name);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', r.table_name);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', r.table_name);
    EXECUTE format($f$
      CREATE POLICY tenant_isolation ON public.%I
        USING      (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
    $f$, r.table_name);
  END LOOP;
END $$;

-- tenants table: the row's own id is the tenant
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON tenants;
CREATE POLICY tenant_isolation ON tenants
  USING      (id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
  WITH CHECK (id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

-- gst_rate_master is global reference data: read-only for the app
REVOKE INSERT, UPDATE, DELETE ON gst_rate_master FROM pharmacy_app;

-- Immutability for ledger and audit log
CREATE OR REPLACE FUNCTION forbid_update_delete() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE = 'restrict_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stock_movements_immutable
  BEFORE UPDATE OR DELETE ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION forbid_update_delete();

CREATE TRIGGER audit_log_immutable
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION forbid_update_delete();

CREATE TRIGGER sync_events_immutable
  BEFORE UPDATE OR DELETE ON sync_events
  FOR EACH ROW EXECUTE FUNCTION forbid_update_delete();

-- Finalized invoices: only status/cancel fields may change
CREATE OR REPLACE FUNCTION sales_invoice_guard() RETURNS trigger AS $$
BEGIN
  IF OLD.status = 'final' AND (
       NEW.invoice_no <> OLD.invoice_no OR NEW.grand_total <> OLD.grand_total OR
       NEW.taxable_total <> OLD.taxable_total OR NEW.invoice_date <> OLD.invoice_date) THEN
    RAISE EXCEPTION 'finalized invoice is immutable' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sales_invoices_guard
  BEFORE UPDATE ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION sales_invoice_guard();

-- Seed example GST master rows: PLACEHOLDERS ONLY. Replace with CA-verified, notified data.
-- INSERT INTO gst_rate_master (hsn_prefix, rate_percent, effective_from, notification) VALUES
--   ('3004', 5.00, DATE '2025-09-22', 'VERIFY with CA');
