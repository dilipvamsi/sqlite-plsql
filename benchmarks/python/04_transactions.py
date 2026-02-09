import sqlite3
import time
import os
import sys
from bench_utils import get_connection, load_plsqlite

def setup_accounts(conn=None):
    close = False
    if conn is None:
        conn = get_connection()
        close = True
    conn.execute("UPDATE accounts SET balance = 1000.0")
    conn.commit()
    if close:
        conn.close()

def bench_app_layer(n=1000):
    conn = get_connection()
    setup_accounts(conn)
    start = time.time()

    for i in range(1, n + 1):
        from_id = i
        to_id = i + 1
        amount = 10.0

        with conn: # Starts a transaction
            cursor = conn.execute("SELECT balance FROM accounts WHERE id = ?", (from_id,))
            res = cursor.fetchone()
            if res and res[0] >= amount:
                conn.execute("UPDATE accounts SET balance = balance - ? WHERE id = ?", (amount, from_id))
                conn.execute("UPDATE accounts SET balance = balance + ? WHERE id = ?", (amount, to_id))

    end = time.time()
    conn.close()
    return (end - start) * 1000

def bench_plsqlite(n=1000):
    conn = get_connection()
    setup_accounts(conn)
    load_plsqlite(conn)

    conn.execute("""
    SELECT register_plsql('transfer', 'from_id, to_id, amount', '
        DECLARE bal = 0.0;
        SET bal = (SELECT balance FROM accounts WHERE id = @from_id);
        IF (@bal >= @amount) THEN
            UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
            UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
        END IF;
        RETURN @bal;
    ');
    """)

    start = time.time()
    for i in range(1, n + 1):
        conn.execute("SELECT run_plsql('transfer', ?, ?, 10.0)", (i, i + 1))

    end = time.time()
    conn.close()
    return (end - start) * 1000

def bench_plsqlite_batched(n=1000):
    conn = get_connection()
    setup_accounts(conn)
    load_plsqlite(conn)

    conn.execute("""
    SELECT register_plsql('transfer', 'from_id, to_id, amount', '
        DECLARE bal = 0.0;
        SET bal = (SELECT balance FROM accounts WHERE id = @from_id);
        IF (@bal >= @amount) THEN
            UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
            UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
        END IF;
        RETURN @bal;
    ');
    """)

    conn.execute("""
    SELECT register_plsql('batch_transfer', 'n', '
        RANGE i IN (1, @n) LOOP
            CALL transfer(@i, @i + 1, 10.0);
        END LOOP;
        RETURN "DONE";
    ');
    """)
    start = time.time()
    conn.execute("SELECT run_plsql('batch_transfer', ?)", (n,))
    end = time.time()
    conn.close()
    return (end - start) * 1000

if __name__ == "__main__":
    n = int(os.getenv("BENCH_TX_COUNT", "10"))
    print(f"--- Python Transaction Benchmarks ({n} transfers) ---")

    setup_accounts()
    app_time = bench_app_layer(n)
    print(f"RESULT: Transactions: App-Layer: {app_time:.2f}ms")

    setup_accounts()
    pl_time = bench_plsqlite(n)
    print(f"RESULT: Transactions: PL/SQLite Proc: {pl_time:.2f}ms")

    setup_accounts()
    pl_batch_time = bench_plsqlite_batched(n)
    print(f"RESULT: Transactions: PL/SQLite Batch: {pl_batch_time:.2f}ms")

    if pl_time > 0:
        print(f"Speedup (App vs Proc): {app_time/pl_time:.2f}x")
    if pl_batch_time > 0:
        print(f"Speedup (App vs Batch): {app_time/pl_batch_time:.2f}x")
