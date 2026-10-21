# Development Plan

Assumes kickoff in **November 2026** (Month 1). Adjust dates if you start later.

## 1. Goals

1. Replace paper/Excel/legacy desktop billing in independent Indian chemist shops with a fast,
   offline-first product that costs less than incumbents.
2. Keep each shop's data theirs: encrypted on their PC, mirrored to an isolated cloud tenant.
3. Make compliance (GST, Schedule H/H1/X, DPDP) a built-in feature, not an afterthought.
4. Add AI where it removes real drudgery (purchase-bill entry, expiry/reorder), with a human always confirming.

## 2. Hard deadlines that shape the plan

| Date | Item | Consequence |
|---|---|---|
| 13 May 2027 | DPDP Rules operational duties take effect (security safeguards, consent, breach notification, erasure, etc.) | Consent capture, breach process, erasure/retention logic and encryption must be live **before pilot with real customers** (Month 6) |
| Ongoing | GST rate/notification changes | Rates must be data-driven and updatable without app release |

## 3. Phases and milestones

### Phase 0 — Discovery and setup (Weeks 1–4)
- Interview 30–50 chemists (metro, tier-2, rural). Capture: Windows versions, RAM, printers, internet, what they use today, pain points, willingness to pay.
- Sign up 10 design-partner shops. Hire/consult a pharmacy-regulatory advisor and a CA for GST.
- Decide Tauri vs Electron/.NET based on Windows 7/8 prevalence (default: Tauri, Win 10+).
- Repo, CI, environments, coding standards, AI workflow (this repo).
- **Exit:** survey report, design partners signed, stack confirmed, `tasks.md` T0.* done.

### Phase 1 — Offline MVP (Months 2–5)
Windows desktop app, no cloud required.
- Encrypted local DB, login, roles (owner/pharmacist/cashier)
- Product master, suppliers, customers
- Purchase entry (manual) with batch/expiry/MRP/rates
- Billing: barcode/name search, FEFO batch pick, discounts, GST split (CGST/SGST/IGST), loose/strip sale, returns
- Schedule H/H1/X handling + prescription capture + H1 register
- Stock, expiry and low-stock reports
- Thermal + A4 printing, PDF bill
- GST reports: GSTR-1/3B-ready summaries and CSV/JSON export (no direct filing yet)
- Import from CSV (and a Marg export importer as top priority)
- **Exit:** 3 design partners run a real day of billing offline; <2 s bill save; zero stock mismatches in 2-week parallel run.

### Phase 2 — Cloud, sync, mobile, DPDP controls (Months 4–7, overlaps P1)
- Tenant onboarding, device registration, licensing
- Sync engine (push/pull, HLC, idempotency), encrypted backup/restore
- Owner mobile app (Flutter, Android): daily sales, stock, expiry, low stock
- WhatsApp/SMS bill delivery with customer consent record (DLT + WhatsApp templates)
- DPDP controls: consent ledger, privacy notice, data-subject request tooling (access/erasure), breach runbook, audit log
- Third-party penetration test + fixes
- **Exit (Month 6–7):** pilot with 10 shops on production cloud; RPO ≤ 15 min; restore drill passed; pen-test criticals closed; DPDP checklist signed off by advisor.

### Phase 3 — Compliance automation and OCR (Months 7–10)
- GST filing through a GSP partner (GSTR-1, GSTR-3B), e-invoice/IRN for eligible B2B customers
- Purchase-bill OCR (photo → draft purchase entry → human confirm)
- Multi-device per store, multi-store per tenant, staff permissions
- Razorpay subscriptions, usage metering, support tooling
- **Exit:** paid launch to first 100 shops.

### Phase 4 — AI and growth (Months 10–14)
- Expiry-risk and reorder suggestions (forecasting), dead-stock alerts
- Hindi/regional voice and natural-language queries ("kal ki bikri kitni thi?")
- Customer refill reminders (consented), simple online order page for the shop
- Distributor integrations (price lists, e-orders)
- **Exit:** measurable reduction in expired stock for pilot shops; 500+ paying shops.

### Phase 5 — Scale and certification (Month 14+)
- SOC 2 Type I → ISO 27001, chain/multi-branch features, dedicated-tenant option
- Regional partner/channel program, ABDM/health-ecosystem exploration

## 4. Week-by-week for the first 16 weeks

| Week | Focus | Deliverable |
|---|---|---|
| 1–2 | Interviews, partner signup, regulatory advisor | Interview notes, partner list |
| 3–4 | Repo/CI, local DB layer, backend skeleton, DB migrations | Green CI, `/health`, migrations apply |
| 5–6 | Product/supplier/customer CRUD, auth (local + OTP in cloud) | Master data screens |
| 7–8 | Purchase entry + batch/stock ledger | Stock reports match ledger |
| 9–10 | Billing core (FEFO, GST split, loose sale), invoice numbering | Bills saved offline |
| 11–12 | Printing/PDF, returns, H1 register, prescriptions | Printable compliant bills |
| 13–14 | Reports + CSV/Marg import | Parallel-run in 3 shops |
| 15–16 | Hardening, installer signing, auto-update, feedback fixes | **MVP release candidate** |

## 5. Team (minimum viable)

| Role | Count | Notes |
|---|---|---|
| Tech lead / architect | 1 | Owns sync + security design |
| Desktop/frontend engineer | 2 | Tauri, React, Rust basics |
| Backend engineer | 1–2 | NestJS, Postgres, queues |
| Mobile engineer | 1 (from Phase 2) | Flutter |
| Product + pharmacy domain | 1 | Writes acceptance criteria with shopkeepers |
| QA | 1 (from Phase 1 end) | Plus real-shop UAT |
| Support/onboarding | 1 (from pilot) | Hindi + regional languages |
| Advisors (part-time) | CA (GST), pharmacy-regulatory, privacy counsel | Review before pilot |

Using AI coding agents multiplies throughput but does **not** remove the need for human review of security,
tax logic and sync code. Mandatory human review list: tenant isolation, auth, sync projectors, GST math, encryption.

## 6. Risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Shops won't switch (data migration pain) | High | Marg/CSV importer in MVP; free migration service for first 100 |
| Old Windows PCs | Medium | Survey in Phase 0; fallback shell; keep app lightweight |
| Sync bugs corrupt stock | Medium | Ledger design, property-based tests, nightly reconciliation job, restore drills |
| Software piracy | High | Server-checked licences with offline grace, device binding; price below cracking effort |
| DPDP/Drugs-rule misinterpretation | Medium | Advisor sign-off gates; documented open questions |
| WhatsApp/SMS approval delays | Medium | Start DLT and BSP onboarding in Phase 0 |
| LLM errors in clinical context | Medium | Assistive only, human confirm, no clinical advice features before legal review |
| Support load | High | In-app guided onboarding, remote-assist tool, regional-language help |

## 7. Success metrics

- Time to first bill after install < 30 minutes (with import)
- Bill save latency p95 < 500 ms offline
- Sync success rate > 99.5%, backup freshness < 15 min p95
- Stock reconciliation mismatches = 0 on nightly job
- Weekly active shops / paid conversion after 30-day trial
- Support tickets per shop per month

## 8. Out of scope (for now)

Hospital pharmacy workflows, insurance claims, controlled-drug (narcotics) distribution workflows,
e-pharmacy marketplace, clinical decision support.
