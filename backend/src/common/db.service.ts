import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Pool, PoolClient } from 'pg';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * The ONLY way to touch tenant data (AGENTS.md rule 1).
 * Opens a transaction and sets app.tenant_id so Postgres RLS filters every statement.
 */
@Injectable()
export class DbService implements OnModuleDestroy {
  private readonly pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 20 });

  async withTenant<T>(tenantId: string, fn: (client: PoolClient) => Promise<T>): Promise<T> {
    if (!UUID_RE.test(tenantId)) throw new Error('invalid tenant id');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenantId]);
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (err) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw err;
    } finally {
      client.release();
    }
  }

  /** Health check only. Never use for tenant tables. */
  async ping(): Promise<boolean> {
    const r = await this.pool.query('SELECT 1 AS ok');
    return r.rows[0].ok === 1;
  }

  async onModuleDestroy() {
    await this.pool.end();
  }
}
