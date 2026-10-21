// Starter Tauri core: encrypted SQLite access for the UI.
// All SQL is parameterized. The key is passed as 64 hex chars (256-bit); in production it is
// generated at first run and protected with Windows DPAPI (task T0.4) and never stored in plain text.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use rusqlite::{params_from_iter, types::Value, types::ValueRef, Connection};
use serde::Deserialize;
use serde_json::{json, Map, Value as J};
use std::sync::Mutex;
use tauri::State;

struct Db(Mutex<Option<Connection>>);

#[derive(Deserialize)]
struct Stmt {
    sql: String,
    params: Vec<J>,
}

fn to_sql(v: &J) -> Value {
    match v {
        J::Null => Value::Null,
        J::Bool(b) => Value::Integer(*b as i64),
        J::Number(n) => match n.as_i64() {
            Some(i) => Value::Integer(i),
            None => Value::Real(n.as_f64().unwrap_or(0.0)),
        },
        J::String(s) => Value::Text(s.clone()),
        other => Value::Text(other.to_string()),
    }
}

#[tauri::command]
fn db_open(state: State<'_, Db>, path: String, key_hex: String) -> Result<(), String> {
    if key_hex.len() != 64 || !key_hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("invalid key".into());
    }
    let conn = Connection::open(path).map_err(|e| e.to_string())?;
    conn.execute_batch(&format!("PRAGMA key = \"x'{}'\";", key_hex))
        .map_err(|e| e.to_string())?;
    // Verifies the key: fails here if the key is wrong or the file is not a valid encrypted DB
    conn.query_row("SELECT count(*) FROM sqlite_master", [], |r| r.get::<_, i64>(0))
        .map_err(|_| "wrong key or corrupt database".to_string())?;
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL;")
        .map_err(|e| e.to_string())?;
    *state.0.lock().unwrap() = Some(conn);
    Ok(())
}

#[tauri::command]
fn db_run_script(state: State<'_, Db>, sql: String) -> Result<(), String> {
    let guard = state.0.lock().unwrap();
    let conn = guard.as_ref().ok_or("db not open")?;
    conn.execute_batch(&sql).map_err(|e| e.to_string())
}

#[tauri::command]
fn db_query(state: State<'_, Db>, sql: String, params: Vec<J>) -> Result<Vec<Map<String, J>>, String> {
    let guard = state.0.lock().unwrap();
    let conn = guard.as_ref().ok_or("db not open")?;
    let mut stmt = conn.prepare(&sql).map_err(|e| e.to_string())?;
    let cols: Vec<String> = stmt.column_names().iter().map(|s| s.to_string()).collect();
    let mut rows = stmt
        .query(params_from_iter(params.iter().map(to_sql)))
        .map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    while let Some(row) = rows.next().map_err(|e| e.to_string())? {
        let mut m = Map::new();
        for (i, c) in cols.iter().enumerate() {
            let v = match row.get_ref(i).map_err(|e| e.to_string())? {
                ValueRef::Null => J::Null,
                ValueRef::Integer(n) => json!(n),
                ValueRef::Real(f) => json!(f),
                ValueRef::Text(t) => json!(String::from_utf8_lossy(t)),
                ValueRef::Blob(_) => J::Null,
            };
            m.insert(c.clone(), v);
        }
        out.push(m);
    }
    Ok(out)
}

/// Atomic multi-statement write. Used for every business write together with its outbox rows.
#[tauri::command]
fn db_exec_batch(state: State<'_, Db>, statements: Vec<Stmt>) -> Result<(), String> {
    let guard = state.0.lock().unwrap();
    let conn = guard.as_ref().ok_or("db not open")?;
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    for s in &statements {
        tx.execute(&s.sql, params_from_iter(s.params.iter().map(to_sql)))
            .map_err(|e| e.to_string())?;
    }
    tx.commit().map_err(|e| e.to_string())
}

fn main() {
    tauri::Builder::default()
        .manage(Db(Mutex::new(None)))
        .invoke_handler(tauri::generate_handler![db_open, db_run_script, db_query, db_exec_batch])
        .run(tauri::generate_context!())
        .expect("error while running PharmaOS");
}
