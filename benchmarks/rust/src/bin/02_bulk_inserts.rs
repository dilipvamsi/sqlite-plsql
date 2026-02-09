use rust_benchmarks::get_db_connection;
use rusqlite::Result;
use std::time::Instant;

fn setup_db() -> Result<()> {
    let conn = get_db_connection(false)?;
    conn.execute("DROP TABLE IF EXISTS bulk_data;", [])?;
    conn.execute("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);", [])?;
    Ok(())
}

fn bench_app_layer(n: i32) -> Result<f64> {
    let mut conn = get_db_connection(false)?;
    conn.execute("DROP TABLE IF EXISTS bulk_data;", [])?;
    conn.execute("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);", [])?;
    
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

fn bench_plsqlite(n: i32) -> Result<f64> {
    let conn = get_db_connection(true)?;
    conn.execute("DROP TABLE IF EXISTS bulk_data;", [])?;
    conn.execute("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);", [])?;
    
    conn.query_row(
        "SELECT register_plsql('bulk_insert', 'n', '
            RANGE i IN (1, @n) LOOP
                INSERT INTO bulk_data (val) VALUES (''row_'' || @i);
            END LOOP;
            RETURN ''DONE'';
        ');",
        [],
        |_| Ok(())
    )?;

    let start = Instant::now();
    conn.query_row("SELECT run_plsql('bulk_insert', ?)", [n], |_| Ok(()))?;
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

    if pl_time > 0.0 {
        println!("Speedup: {:.2}x", app_time / pl_time);
    }

    Ok(())
}
