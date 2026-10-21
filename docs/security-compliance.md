# Security and Compliance

> This is an engineering document, not legal advice. Items marked **[VERIFY]** must be confirmed by a CA, a
> pharmacy-regulatory advisor or privacy counsel before launch.

## 1. Assets and trust boundaries
| Asset | Where | Sensitivity |
|---|---|---|
| Sales and customer data (phones, purchase history) | Local DB, cloud | High (reveals health conditions) |
| Prescriptions (images, patient/doctor details) | Local, S3 | High |
| GST/GSP credentials, WhatsApp tokens | Cloud (encrypted) | Critical |
| Licence tokens, update keys | Cloud/CI | Critical |
| Stock and pricing | Local, cloud | Medium (business-sensitive) |

Boundaries: shop PC <-> internet <-> API; API <-> DB; API <-> third parties (BSP, GSP, LLM, Razorpay).

## 2. Threat model (STRIDE summary)

| Threat | Example | Controls |
|---|---|---|
| Spoofing | Stolen JWT, cloned device | Short-lived access tokens, refresh rotation, device binding with keypair, OTP rate limits, revocation list |
| Tampering | Edited local DB, forged invoices, tampered updates | SQLCipher, immutable ledger, audit hash chain, signed updates, server validation of events |
| Repudiation | Staff denies cancelling bill | Audit log with user + device, permission-gated actions |
| Information disclosure | Cross-tenant read, stolen laptop, log leakage | RLS + composite FKs, per-tenant keys, encrypted disk-at-rest DB, no PII in logs, S3 per-tenant prefixes with SSE-KMS |
| Denial of service | OTP/SMS pumping, sync flood | Rate limits, WAF, per-tenant quotas, idempotency, backpressure |
| Elevation | Cashier edits stock, SQL injection | RBAC enforced server-side and in Rust commands, parameterized SQL only, input validation |

## 3. Desktop security
- **Encrypted DB:** SQLCipher with a random 256-bit key. Key stored via OS-protected storage (Windows DPAPI / Credential Manager), optionally wrapped by a shop passphrase. Never next to the DB file in plain text.
- **App lock:** auto-lock on idle; PIN hashed with Argon2id; limited attempts with backoff.
- **Tauri hardening:** strict CSP, minimal allowlisted commands/capabilities, no remote code loading, no `eval`, no shell access.
- **Updates:** signed update manifests; pinned public key; staged rollout; rollback path.
- **Code signing:** EV certificate for installers to avoid SmartScreen warnings and tampering.
- **Anti-piracy (best effort):** server-validated licence tokens with offline grace period, device binding, integrity checks. Accept some leakage; keep price and UX better than cracked alternatives.
- **Backups:** encrypted local backup folder option + cloud snapshots. Tell users ransomware recovery = cloud restore.
- **Clock tamper:** compare with server time on every sync; limit offline grace.

## 4. Backend security
- **AuthN:** phone OTP (hashed OTP, 5 min expiry, 5 attempts, per-phone and per-IP limits), JWT with asymmetric keys (EdDSA/RS256) + key rotation, refresh token rotation with reuse detection. TOTP/passkeys for owners.
- **AuthZ:** role claims plus server-side checks; deny by default.
- **Tenant isolation:** see `db-schema.md` section 6. App DB role without BYPASSRLS. Automated cross-tenant test on every table.
- **Secrets:** AWS Secrets Manager; no secrets in env files in prod; rotate quarterly.
- **Input handling:** class-validator, size limits, JSON schema versioning, parameterized SQL.
- **Rate limiting:** per IP, per device, per tenant.
- **Dependencies:** Dependabot, `npm audit`, Trivy for containers, SBOM.
- **Logging:** structured, correlation IDs, PII scrubbing. Audit log separate from app logs.
- **Infra:** private subnets for DB/Redis, WAF in front, least-privilege IAM, MFA on cloud console, separate AWS accounts per env, backups tested.
- **Support access:** break-glass with ticket reference, time-boxed, fully audited. No standing prod DB access.

## 5. Third-party and AI risks
| Risk | Control |
|---|---|
| LLM sees personal data | Mask phone/names before calls; contractual no-training and data-processing terms; Indian-region options where available |
| Prompt injection via scanned invoices/prescriptions | Treat extracted text as data, not instructions; fixed schema output; validate; no tool access for extraction model |
| Wrong drug info | No clinical advice features; assistive only; pharmacist confirms |
| WhatsApp/SMS misuse | Send only with consent; per-tenant caps; template-only sends |
| GSP credential theft | Encrypt per-tenant; scoped tokens; rotate; alert on anomalies |

## 6. DPDP Act, 2023 and Rules, 2025
Dates and obligations (verify against the official Rules and counsel):
- DPDP Rules notified 13 Nov 2025. Operational duties (rules 3, 5 to 16) apply after 18 months, around **13 May 2027**.
- Your role: shops are typically the **Data Fiduciary** for their customers' data; you act as a **Data Processor** for them, and a fiduciary for your own users (shop owners/staff). Get this reviewed **[VERIFY]**. Contracts must allocate duties.

Engineering checklist:
- [ ] **Consent ledger** (`customer_consents`): purpose, channel, timestamp, notice version, how captured, withdrawal. Messages blocked without valid consent.
- [ ] **Notice** shown/printed at point of collection in English + regional language **[VERIFY wording]**.
- [ ] **Purpose limitation:** separate purposes (bill delivery vs refill reminders vs marketing).
- [ ] **Data principal rights:** access, correction, erasure, grievance workflow with timelines **[VERIFY]**.
- [ ] **Erasure vs retention:** erase marketing/contact data; retain tax and drug records as legally required, minimized and restricted **[VERIFY periods]**.
- [ ] **Security safeguards:** encryption, access control, logging, backups (this document).
- [ ] **Breach response:** runbook, detection alerts, notification workflow to the Board and affected persons within notified timelines **[VERIFY]**.
- [ ] **Children's data:** if a customer is a minor, consent rules differ **[VERIFY]**; capture age/guardian only where needed.
- [ ] **Data localization/transfer:** host in India; check any cross-border transfer rules before using foreign AI/SMS vendors **[VERIFY]**.
- [ ] **Vendor DPAs** with BSP, SMS, cloud, LLM, payment providers.
- [ ] **Significant Data Fiduciary** assessment if scale grows **[VERIFY]**.

## 7. GST notes (engineering)
- E-invoicing applies to taxpayers above the notified turnover (currently Rs 5 crore) **[VERIFY current notification]**; most retail pharmacies issue B2C bills, so start with accurate GSTR-1/3B data.
- Keep GST rates versioned in `gst_rate_master` and per product; support rate change effective dates.
- Invoice number max 16 characters; allowed characters: letters, digits, `/`, `-` **[VERIFY]**.
- HSN digit requirement depends on turnover and transaction type **[VERIFY]**.
- File through a GSP; never store GST portal passwords in plain text.

## 8. Drugs and Cosmetics rules (engineering)
- Schedules: H, H1, X need a prescription from a registered medical practitioner for retail sale; H1 has register requirements; X has stricter record-keeping **[VERIFY exact fields and retention]**.
- Software should: capture prescriber and patient details, keep an H1 register, show drug licence numbers on bills, block sales of expired batches, track batch/expiry on every line.
- Software should NOT decide legality of a sale; it records and warns. Pharmacist remains responsible.
- Online sale rules for medicines are contested and changing. Do not build e-pharmacy features without regulatory advice **[VERIFY]**.

## 9. Incident response (summary)
1. Detect (alerts, user report) -> 2. Triage severity -> 3. Contain (revoke tokens/devices, rotate keys, isolate tenant) -> 4. Preserve evidence -> 5. Notify (tenants, Board, individuals as required) -> 6. Recover/restore -> 7. Post-mortem within 5 days.

## 10. Security testing schedule
| When | What |
|---|---|
| Every PR | SAST, dependency scan, secret scan, tenant-isolation tests |
| Monthly | Container scans, access review |
| Before pilot and annually | External penetration test (web API + desktop app) |
| Quarterly | Backup restore drill, key rotation drill, incident tabletop |

## 11. Open questions (fill as they come up)
1. Exact retention periods for H1 register, prescriptions, invoices.
2. Whether pharmacy owners count as fiduciary only, or joint with us for some data.
3. Whether storing prescription images is necessary or details-only is enough.
4. Cross-border rules if an LLM provider hosts outside India.
