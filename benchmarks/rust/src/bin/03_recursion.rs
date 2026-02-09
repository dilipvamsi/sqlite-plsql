use rust_benchmarks::get_db_connection;
use rusqlite::{params, Result};
use std::time::Instant;

fn bench_app_layer(depth: i32) -> Result<(f64, i64)> {
    let mut conn = get_db_connection(false)?;
    conn.execute("DROP TABLE IF EXISTS recursion_log", [])?;
    conn.execute("CREATE TABLE recursion_log(depth INTEGER, val INTEGER)", [])?;

    let tx = conn.transaction()?;
    let start = Instant::now();
    {
        let mut stmt = tx.prepare("INSERT INTO recursion_log(depth, val) VALUES (?, ?)")?;
        fn recurse(n: i32, stmt: &mut rusqlite::Statement) -> i32 {
            if n <= 0 {
                return 0;
            }
            stmt.execute(params![n, n * 2]).unwrap();
            n + recurse(n - 1, stmt)
        }
        recurse(depth, &mut stmt);
    }
    tx.commit()?;
    let elapsed = start.elapsed().as_secs_f64() * 1000.0;
    let count: i64 = conn.query_row("SELECT count(*) FROM recursion_log", [], |r| r.get(0))?;
    Ok((elapsed, count))
}

fn bench_plsqlite(depth: i32) -> Result<(f64, i64)> {
    let conn = get_db_connection(true)?;

    conn.execute("DROP TABLE IF EXISTS recursion_log", [])?;
    conn.execute("CREATE TABLE recursion_log(depth INTEGER, val INTEGER)", [])?;

    conn.query_row(
        "SELECT register_plsql('rec_log_insert', 'n', '
            IF (@n <= 0) THEN
                RETURN 0;
            END IF;
            INSERT INTO recursion_log(depth, val) VALUES (@n, @n * 2);
            RETURN @n + (SELECT run_plsql(''rec_log_insert'', @n - 1));
        ');",
        [],
        |_| Ok(())
    )?;

    let start = Instant::now();
    conn.query_row("SELECT run_plsql('rec_log_insert', ?)", params![depth], |_| Ok(()))?;
    let elapsed = start.elapsed().as_secs_f64() * 1000.0;

    let count: i64 = conn.query_row("SELECT count(*) FROM recursion_log", [], |r| r.get(0))?;
    Ok((elapsed, count))
}

fn main() -> Result<()> {
    let depth = 100;
    println!("--- Rust Recursion (depth {}) ---", depth);

    let (app_time, app_res) = bench_app_layer(depth)?;
    println!("RESULT: Recursion: App-Layer: {:.4}ms (Result: {})", app_time, app_res);

    let (pl_time, pl_res) = bench_plsqlite(depth)?;
    println!("RESULT: Recursion: PL/SQLite Proc: {:.2}ms (Result: {})", pl_time, pl_res);

    if pl_time > 0.0 {
        println!("Speedup: {:.4}x", app_time / pl_time);
    }
    Ok(())
}
