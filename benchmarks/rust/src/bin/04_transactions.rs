use rusqlite::{Connection, Result};
use std::time::Instant;
use std::ffi::c_void;

const DB_PATH: &str = "../../databases/bench.db";
const EXT_PATH: &str = "../../build/plsqlite.so";

extern "C" {
    fn sqlite3_enable_load_extension(db: *mut c_void, onoff: i32) -> i32;
}

fn setup_accounts() -> Result<()> {
    let conn = Connection::open(DB_PATH)?;
    conn.execute("UPDATE accounts SET balance = 1000.0", [])?;
    Ok(())
}

fn bench_app_layer(n: i32) -> Result<f64> {
    let mut conn = Connection::open(DB_PATH)?;
    let start = Instant::now();

    for i in 1..=n {
        let tx = conn.transaction()?;
        {
            let bal: f64 = tx.query_row("SELECT balance FROM accounts WHERE id = ?", [i], |r| r.get(0))?;
            if bal >= 10.0 {
                tx.execute("UPDATE accounts SET balance = balance - 10.0 WHERE id = ?", [i])?;
                tx.execute("UPDATE accounts SET balance = balance + 10.0 WHERE id = ?", [i + 1])?;
            }
        }
        tx.commit()?;
    }

    Ok(start.elapsed().as_secs_f64() * 1000.0)
}

fn bench_plsqlite(n: i32) -> Result<f64> {
    let conn = Connection::open(DB_PATH)?;
    unsafe {
        let handle = conn.handle();
        sqlite3_enable_load_extension(handle as _, 1);
        conn.load_extension(EXT_PATH, None)?;
    }

    let _: String = conn.query_row(
        "SELECT register_plsql('transfer', 'from_id, to_id, amount', '
            DECLARE bal = 0.0;
            SET bal = (SELECT balance FROM accounts WHERE id = @from_id);
            IF (@bal >= @amount) THEN
                UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
                UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
            END IF;
            RETURN @bal;
        ');",
        [],
        |r| r.get(0)
    )?;

    let start = Instant::now();
    for i in 1..=n {
        let _: f64 = conn.query_row("SELECT run_plsql('transfer', ?, ?, 10.0)", [i, i + 1], |r| r.get(0))?;
    }

    Ok(start.elapsed().as_secs_f64() * 1000.0)
}

fn bench_plsqlite_batched(n: i32) -> Result<f64> {
    let conn = Connection::open(DB_PATH)?;
    unsafe {
        let handle = conn.handle();
        sqlite3_enable_load_extension(handle as _, 1);
        conn.load_extension(EXT_PATH, None)?;
    }

    let _: String = conn.query_row(
        "SELECT register_plsql('batch_transfer', 'n', '
            FOR i IN (WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < @n) SELECT x FROM cnt) LOOP
                CALL transfer(@i.x, @i.x + 1, 10.0);
            END LOOP;
            RETURN ''DONE'';
        ');",
        [],
        |r| r.get(0)
    )?;

    let start = Instant::now();
    let _: String = conn.query_row("SELECT run_plsql('batch_transfer', ?)", [n], |r| r.get(0))?;
    
    Ok(start.elapsed().as_secs_f64() * 1000.0)
}

fn main() -> Result<()> {
    let n: i32 = std::env::var("BENCH_TX_COUNT")
        .unwrap_or_else(|_| "10".to_string())
        .parse()
        .unwrap_or(10);
    println!("--- Rust Transaction Benchmarks ({} transfers) ---", n);

    setup_accounts()?;
    let app_time = bench_app_layer(n)?;
    println!("RESULT: Transactions: App-Layer: {:.2}ms", app_time);

    setup_accounts()?;
    let pl_time = bench_plsqlite(n)?;
    println!("RESULT: Transactions: PL/SQLite Proc: {:.2}ms", pl_time);

    setup_accounts()?;
    let pl_batch_time = bench_plsqlite_batched(n)?;
    println!("RESULT: Transactions: PL/SQLite Batch: {:.2}ms", pl_batch_time);

    if pl_batch_time > 0.0 {
        println!("Speedup (App vs Batch): {:.2}x", app_time / pl_batch_time);
    }

    Ok(())
}
