import sqlite3
import time
import os
import sys
from bench_utils import get_connection, load_plsqlite

def bench_app_layer(depth=100):
    conn = get_connection()
    conn.execute("DROP TABLE IF EXISTS recursion_log")
    conn.execute("CREATE TABLE recursion_log(depth INTEGER, val INTEGER)")
    start = time.time()
    with conn:
        def recurse(n):
            if n <= 0: return 0
            conn.execute("INSERT INTO recursion_log(depth, val) VALUES (?, ?)", (n, n * 2))
            return n + recurse(n - 1)
        recurse(depth)
    end = time.time()
    res = conn.execute("SELECT count(*) FROM recursion_log").fetchone()[0]
    conn.close()
    return (end - start) * 1000, res

def bench_plsqlite(depth=100):
    conn = get_connection()
    load_plsqlite(conn)
    conn.execute("DROP TABLE IF EXISTS recursion_log")
    conn.execute("CREATE TABLE recursion_log(depth INTEGER, val INTEGER)")

    conn.execute("""
    SELECT register_plsql('rec_log_insert', 'n', '
        IF (@n <= 0) THEN
            RETURN 0;
        END IF;
        INSERT INTO recursion_log(depth, val) VALUES (@n, @n * 2);
        RETURN @n + (SELECT run_plsql("rec_log_insert", @n - 1));
    ');
    """)
    start = time.time()
    conn.execute("SELECT run_plsql('rec_log_insert', ?)", (depth,)).fetchone()
    end = time.time()
    res = conn.execute("SELECT count(*) FROM recursion_log").fetchone()[0]
    conn.close()
    return (end - start) * 1000, res

if __name__ == "__main__":
    print("--- Python Recursion Benchmarks ---")
    depth = 100
    app_time, app_res = bench_app_layer(depth)
    print(f"RESULT: Recursion: App-Layer: {app_time:.4f}ms (Result: {app_res})")

    pl_time, pl_res = bench_plsqlite(depth)
    print(f"RESULT: Recursion: PL/SQLite Proc: {pl_time:.2f}ms (Result: {pl_res})")

    if pl_time > 0:
        print(f"Speedup: {app_time/pl_time:.4f}x")
