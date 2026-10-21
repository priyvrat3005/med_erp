# Desktop App (Tauri 2 + React + TypeScript)

Offline-first Windows app for the pharmacy counter. Data lives in an **encrypted SQLite** file on the shop's PC;
the sync engine mirrors changes to the cloud in the background.

## Run
Prerequisites: Node 20+, Rust stable, Windows: Visual Studio Build Tools (C++), WebView2 runtime.
```bash
npm install
npm run tauri dev
```
Add an app icon at `src-tauri/icons/icon.ico` (use `npx tauri icon your-logo.png`).

## Layout
```
src/
  App.tsx, main.tsx     shell + routes (placeholders)
  pages/                one folder per screen (Billing, Inventory, ...), built task by task
  lib/db.ts             typed wrapper for Rust DB commands
  lib/localSchema.sql   SQLite schema (migration 1)
  lib/hlc.ts            hybrid logical clock
  lib/billNumber.ts     offline-safe invoice numbers
  lib/syncEngine.ts     push/pull loop (skeleton; finish in T4.4)
src-tauri/
  src/main.rs           encrypted DB commands (db_open, db_query, db_exec_batch, db_run_script)
  tauri.conf.json       CSP, bundle (NSIS/MSI)
  capabilities/         permissions: keep minimal
```

## Rules (see ../AGENTS.md)
- Every business write goes through `db.tx([...])` together with its outbox rows.
- Stock is never edited; only `stock_movements` rows are appended.
- Money = decimal strings + `decimal.js`. Never floats.
- Never log customer data. Never store the DB key in plain text (T0.4).

## Known gaps in this scaffold (planned)
- Key management (DPAPI) is not implemented; `db_open` takes the key from the UI. T0.4.
- PIN login, role enforcement in Rust. T1.2.
- Printing, updater, installer signing. T3.6, T8.2.
- Windows 7/8 support is not possible with Tauri/WebView2. Decide in Phase 0.

## Test
```bash
npm test            # vitest: HLC, invoice numbering (add tax engine tests in T3.1)
cd src-tauri && cargo test
```
