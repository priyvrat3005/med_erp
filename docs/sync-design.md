# Sync Design (local-first)

## 1. Goals
- Billing works fully offline; sync is background and eventually consistent.
- No lost sales, no double-counted stock, safe retries, safe multi-device.
- Cloud tenant is a faithful mirror and the basis for backup, mobile app and reports.

## 2. Model: event log plus projections
Every local business change creates an **event** in the same SQLite transaction as the data change (outbox pattern).
The server stores events in `sync_events` and **projects** them into relational tables.

```json
{
  "eventId": "uuid-v4-generated-on-device",
  "entity": "stock_movement",
  "op": "upsert",
  "payload": { "...entity fields in snake_case..." },
  "hlc": "0001761038400000-0003-A1"
}
```
- `entity`: `product | supplier | customer | batch | stock_movement | purchase_invoice | sales_invoice | prescription`
- `op`: `upsert | void` (void = logical deletion of master data; transactional docs use reversing entries)
- `tenantId` is NEVER in the payload; the server takes it from the auth token.

## 3. Hybrid Logical Clock (HLC)
Format (fixed width so string comparison = time order):
`<13-digit unix ms>-<4-hex counter>-<device code>` e.g. `1761038400000-0003-A1`.
Rules: on local event, `ms = max(now, lastMs)`; if equal to lastMs, counter++. On receiving remote HLC, advance local clock to `max(local, remote)`.
Reject events with HLC more than 24h ahead of server time (clock tamper / bad clock) and flag the device.

## 4. Conflict rules per entity

| Entity | Rule | Reason |
|---|---|---|
| `stock_movement` | Insert-only, never conflicts. Dedupe by `eventId`/`id`. | Ledger addition is commutative |
| `sales_invoice`, `purchase_invoice` | Insert-only after finalize. Corrections as new reversing docs. | Tax/audit integrity |
| `product`, `supplier`, `customer` | Last-writer-wins by HLC, per row (field-level merge later if needed) | Low-risk master data |
| `batch` | Create-only fields (batch_no, expiry, MRP) immutable; if two devices create the same (store, product, batch_no, MRP) concurrently, server keeps the first and maps the second ID to it (alias table) | Avoid duplicate batches |
| `prescription` | Insert-only | Legal record |
| Invoice numbers | Per-device series, so no collisions | See below |

### Invoice numbers
`<store 2 chars><device 1 char>/<fy 2 digits>/<6-digit counter>` e.g. `AB1/26/000123` (13 chars; limit is 16).
Counter lives in the device's `device_counters` row, incremented in the same transaction as the invoice.
Confirm series rules with your CA (consecutive, unique, allowed characters).

## 5. Protocol

### Push: `POST /v1/sync/push`
Request: `{ "events": [ SyncEvent, ... ] }` (max 500 per call, max 1 MB).
Response:
```json
{ "accepted": ["id1"], "duplicates": ["id2"], "rejected": [{"eventId":"id3","reason":"validation_failed"}] }
```
Server per event, inside ONE transaction with a SAVEPOINT each:
1. Check duplicate by `(tenant_id, event_id)`; if exists mark duplicate.
2. Take next per-tenant sequence via `sync_counters` (row lock serializes pushes per tenant, so seq order = commit order; no skipped cursors).
3. Insert into `sync_events`.
4. Run the projector for the entity. On failure rollback to savepoint and report rejected.

### Pull: `GET /v1/sync/pull?cursor=<seq>&limit=500`
Returns events with `seq > cursor` not originated by the requesting device, plus `nextCursor` and `hasMore`.
Client applies them in ONE local transaction, then stores the cursor.

### Client loop
1. If offline or unauthenticated: stop, show "sync paused" badge.
2. Push unsent outbox rows oldest first. Mark `sent_at` for accepted and duplicates. Keep rejected rows flagged for review.
3. Pull until `hasMore=false`.
4. Sleep 15-30 s (jittered). Exponential backoff on errors up to 10 min.
5. Wake immediately after a bill is saved.

## 6. Initial sync, restore and new device
- **New device (same tenant):** download latest snapshot (SQLite export, encrypted) from S3 if available, then pull events after snapshot cursor.
- **Restore after PC loss:** owner authenticates (OTP), picks store, device is registered, snapshot + events restored, device gets a **new device code** (never reuse old series).
- **Snapshot cadence:** nightly, plus before schema upgrades.

## 7. Schema evolution
- Each event includes `schemaVersion` (add to payload envelope when first change arrives).
- Server projectors accept N and N-1. Clients refuse to push if server requires a newer app (force update screen).
- Local migrations run before any sync.

## 8. Integrity checks
- **Client checksum:** per store daily `SUM(qty_base)` by batch hashed, sent with pull requests.
- **Nightly server reconciliation:** recompute stock from ledger and compare to checksums; open an ops ticket on mismatch.
- **Audit chain:** `audit_log.hash = H(prev_hash || row)` so tampering is detectable.

## 9. Failure modes and handling
| Failure | Handling |
|---|---|
| Push request timed out but server committed | Retry; duplicate by `eventId` is ignored |
| App crash mid-bill | SQLite transaction rolls back; no partial bill |
| Two counters sell the last strip | Both sales sync; stock goes negative; reconciliation alert and adjustment flow |
| Device clock wrong | HLC advances from max seen; extreme skew rejected and flagged |
| Revoked device | Server returns 403 `device_revoked`; app locks sync and asks owner to re-register |
| Large backlog after weeks offline | Batched push, progress UI, rate limiting with 429 + Retry-After |

## 10. Test plan (must exist before pilot)
- Property tests: random interleavings of events from 3 devices converge to the same state.
- Duplicate and out-of-order push tests.
- Kill-process tests during sync apply.
- Soak test with 10k simulated tenants.
