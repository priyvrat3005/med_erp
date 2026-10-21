# AGENTS.md — rules for AI coding agents

Read this file fully before writing any code. Also read the docs named in the task you are given.

## Project in one paragraph
Local-first pharmacy ERP for India. Desktop app (`frontend/`, Tauri + React + encrypted SQLite) syncs
to a multi-tenant cloud (`backend/`, NestJS + Postgres with RLS). Pharmacies are tenants; each tenant
may have several stores and devices. Data correctness (stock, tax, drug registers) matters more than speed.

## Non-negotiable rules

### Tenancy and security
1. Every tenant-scoped table has `tenant_id`. Every backend query on such tables MUST run inside
   `DbService.withTenant(tenantId, fn)`. Never call `pool.query` directly for tenant data.
2. `tenant_id` comes from the verified auth token, NEVER from request body/query/payload.
3. Never log phone numbers, names, prescriptions, tokens or keys. Log IDs only.
4. Secrets only via environment/secret manager. Never commit `.env`.
5. Validate all external input (class-validator in backend, zod in frontend).
6. Local SQLite file is always encrypted (SQLCipher). Key is never stored in plain text next to the DB.

### Data integrity
7. Stock is NEVER stored as a mutable number. Only append rows to `stock_movements`; stock = SUM(qty_base).
8. `stock_movements`, `audit_log` and finalized invoices are immutable. Corrections = new reversing rows
   (e.g. sale cancellation posts positive movements), never UPDATE/DELETE.
9. Money is a decimal string in JSON/SQLite and `numeric(14,2)` in Postgres. Use `decimal.js`. No JS floats.
10. Quantities are integers in BASE units (tablet/ml/unit). Pack conversion uses `products.pack_size`.
11. Sell by FEFO (first-expiry-first-out). Never sell an expired batch; warn on near-expiry (configurable).
12. Expiry is stored as the last day of the printed month.
13. GST rates come from data (product / `gst_rate_master`), never hardcoded in code.
14. Invoice numbers: max 16 chars, only A-Z 0-9 `/` `-`, unique per store+series, generated offline per device.

### Sync
15. Every local write that must reach the cloud is written in the SAME SQLite transaction as an `outbox` row.
16. Sync endpoints must be idempotent on `event_id`.
17. Never resolve conflicts by overwriting stock. See `docs/sync-design.md` for per-entity rules.

### Code quality
18. TypeScript strict mode. No `any` without a comment explaining why.
19. Migrations are forward-only SQL files in `backend/db/migrations`. Never edit an applied migration.
20. Every feature ships with tests (unit + at least one integration/e2e for backend routes).
21. Small commits, one task each, message format `T<id>: <summary>`.
22. If a requirement is ambiguous or touches law (GST/Drugs rules/DPDP), STOP and ask instead of guessing.
    Put open legal questions in `docs/security-compliance.md` under "Open questions".

### AI features
23. AI output never auto-commits clinical or financial data. It proposes; a human confirms.
24. Strip personal data before sending anything to an external model. See `docs/ai-features.md`.

## Definition of done (every task)
- Builds and lints clean; tests pass; migrations apply on an empty DB.
- Docs updated if behaviour/schema/API changed.
- No TODOs left without a linked entry in `tasks.md`.
