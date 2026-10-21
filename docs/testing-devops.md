# Testing, CI/CD and Operations

## 1. Test pyramid

| Level | Backend | Desktop | Tooling |
|---|---|---|---|
| Unit | Services, tax helpers, projectors | Tax engine, stock service, HLC, bill numbering | Jest / Vitest |
| Property-based | Sync convergence, ledger invariants | Stock never negative unless allowed | fast-check |
| Integration | Real Postgres in CI: migrations, RLS, sync endpoints | Tauri commands against encrypted SQLite | Testcontainers, cargo test |
| E2E | API flows with supertest | UI flows (billing, purchase) | Playwright / WebDriver for Tauri |
| Security | Cross-tenant tests on every table, authZ matrix | CSP, command allowlist checks | Custom + ZAP |
| Performance | Sync load (k6) | Bill save latency on low-end VM | k6, benchmarks |
| UAT | | 3 to 10 real shops in parallel run | Checklists |

### Must-have tests (blockers for release)
1. **Tenant isolation:** for every table, tenant A cannot SELECT/INSERT/UPDATE/DELETE tenant B rows.
2. **Ledger invariants:** stock = sum of movements; UPDATE/DELETE on ledger fails.
3. **Tax engine:** CA-verified fixtures: intra-state, inter-state, inclusive MRP, discounts, rounding, returns.
4. **Sync idempotency:** same push twice = one effect; out-of-order pull safe; crash mid-apply safe.
5. **Invoice numbering:** two devices offline for a week never collide.
6. **Restore drill:** new PC restores from cloud and stock matches.
7. **Encryption:** wrong key fails to open DB; plain `sqlite3` cannot read the file.

## 2. CI pipelines (GitHub Actions)

Backend: install, lint, typecheck, unit tests, spin up Postgres service, apply migrations to an empty DB, run integration + RLS tests, build Docker image, scan (Trivy), push to registry on main.
Frontend: install, lint, typecheck, vitest, `cargo check` and `cargo test` on windows-latest, build installer on tags, sign, upload to release bucket.

Shared: secret scanning, dependency review, Dependabot weekly, required reviews, branch protection.

## 3. Environments

| Env | Purpose | Data |
|---|---|---|
| local | Developer | Docker Postgres, seed data |
| dev | Integration | Synthetic |
| staging | Pre-release, pilot rehearsal | Synthetic + anonymized samples |
| prod | Customers | Real, separate AWS account, separate keys |

## 4. Release process (desktop)
1. Merge to main -> nightly build to internal channel.
2. Tag `vX.Y.Z` -> build, sign (EV), notarize checksums, publish to `beta` channel (design partners).
3. After 1 week with no P1 issues -> `stable` at 5%, 25%, 100% staged rollout.
4. Server must support N and N-1 client versions; force-update only for security fixes.
5. Rollback: previous installer re-published to channel; DB migrations are forward-compatible (expand/contract).

## 5. Release process (backend)
Blue/green or rolling on ECS. Migrations: expand -> deploy -> contract in separate releases. Feature flags for risky features.

## 6. Observability
- **Metrics:** request latency, error rate, sync lag, outbox backlog size per device (reported), push/pull rejections, queue depth, OTP sends, message delivery rate.
- **Logs:** structured JSON, correlation ID, no PII.
- **Tracing:** OpenTelemetry on API and workers.
- **Alerts:** sync lag > 5 min p95, 5xx > 1%, DB CPU/connections, failed backups, reconciliation mismatches, OTP spikes.
- **Dashboards:** tenant health (last sync, backlog, app version), ops dashboard for support.

## 7. Backup and DR
- RDS automated backups with point-in-time recovery; Multi-AZ.
- S3 versioning + lifecycle; keep backup copies within India.
- Quarterly full restore drill to a fresh environment with verification script.
- Per-tenant export tool (supports data-subject requests and churn).

## 8. Support and ops tooling
- Remote diagnostics bundle (logs, versions, DB schema version, no PII) the shop can upload.
- Admin console: tenant lookup, device list, force sync, revoke device, licence extension; all actions audited.
- Runbooks in `docs/runbooks/` (create as needed): incident, restore, key rotation, breach notification, GSP outage, WhatsApp template rejection.

## 9. Definition of Done for MVP release candidate
- [ ] 3 shops ran 2 weeks parallel with Excel/legacy; zero unexplained stock variance
- [ ] Bill save p95 < 500 ms on reference low-end PC
- [ ] Installer signed; update flow tested
- [ ] Encrypted DB verified; key handling reviewed
- [ ] CA signed off GST outputs for sample month
- [ ] Regulatory advisor reviewed H1 flow and bill format
- [ ] Backups and restore demonstrated
