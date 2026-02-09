use rust_benchmarks::get_db_connection;
use rusqlite::{params, Result};
use std::time::Instant;

fn bench_rust_range_insert(n: i32) -> Result<(f64, i64)> {
    let mut conn = get_db_connection(false)?;
    conn.execute("DROP TABLE IF EXISTS range_test", [])?;
    conn.execute("CREATE TABLE range_test(id INTEGER PRIMARY KEY, val INTEGER)", [])?;

    let start = Instant::now();
    let tx = conn.transaction()?;
    {
        let mut stmt = tx.prepare("INSERT INTO range_test(val) VALUES (?)")?;
        for i in 1..=n {
            stmt.execute(params![i])?;
        }
    }
    tx.commit()?;
    let elapsed = start.elapsed().as_secs_f64() * 1000.0;
    let count: i64 = conn.query_row("SELECT count(*) FROM range_test", [], |r| r.get(0))?;
    Ok((elapsed, count))
}

fn bench_plsqlite_range_insert(n: i32) -> Result<(f64, i64)> {
    let conn = get_db_connection(true)?;
    conn.execute("DROP TABLE IF EXISTS range_test", [])?;
    conn.execute("CREATE TABLE range_test(id INTEGER PRIMARY KEY, val INTEGER)", [])?;

    conn.query_row(
        "SELECT register_plsql('range_insert_test', 'n', '
            RANGE i IN (1, @n) LOOP
                INSERT INTO range_test(val) VALUES (@i);
            END LOOP;
        ');",
        [],
        |_| Ok(())
    )?;

    let start = Instant::now();
    conn.query_row("SELECT run_plsql('range_insert_test', ?)", params![n], |_| Ok(()))?;
    let elapsed = start.elapsed().as_secs_f64() * 1000.0;
    let count: i64 = conn.query_row("SELECT count(*) FROM range_test", [], |r| r.get(0))?;
    Ok((elapsed, count))
}

fn main() -> Result<()> {
    let n = 10000;
    println!("--- Rust RANGE-Insert Benchmarks ({} iterations) ---", n);

    let (rust_time, rust_res) = bench_rust_range_insert(n)?;
    println!("RESULT: Range: App-Layer: {:.2}ms (Result: {})", rust_time, rust_res);

    let (pl_time, pl_res) = bench_plsqlite_range_insert(n)?;
    println!("RESULT: Range: PL/SQLite: {:.2}ms (Result: {})", pl_time, pl_res);

    if pl_time > 0.0 {
        println!("Speedup: {:.2}x", rust_time / pl_time);
    }
    Ok(())
}
