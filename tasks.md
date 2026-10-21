# Tasks and AI Prompts

Work top to bottom. One task = one AI session = one commit. Start each session with:
> "Read AGENTS.md and the docs listed in this task, then implement the task. Show a plan before coding."

---
## Milestone 0 — Foundations

### T0.1 Repo and CI
**Read:** README.md, AGENTS.md
**Prompt:** Set up GitHub Actions: backend (lint, typecheck, test with Postgres service container, migrations apply on empty DB) and frontend (lint, typecheck, vitest; Rust `cargo check` on windows-latest). Add Dependabot and a secret-scan step.
**Done:** both pipelines green on a dummy PR.

### T0.2 Backend boots
**Read:** backend/README.md, docs/system-design.md
**Prompt:** Install deps, fix any version drift so `npm run start:dev` serves GET /health, `npm run migrate` applies SQL migrations in order and records them in a `schema_migrations` table. Add a migration runner script (`backend/scripts/migrate.ts`).
**Done:** health returns 200; migrations idempotent.

### T0.3 Desktop boots
**Read:** frontend/README.md, docs/security-compliance.md (local encryption)
**Prompt:** Make `npm run tauri dev` work. Verify the Rust commands `db_open`, `db_query`, `db_exec_batch`, `db_run_script` compile. Add a smoke test that creates an encrypted DB, applies `src/lib/localSchema.sql`, and fails to reopen with a wrong key.
**Done:** encrypted DB round-trip test passes.

### T0.4 Key management (desktop)
**Read:** docs/security-compliance.md
**Prompt:** Generate a random 256-bit DB key at first run, protect it with Windows DPAPI (via the `keyring` crate or windows API), and require shop passphrase unlock option. Never write the key in plain text. Add key rotation command.
**Done:** DB unreadable without OS user context; unit test for rotation.

---
## Milestone 1 — Master data and auth (local)

### T1.1 Local migrations runner
**Prompt:** Implement versioned local migrations (table `meta`, `schema_version`). `localSchema.sql` becomes migration 1. Test upgrade path with a fake migration 2.

### T1.2 Users, roles, PIN login (offline)
**Read:** docs/security-compliance.md (RBAC)
**Prompt:** Local users with roles owner/pharmacist/cashier. PIN hashed with Argon2id (Rust side). Role guard hook on the React side and enforcement in Rust commands for sensitive operations (cancel invoice, edit batch, view reports).

### T1.3 Product master screen
**Prompt:** CRUD + import. Fields per `docs/db-schema.md` (schedule, HSN, GST%, pack_size, barcode). Fast search (FTS5) by name/generic/barcode. Every write creates an outbox event.

### T1.4 Suppliers and customers
**Prompt:** CRUD. Customer phone captured with a consent checkbox that writes a `customer_consents` row (purpose: bill_delivery, refill_reminder, marketing) with timestamp and wording version.

---
## Milestone 2 — Purchases and stock ledger

### T2.1 Stock ledger core
**Read:** docs/db-schema.md (stock_movements), docs/sync-design.md
**Prompt:** Implement `StockService` (TS) that only appends movements. Provide `getStock(batchId)`, `getStockByProduct`, FEFO batch selector. Property-based tests: random sequences of purchases/sales/returns never produce negative stock unless explicitly allowed by setting.

### T2.2 Purchase entry
**Prompt:** Purchase invoice form with lines (product, batch, expiry MM/YY, MRP, rate, qty packs, free qty, discount, GST). Creates batches + `purchase` movements in one transaction. Edit = reversal + new entry, never UPDATE.

### T2.3 Expiry and low-stock reports
**Prompt:** Reports: expiring in 30/60/90 days, expired, low stock vs reorder level, dead stock (no sale in N days). CSV export.

---
## Milestone 3 — Billing

### T3.1 Tax engine
**Read:** AGENTS.md rules 9, 13
**Prompt:** Pure TS module `taxEngine` using decimal.js: line-level GST (inclusive MRP pricing), intra/inter-state split from place of supply, rounding rule, round-off line, invoice totals. 100+ unit tests with CA-verified fixtures. No I/O.

### T3.2 Invoice numbering
**Prompt:** Offline-safe series `<store2><device1>/<fy2>/<6 digits>` (max 16 chars) using a local counter row updated in the same transaction as the invoice. Test collision-free across two simulated devices.

### T3.3 Billing screen
**Prompt:** Keyboard-first billing UI: barcode scan, F-keys, FEFO batch auto-pick, loose/strip toggle, discount, payment split, hold/resume bills. Save = invoice + lines + sale movements + payments + outbox events in ONE transaction. Target p95 save < 500 ms.

### T3.4 Schedule H/H1/X flow
**Read:** docs/security-compliance.md (Drugs rules)
**Prompt:** If a line is H/H1/X, require prescription details (doctor name/reg no, patient name/age/address) before finalizing; create `h1_register_entries` for H1. Photo capture optional. Make rules configurable per state.

### T3.5 Returns and cancellations
**Prompt:** Sale return and invoice cancel as reversing movements + credit note numbering. Permission gated + audit logged.

### T3.6 Print and PDF
**Prompt:** 58/80 mm thermal (ESC/POS) and A4 templates, with drug licence numbers, GSTIN, batch, expiry, MRP. PDF generation for sharing.

---
## Milestone 4 — Backend and sync

### T4.1 Auth (cloud)
**Read:** docs/security-compliance.md
**Prompt:** Phone-OTP login with rate limiting and OTP hashing, JWT (asymmetric keys), refresh rotation, device registration (public key), role claims. Replace the dev JWT guard.

### T4.2 Tenant onboarding
**Prompt:** Create tenant, first store, owner user, sync counter row, per-tenant KMS data key in one transaction. Admin API behind internal auth.

### T4.3 Sync server
**Read:** docs/sync-design.md
**Prompt:** Complete `SyncService` projectors for every entity, per-tenant sequence counter, cursor pull, payload size limits, schema versioning. Integration tests incl. duplicate push, out-of-order events, two devices.

### T4.4 Sync client
**Prompt:** Implement `syncEngine.ts`: background loop, exponential backoff, offline detection, HLC, apply remote events in a transaction, bounded batches, progress UI, "sync paused" banner.

### T4.5 Backup and restore
**Prompt:** Nightly encrypted full snapshot + continuous event log. Restore wizard on a new PC from cloud (verify device, download snapshot, replay events). Restore drill documented and automated in CI against a seeded tenant.

### T4.6 Nightly reconciliation job
**Prompt:** Server job recomputes stock from ledger and compares with client-reported checksums; flag mismatches to an ops dashboard.

---
## Milestone 5 — Messaging, DPDP, licensing

### T5.1 Bill delivery (WhatsApp/SMS)
**Prompt:** Outbox-based messaging worker. Only send if a valid consent row exists. DLT-registered SMS templates and WhatsApp approved templates configurable per tenant. Delivery status webhooks.

### T5.2 DPDP toolkit
**Read:** docs/security-compliance.md (DPDP section)
**Prompt:** Consent ledger UI, privacy notice versions, data-subject request flow (access/correct/erase) honoring legal retention for drug and tax records, breach incident runbook + admin tooling. Keep a record of which data classes are retained and for how long.

### T5.3 Licensing
**Prompt:** Subscription + device licence tokens (signed, short-lived, offline grace of N days), clock-tamper checks using server time on each sync.

### T5.4 Owner mobile app (Flutter)
**Prompt:** Read-only dashboards first (sales, stock, expiry, low stock) from cloud; push alerts. Separate repo folder `mobile/` to be added.

---
## Milestone 6 — GST and OCR

### T6.1 GST reports
**Prompt:** GSTR-1 (B2B, B2CL, B2CS, CDNR, HSN summary) and GSTR-3B summary from invoices; validate against CA fixtures.

### T6.2 GSP integration
**Prompt:** Adapter interface `GstProvider` + implementation for chosen GSP; OAuth/credential storage encrypted per tenant; filing status tracking; sandbox tests only until CA sign-off.

### T6.3 E-invoice (eligible tenants)
**Prompt:** IRN generation flow, QR on invoice, cancellation window rules, retry queue. Enabled only if tenant turnover flag set.

### T6.4 Purchase-bill OCR
**Read:** docs/ai-features.md
**Prompt:** Upload photo/PDF → OCR → LLM structured extraction → draft purchase entry with confidence per field → human review screen. Treat extracted text as untrusted (prompt injection). Product matching by name/barcode with suggestions.

---
## Milestone 7 — AI and growth

### T7.1 Forecasting and reorder
**Prompt:** Nightly per-product demand forecast (LightGBM/Prophet), expiry-risk score, reorder suggestions by supplier. Explainable numbers, backtest report.

### T7.2 Voice and NL queries
**Prompt:** Hindi/English query → whitelisted report API calls (no free-form SQL). Evaluate on a set of 100 shopkeeper phrases.

### T7.3 Refill reminders and order page
**Prompt:** Consent-gated refill reminders; public shop order page that creates a draft order in the desktop app.

---
## Milestone 8 — Release readiness
- T8.1 Penetration test + fix list
- T8.2 Installer signing (EV certificate), auto-update with signature verification, staged rollout
- T8.3 Load/chaos tests for sync (10k tenants simulated)
- T8.4 Runbooks: incident, restore, key rotation, DPDP breach notification
- T8.5 Pilot onboarding kit (videos in Hindi + regional languages)
