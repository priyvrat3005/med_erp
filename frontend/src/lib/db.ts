import { invoke } from '@tauri-apps/api/core';

export type SqlParam = string | number | boolean | null;
export interface Stmt { sql: string; params: SqlParam[] }

/** Thin wrapper over Rust commands. All SQL is parameterized. Money values are decimal STRINGS. */
export const db = {
  open: (path: string, keyHex: string) => invoke<void>('db_open', { path, keyHex }),
  runScript: (sql: string) => invoke<void>('db_run_script', { sql }),
  query: <T = Record<string, unknown>>(sql: string, params: SqlParam[] = []) =>
    invoke<T[]>('db_query', { sql, params }),
  /** Atomic: all statements commit or none do. Use for every business write + its outbox rows. */
  tx: (statements: Stmt[]) => invoke<void>('db_exec_batch', { statements }),
};
