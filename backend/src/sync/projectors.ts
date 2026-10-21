import { PoolClient } from 'pg';
import { SyncEventDto, SyncEntity } from './sync.dto';

export interface ProjectorContext {
  tenantId: string;
  deviceId: string;
}

export class ProjectionError extends Error {
  constructor(public readonly reason: string) {
    super(reason);
  }
}

type Projector = (c: PoolClient, ctx: ProjectorContext, ev: SyncEventDto) => Promise<void>;

const str = (v: unknown, name: string): string => {
  if (typeof v !== 'string' || v.length === 0) throw new ProjectionError(`invalid_${name}`);
  return v;
};
const int = (v: unknown, name: string): number => {
  if (typeof v !== 'number' || !Number.isInteger(v)) throw new ProjectionError(`invalid_${name}`);
  return v;
};

/**
 * Product: last-writer-wins by HLC (string compare works because HLC is fixed-width).
 * tenant_id ALWAYS comes from ctx (auth token), never from payload.
 */
const product: Projector = async (c, ctx, ev) => {
  const p = ev.payload;
  await c.query(
    `INSERT INTO products (id, tenant_id, name, generic_name, manufacturer, hsn_code, gst_rate_percent,
                           schedule, pack_size, barcode, mrp, is_active, hlc)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
     ON CONFLICT (id) DO UPDATE SET
       name = EXCLUDED.name, generic_name = EXCLUDED.generic_name, manufacturer = EXCLUDED.manufacturer,
       hsn_code = EXCLUDED.hsn_code, gst_rate_percent = EXCLUDED.gst_rate_percent,
       schedule = EXCLUDED.schedule, pack_size = EXCLUDED.pack_size, barcode = EXCLUDED.barcode,
       mrp = EXCLUDED.mrp, is_active = EXCLUDED.is_active, hlc = EXCLUDED.hlc, updated_at = now()
     WHERE products.tenant_id = EXCLUDED.tenant_id AND products.hlc < EXCLUDED.hlc`,
    [
      str(p.id, 'id'), ctx.tenantId, str(p.name, 'name'), p.generic_name ?? null, p.manufacturer ?? null,
      p.hsn_code ?? null, p.gst_rate_percent ?? '0', p.schedule ?? 'none', int(p.pack_size ?? 1, 'pack_size'),
      p.barcode ?? null, p.mrp ?? null, ev.op === 'void' ? false : (p.is_active ?? true), ev.hlc,
    ],
  );
};

/** Stock movement: insert-only; duplicates are ignored by PK. */
const stockMovement: Projector = async (c, ctx, ev) => {
  if (ev.op !== 'upsert') throw new ProjectionError('ledger_is_append_only');
  const p = ev.payload;
  const qty = int(p.qty_base, 'qty_base');
  if (qty === 0) throw new ProjectionError('invalid_qty_base');
  await c.query(
    `INSERT INTO stock_movements (id, tenant_id, store_id, batch_id, product_id, movement_type, qty_base,
                                  ref_type, ref_id, reason, device_id, hlc, occurred_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
     ON CONFLICT (id) DO NOTHING`,
    [
      str(p.id, 'id'), ctx.tenantId, str(p.store_id, 'store_id'), str(p.batch_id, 'batch_id'),
      str(p.product_id, 'product_id'), str(p.movement_type, 'movement_type'), qty,
      p.ref_type ?? null, p.ref_id ?? null, p.reason ?? null, ctx.deviceId, ev.hlc,
      str(p.occurred_at, 'occurred_at'),
    ],
  );
};

/** Entities not yet projected are stored in sync_events only (see tasks T4.3). */
const pending: Projector = async () => undefined;

export const PROJECTORS: Record<SyncEntity, Projector> = {
  product,
  stock_movement: stockMovement,
  supplier: pending,
  customer: pending,
  batch: pending,
  purchase_invoice: pending,
  sales_invoice: pending,
  prescription: pending,
};
