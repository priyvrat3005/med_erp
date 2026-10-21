import { db, Stmt, SqlParam } from './db';
import { Hlc } from './hlc';

interface OutboxRow { event_id: string; entity: string; op: string; payload: string; hlc: string }

export interface SyncConfig {
  apiBase: string;
  getToken: () => Promise<string>;
  hlc: Hlc;
}

/**
 * Background sync loop skeleton. Implement fully in task T4.4.
 * Rules: push oldest first; mark sent for accepted+duplicates; keep rejected for review;
 * pull until hasMore=false; apply remote events in ONE local transaction; back off on errors.
 */
export class SyncEngine {
  private timer: ReturnType<typeof setTimeout> | null = null;
  private backoffMs = 0;

  constructor(private readonly cfg: SyncConfig) {}

  start() { this.schedule(0); }
  stop() { if (this.timer) clearTimeout(this.timer); }
  wake() { this.schedule(0); }

  private schedule(delay: number) {
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.tick(), delay);
  }

  private async tick() {
    try {
      if (!navigator.onLine) return this.schedule(15_000);
      await this.push();
      await this.pull();
      this.backoffMs = 0;
      this.schedule(15_000 + Math.random() * 15_000);
    } catch {
      this.backoffMs = Math.min(this.backoffMs ? this.backoffMs * 2 : 5_000, 600_000);
      this.schedule(this.backoffMs);
    }
  }

  private async headers() {
    return { 'Content-Type': 'application/json', Authorization: `Bearer ${await this.cfg.getToken()}` };
  }

  private async push() {
    const rows = await db.query<OutboxRow>(
      'SELECT event_id, entity, op, payload, hlc FROM outbox WHERE sent_at IS NULL AND rejected = 0 ORDER BY id LIMIT 200',
    );
    if (!rows.length) return;
    const body = JSON.stringify({
      events: rows.map((r) => ({
        eventId: r.event_id, entity: r.entity, op: r.op, payload: JSON.parse(r.payload), hlc: r.hlc,
      })),
    });
    const res = await fetch(`${this.cfg.apiBase}/v1/sync/push`, { method: 'POST', headers: await this.headers(), body });
    if (!res.ok) throw new Error(`push failed: ${res.status}`);
    const out = (await res.json()) as { accepted: string[]; duplicates: string[]; rejected: { eventId: string; reason: string }[] };
    const done = [...out.accepted, ...out.duplicates];
    const stmts: Stmt[] = [
      ...done.map((id) => ({ sql: "UPDATE outbox SET sent_at = datetime('now') WHERE event_id = ?", params: [id] })),
      ...out.rejected.map((r) => ({ sql: 'UPDATE outbox SET rejected = 1, reject_reason = ? WHERE event_id = ?', params: [r.reason, r.eventId] })),
    ];
    if (stmts.length) await db.tx(stmts);
  }

  private async pull() {
    for (;;) {
      const cur = await db.query<{ value: string }>("SELECT value FROM sync_state WHERE key = 'pull_cursor'");
      const cursor = cur[0]?.value ?? '0';
      const res = await fetch(`${this.cfg.apiBase}/v1/sync/pull?cursor=${cursor}&limit=500`, { headers: await this.headers() });
      if (!res.ok) throw new Error(`pull failed: ${res.status}`);
      const page = (await res.json()) as {
        events: { seq: number; eventId: string; entity: string; op: string; payload: Record<string, unknown>; hlc: string }[];
        nextCursor: number; hasMore: boolean;
      };
      // TODO(T4.4): map each event to local table statements (applyRemoteEvent) and apply atomically.
      const stmts: Stmt[] = page.events.flatMap((e) => { this.cfg.hlc.observe(e.hlc); return applyRemoteEvent(e); });
      stmts.push({ sql: "INSERT INTO sync_state(key, value) VALUES('pull_cursor', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", params: [String(page.nextCursor)] });
      await db.tx(stmts);
      if (!page.hasMore) break;
    }
  }
}

/** Translate a remote event into local SQL. Stock movements are insert-or-ignore (idempotent). */
function applyRemoteEvent(e: { entity: string; op: string; payload: Record<string, unknown> }): Stmt[] {
  const p = e.payload;
  if (e.entity === 'stock_movement') {
    return [{
      sql: `INSERT OR IGNORE INTO stock_movements
            (id, store_id, batch_id, product_id, movement_type, qty_base, ref_type, ref_id, reason, hlc, occurred_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
      params: [p.id, p.store_id, p.batch_id, p.product_id, p.movement_type, p.qty_base,
               p.ref_type ?? null, p.ref_id ?? null, p.reason ?? null, p.hlc ?? '', p.occurred_at] as SqlParam[],
    }];
  }
  // TODO(T4.4): other entities (product LWW, supplier, customer, batch, invoices, prescriptions)
  return [];
}
