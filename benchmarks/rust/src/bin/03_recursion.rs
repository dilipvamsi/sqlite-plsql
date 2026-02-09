use rusqlite::{Connection, Result};
use std::time::Instant;
use std::ffi::c_void;

const DB_PATH: &str = "../../databases/bench.db";
const EXT_PATH: &str = "../../build/plsqlite.so";

extern "C" {
    fn sqlite3_enable_load_extension(db: *mut c_void, onoff: i32) -> i32;
}

fn recurse(n: i32) -> i32 {
    if n <= 0 { 0 } else { n + recurse(n - 1) }
}

fn bench_app_layer(depth: i32) -> f64 {
    let start = Instant::now();
    let _res = recurse(depth);
    start.elapsed().as_secs_f64() * 1000.0
}

fn bench_plsqlite(depth: i32) -> Result<f64> {
    let conn = Connection::open(DB_PATH)?;
    unsafe {
        let handle = conn.handle();
        sqlite3_enable_load_extension(handle as _, 1);
        conn.load_extension(EXT_PATH, None)?;
    }

    let _: String = conn.query_row(
        "SELECT register_plsql('rec_sum', 'n', '
            IF (@n <= 0) THEN
                RETURN 0;
            ELSE
                DECLARE inner_res = 0;
                SET inner_res = (SELECT run_plsql(''rec_sum'', @n - 1));
                RETURN @n + @inner_res;
            END IF;
        ');",
        [],
        |r| r.get(0)
    )?;

    let start = Instant::now();
    let _res: i32 = conn.query_row("SELECT run_plsql('rec_sum', ?)", [depth], |r| r.get(0))?;
    Ok(start.elapsed().as_secs_f64() * 1000.0)
}

fn main() -> Result<()> {
    println!("--- Rust Recursion Benchmarks ---");
    let depth = 200;

    let app_time = bench_app_layer(depth);
    println!("RESULT: Recursion: App-Layer: {:.4}ms", app_time);

    let pl_time = bench_plsqlite(depth)?;
    println!("RESULT: Recursion: PL/SQLite Proc: {:.2}ms", pl_time);

    if pl_time > 0.0 {
        println!("Speedup: {:.4}x", app_time / pl_time);
    }

    Ok(())
}
