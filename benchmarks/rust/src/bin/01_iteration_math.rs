use rust_benchmarks::get_db_connection;
use rusqlite::Result;
use std::time::Instant;

fn bench_app_layer() -> Result<(f64, i64)> {
    let mut conn = get_db_connection(false)?;
    conn.execute("DROP TABLE IF EXISTS iteration_results", [])?;
    conn.execute("CREATE TABLE iteration_results(val REAL)", [])?;

    let start = Instant::now();
    let tx = conn.transaction()?;

    {
        let mut stmt = tx.prepare("SELECT val FROM data")?;
        let mut insert_stmt = tx.prepare("INSERT INTO iteration_results(val) VALUES (?)")?;

        let rows = stmt.query_map([], |row| row.get::<_, f64>(0))?;

        for val in rows {
            let v = val?;
            if v > 50.0 {
                insert_stmt.execute([v * 1.5])?;
            } else {
                insert_stmt.execute([v])?;
            }
        }
    }
    tx.commit()?;

    let elapsed = start.elapsed().as_secs_f64() * 1000.0;
    let count: i64 = conn.query_row("SELECT count(*) FROM iteration_results", [], |r| r.get(0))?;
    Ok((elapsed, count))
}

fn bench_plsqlite() -> Result<(f64, i64)> {
    let conn = get_db_connection(true)?;
    conn.execute("DROP TABLE IF EXISTS iteration_results", [])?;
    conn.execute("CREATE TABLE iteration_results(val REAL)", [])?;

    conn.query_row(
        "SELECT register_plsql('weighted_sum_insert', '', '
            FOR r IN (SELECT val FROM data) LOOP
                IF (@r.val > 50) THEN
                    INSERT INTO iteration_results(val) VALUES (@r.val * 1.5);
                ELSE
                    INSERT INTO iteration_results(val) VALUES (@r.val);
                END IF;
            END LOOP;
        ');",
        [],
        |_| Ok(())
    )?;

    let start = Instant::now();
    conn.query_row("SELECT run_plsql('weighted_sum_insert')", [], |_| Ok(()))?;
    let elapsed = start.elapsed().as_secs_f64() * 1000.0;
    let count: i64 = conn.query_row("SELECT count(*) FROM iteration_results", [], |r| r.get(0))?;

    Ok((elapsed, count))
}

fn main() -> Result<()> {
    println!("--- Rust Iteration Benchmarks ---");

    let (app_time, app_res) = bench_app_layer()?;
    println!("RESULT: Iteration: App-Layer: {:.2}ms (Result: {})", app_time, app_res);

    let (pl_time, pl_res) = bench_plsqlite()?;
    println!("RESULT: Iteration: PL/SQLite: {:.2}ms (Result: {})", pl_time, pl_res);

    if pl_time > 0.0 {
        println!("Speedup: {:.2}x", app_time / pl_time);
    }

    Ok(())
}
