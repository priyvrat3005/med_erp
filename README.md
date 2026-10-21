# PharmaOS (working name) — Pharmacy ERP for India

Local-first pharmacy management for Indian medical stores: billing, batch/expiry inventory,
GST, Schedule H/H1/X compliance, and bills sent to customers on WhatsApp/SMS.
Each shop owns its data **on its own PC (encrypted)** and a **tenant-isolated cloud copy** syncs
in the background for backup, mobile access and compliance services.

> Rename "PharmaOS" everywhere (`tauri.conf.json`, `package.json`, docs) once you pick a brand.

## Repository layout

```
pharmacy-erp/
├── README.md              <- you are here
├── plan.md                <- phased development plan, milestones, team, risks
├── tasks.md               <- ordered task list with copy-paste AI prompts
├── AGENTS.md              <- rules every AI coding agent MUST follow in this repo
├── docs/
│   ├── system-design.md   <- architecture, components, diagrams, deployment
│   ├── db-schema.md       <- cloud (Postgres) + local (SQLite) schema explained
│   ├── sync-design.md     <- local-first sync protocol, HLC, conflict rules
│   ├── security-compliance.md <- threat model, DPDP, GST, Drugs & Cosmetics notes
│   ├── ai-features.md     <- AI roadmap, guardrails, prompts
│   └── testing-devops.md  <- test strategy, CI/CD, environments, release
├── backend/               <- NestJS + PostgreSQL cloud API (separate project)
└── frontend/              <- Tauri 2 + React desktop app (separate project)
```

`backend` and `frontend` are independent projects with their own `package.json`, build and CI.
They share only the **API contract** (`backend/openapi.yaml`) and the **sync event format**
(`docs/sync-design.md`).

## Quick start

Prerequisites: Node 20+, Docker, Rust (stable) + Windows build tools for Tauri.

```bash
# 1. Backend
cd backend
cp .env.example .env
docker compose up -d db        # Postgres 16
npm install
npm run migrate                # applies db/migrations/*.sql
npm run start:dev              # http://localhost:3000/health

# 2. Frontend (desktop)
cd ../frontend
npm install
npm run tauri dev
```

## How to build this with AI

1. Open the repo in your AI coding tool (Claude Code, Cursor, etc.).
2. Make sure it reads `AGENTS.md` first (many tools pick it up automatically).
3. Work through `tasks.md` top to bottom, one task per session. Each task has a ready prompt,
   the docs it must read, and a definition of done.
4. Commit after every task. Never batch tasks.

## Status

Scaffold. What was verified when this was generated:

| Check | Result |
|---|---|
| Postgres migrations `001` and `002` apply on an empty DB (tested on in-process PostgreSQL) | Pass |
| RLS: tenant A cannot read or write tenant B rows; no tenant set returns zero rows | Pass |
| Local SQLite schema loads; stock ledger rejects UPDATE | Pass |
| Backend `tsc --noEmit` and Jest | Pass |
| Frontend `tsc --noEmit` and Vitest (HLC, invoice numbers) | Pass |
| Rust/Tauri core (`src-tauri`) compile | **Not verified**, run `cargo check` first (task T0.3) |
| Auth, GST, messaging, billing UI, tax engine, most sync projectors | **Not built**, see `tasks.md` |

The shipped `AuthGuard` is a dev placeholder and must not be deployed.

## Key decisions (summary)

| Topic | Decision |
|---|---|
| Architecture | Local-first desktop (offline works fully) + multi-tenant cloud |
| Desktop | Tauri 2, React + TypeScript, SQLite + SQLCipher |
| Backend | NestJS (TypeScript), PostgreSQL 16 with Row-Level Security |
| Isolation | `tenant_id` on every row + RLS + per-tenant encryption keys |
| Sync | Append-only event log, idempotent push/pull, hybrid logical clocks |
| Stock | Never stored as a number: always derived from `stock_movements` ledger |
| Money | Decimal strings / `numeric`, never floats |
| Region | AWS Mumbai (ap-south-1); data stays in India |
