use rusqlite::{Connection, Result};
use std::time::Instant;
use std::path::Path;

const DB_PATH: &str = "../../databases/bench.db";
const EXT_PATH: &str = "../../build/plsqlite.so";

fn bench_app_layer() -> Result<(f64, f64)> {
    let conn = Connection::open(DB_PATH)?;
    let start = Instant::now();

    let mut stmt = conn.prepare("SELECT val FROM data")?;
    let rows = stmt.query_map([], |row| row.get::<_, f64>(0))?;

    let mut sum = 0.0;
    for val in rows {
        let v = val?;
        if v > 50.0 {
            sum += v * 1.5;
        } else {
            sum += v;
        }
    }

    let elapsed = start.elapsed().as_secs_f64() * 1000.0;
    Ok((elapsed, sum))
}

extern "C" {
    fn sqlite3_enable_load_extension(db: *mut std::ffi::c_void, onoff: i32) -> i32;
}

fn bench_plsqlite() -> Result<(f64, f64)> {
    let conn = Connection::open(DB_PATH)?;

    // Load extension
    unsafe {
        let handle = conn.handle();
        sqlite3_enable_load_extension(handle as _, 1);
        conn.load_extension(EXT_PATH, None)?;
    }

    let _: String = conn.query_row(
        "SELECT register_plsql('weighted_sum', '', '
            DECLARE total = 0.0;
            FOR r IN (SELECT val FROM data) LOOP
                IF (@r.val > 50) THEN SET total = @total + (@r.val * 1.5);
                ELSE SET total = @total + @r.val; END IF;
            END LOOP;
            RETURN @total;
        ');",
        [],
        |r| r.get(0)
    )?;

    let start = Instant::now();
    let sum: f64 = conn.query_row("SELECT run_plsql('weighted_sum')", [], |r| r.get(0))?;
    let elapsed = start.elapsed().as_secs_f64() * 1000.0;

    Ok((elapsed, sum))
}

fn main() -> Result<()> {
    println!("--- Rust Benchmarks (100k rows) ---");

    let (app_time, app_sum) = bench_app_layer()?;
    println!("RESULT: Iteration: App-Layer: {:.2}ms (Result: {:.2})", app_time, app_sum);

    let (pl_time, pl_sum) = bench_plsqlite()?;
    println!("RESULT: Iteration: PL/SQLite: {:.2}ms (Result: {:.2})", pl_time, pl_sum);

    println!("Speedup: {:.2}x", app_time / pl_time);

    Ok(())
}
