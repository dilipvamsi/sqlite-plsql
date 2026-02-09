use rusqlite::{Connection, Result};
use std::time::Instant;

const DB_PATH: &str = "../../databases/bench.db";
const EXT_PATH: &str = "../../build/plsqlite.so";

fn setup_db() -> Result<()> {
    let conn = Connection::open(DB_PATH)?;
    conn.execute("DROP TABLE IF EXISTS bulk_data;", [])?;
    conn.execute("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);", [])?;
    Ok(())
}

fn bench_app_layer(n: i32) -> Result<f64> {
    let mut conn = Connection::open(DB_PATH)?;
    let start = Instant::now();

    let tx = conn.transaction()?;
    {
        let mut stmt = tx.prepare("INSERT INTO bulk_data (val) VALUES (?)")?;
        for i in 0..n {
            stmt.execute([format!("row_{}", i)])?;
        }
    }
    tx.commit()?;

    let elapsed = start.elapsed().as_secs_f64() * 1000.0;
    Ok(elapsed)
}

extern "C" {
    fn sqlite3_enable_load_extension(db: *mut std::ffi::c_void, onoff: i32) -> i32;
}

fn bench_plsqlite(n: i32) -> Result<f64> {
    let conn = Connection::open(DB_PATH)?;
    unsafe {
        let handle = conn.handle();
        sqlite3_enable_load_extension(handle as _, 1);
        conn.load_extension(EXT_PATH, None)?;
    }

    let _: String = conn.query_row(
        "SELECT register_plsql('bulk_insert', 'n', '
            FOR r IN (WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < @n) SELECT x FROM cnt) LOOP
                INSERT INTO bulk_data (val) VALUES (''row_'' || @r.x);
            END LOOP;
            RETURN ''DONE'';
        ');",
        [],
        |r| r.get(0)
    )?;

    let start = Instant::now();
    let _: String = conn.query_row("SELECT run_plsql('bulk_insert', ?)", [n], |r| r.get(0))?;
    let elapsed = start.elapsed().as_secs_f64() * 1000.0;

    Ok(elapsed)
}

fn main() -> Result<()> {
    let n = 10000;
    println!("--- Rust Bulk Inserts ({} rows) ---", n);

    setup_db()?;
    let app_time = bench_app_layer(n)?;
    println!("RESULT: Bulk: App-Layer: {:.2}ms", app_time);

    setup_db()?;
    let pl_time = bench_plsqlite(n)?;
    println!("RESULT: Bulk: PL/SQLite: {:.2}ms", pl_time);

    println!("Speedup: {:.2}x", app_time / pl_time);

    Ok(())
}
