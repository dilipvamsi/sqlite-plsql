import sqlite3
import time
import os
import sys
from bench_utils import get_connection, load_plsqlite

def bench_python_range(n):
    conn = get_connection()
    conn.execute("DROP TABLE IF EXISTS range_test")
    conn.execute("CREATE TABLE range_test(id INTEGER PRIMARY KEY, val INTEGER)")
    start = time.time()
    conn.execute("BEGIN TRANSACTION")
    for i in range(1, n + 1):
        conn.execute("INSERT INTO range_test(val) VALUES (?)", (i,))
    conn.commit()
    end = time.time()
    res = conn.execute("SELECT count(*) FROM range_test").fetchone()[0]
    conn.close()
    return (end - start) * 1000, res

def bench_plsqlite_range(n):
    conn = get_connection()
    load_plsqlite(conn)
    conn.execute("DROP TABLE IF EXISTS range_test")
    conn.execute("CREATE TABLE range_test(id INTEGER PRIMARY KEY, val INTEGER)")

    conn.execute(f"""
    SELECT register_plsql('range_insert_test', 'n', '
        RANGE i IN (1, @n) LOOP
            INSERT INTO range_test(val) VALUES (@i);
        END LOOP;
    ');
    """)

    start = time.time()
    conn.execute("SELECT run_plsql('range_insert_test', ?);", (n,)).fetchone()
    end = time.time()
    res = conn.execute("SELECT count(*) FROM range_test").fetchone()[0]
    conn.close()
    return (end - start) * 1000, res

if __name__ == "__main__":
    N = 10000 # Use 10k for insert benchmark
    print(f"--- RANGE-Insert Benchmarks ({N:,} iterations) ---")

    py_time, py_res = bench_python_range(N)
    print(f"RESULT: Range: App-Layer: {py_time:.2f}ms (Result: {py_res})")

    pl_time, pl_res = bench_plsqlite_range(N)
    print(f"RESULT: Range: PL/SQLite: {pl_time:.2f}ms (Result: {pl_res})")

    if pl_time > 0:
        print(f"Speedup: {py_time/pl_time:.2f}x")
    else:
        print("Speedup: N/A (PL/SQLite time was 0ms)")
