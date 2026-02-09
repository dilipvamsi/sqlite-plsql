use rust_benchmarks::get_db_connection;
use rusqlite::{params, Result};
use std::env;
use std::time::Instant;

fn setup_accounts() -> Result<()> {
    let conn = get_db_connection(false)?;
    conn.execute("UPDATE accounts SET balance = 1000.0", [])?;
    Ok(())
}

fn bench_app_layer(n: i32) -> Result<f64> {
    let mut conn = get_db_connection(false)?;
    conn.execute("UPDATE accounts SET balance = 1000.0", [])?;
    
    let start = Instant::now();

    for i in 1..=n {
        let tx = conn.transaction()?;
        {
            let bal: f64 = tx.query_row("SELECT balance FROM accounts WHERE id = ?", params![i], |r| {
                r.get(0)
            })?;
            if bal >= 10.0 {
                tx.execute("UPDATE accounts SET balance = balance - 10.0 WHERE id = ?", params![i])?;
                tx.execute("UPDATE accounts SET balance = balance + 10.0 WHERE id = ?", params![i + 1])?;
            }
        }
        tx.commit()?;
    }

    Ok(start.elapsed().as_secs_f64() * 1000.0)
}

fn bench_plsqlite(n: i32) -> Result<f64> {
    let conn = get_db_connection(true)?;
    conn.execute("UPDATE accounts SET balance = 1000.0", [])?;

    conn.query_row(
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
        |_| Ok(())
    )?;

    let start = Instant::now();
    for i in 1..=n {
        conn.query_row("SELECT run_plsql('transfer', ?, ?, 10.0)", params![i, i+1], |_| Ok(()))?;
    }

    Ok(start.elapsed().as_secs_f64() * 1000.0)
}

fn bench_plsqlite_batched(n: i32) -> Result<f64> {
    let conn = get_db_connection(true)?;
    conn.execute("UPDATE accounts SET balance = 1000.0", [])?;

    conn.query_row(
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
        |_| Ok(())
    )?;

    conn.query_row(
        "SELECT register_plsql('batch_transfer', 'n', '
            RANGE i IN (1, @n) LOOP
                CALL transfer(@i, @i + 1, 10.0);
            END LOOP;
            RETURN \"DONE\";
        ');",
        [],
        |_| Ok(())
    )?;

    let start = Instant::now();
    conn.query_row("SELECT run_plsql('batch_transfer', ?)", params![n], |_| Ok(()))?;

    Ok(start.elapsed().as_secs_f64() * 1000.0)
}

fn main() -> Result<()> {
    let n: i32 = env::var("BENCH_TX_COUNT")
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
