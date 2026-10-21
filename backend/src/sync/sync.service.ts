import { Injectable } from '@nestjs/common';
import { DbService } from '../common/db.service';
import { AuthContext } from '../common/auth.guard';
import { PushDto, PushResult } from './sync.dto';
import { PROJECTORS, ProjectionError } from './projectors';

const MAX_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000;

@Injectable()
export class SyncService {
  constructor(private readonly db: DbService) {}

  async push(auth: AuthContext, dto: PushDto): Promise<PushResult> {
    const result: PushResult = { accepted: [], duplicates: [], rejected: [] };

    return this.db.withTenant(auth.tenantId, async (c) => {
      for (const ev of dto.events) {
        // clock sanity: reject HLC far in the future
        const ms = Number(ev.hlc.slice(0, 13));
        if (ms - Date.now() > MAX_CLOCK_SKEW_MS) {
          result.rejected.push({ eventId: ev.eventId, reason: 'clock_skew' });
          continue;
        }

        const dup = await c.query(
          'SELECT 1 FROM sync_events WHERE tenant_id = $1 AND event_id = $2',
          [auth.tenantId, ev.eventId],
        );
        if (dup.rowCount) {
          result.duplicates.push(ev.eventId);
          continue;
        }

        await c.query('SAVEPOINT ev');
        try {
          // Row lock on the counter serializes pushes per tenant: seq order == commit order.
          const seqRes = await c.query(
            `INSERT INTO sync_counters (tenant_id, last_seq) VALUES ($1, 1)
             ON CONFLICT (tenant_id) DO UPDATE SET last_seq = sync_counters.last_seq + 1
             RETURNING last_seq`,
            [auth.tenantId],
          );
          const seq = seqRes.rows[0].last_seq;

          await c.query(
            `INSERT INTO sync_events (seq, tenant_id, event_id, device_id, entity, op, payload, hlc)
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
            [seq, auth.tenantId, ev.eventId, auth.deviceId, ev.entity, ev.op, JSON.stringify(ev.payload), ev.hlc],
          );
          await PROJECTORS[ev.entity](c, { tenantId: auth.tenantId, deviceId: auth.deviceId }, ev);
          await c.query('RELEASE SAVEPOINT ev');
          result.accepted.push(ev.eventId);
        } catch (err) {
          await c.query('ROLLBACK TO SAVEPOINT ev');
          const reason = err instanceof ProjectionError ? err.reason : 'projection_failed';
          result.rejected.push({ eventId: ev.eventId, reason });
        }
      }
      return result;
    });
  }

  async pull(auth: AuthContext, cursor: number, limit: number) {
    const lim = Math.min(Math.max(limit, 1), 500);
    return this.db.withTenant(auth.tenantId, async (c) => {
      const r = await c.query(
        `SELECT seq, event_id, entity, op, payload, hlc
           FROM sync_events
          WHERE tenant_id = $1 AND seq > $2 AND device_id <> $3
          ORDER BY seq ASC LIMIT $4`,
        [auth.tenantId, cursor, auth.deviceId, lim + 1],
      );
      const hasMore = r.rows.length > lim;
      const rows = hasMore ? r.rows.slice(0, lim) : r.rows;
      const nextCursor = rows.length ? Number(rows[rows.length - 1].seq) : cursor;
      return {
        events: rows.map((x) => ({
          seq: Number(x.seq), eventId: x.event_id, entity: x.entity, op: x.op, payload: x.payload, hlc: x.hlc,
        })),
        nextCursor,
        hasMore,
      };
    });
  }
}
