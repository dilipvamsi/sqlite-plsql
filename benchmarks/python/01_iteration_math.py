import sqlite3
import time
import os
import sys
from bench_utils import get_connection, load_plsqlite

def bench_app_layer():
    conn = get_connection()
    conn.execute("DROP TABLE IF EXISTS iteration_results")
    conn.execute("CREATE TABLE iteration_results(val REAL)")
    start = time.time()
    with conn:
        for row in conn.execute("SELECT val FROM data"):
            val = row[0]
            if val > 50:
                conn.execute("INSERT INTO iteration_results(val) VALUES (?)", (val * 1.5,))
            else:
                conn.execute("INSERT INTO iteration_results(val) VALUES (?)", (val,))
    end = time.time()
    res = conn.execute("SELECT count(*) FROM iteration_results").fetchone()[0]
    conn.close()
    return (end - start) * 1000, res

def bench_plsqlite():
    conn = get_connection()
    load_plsqlite(conn)
    conn.execute("DROP TABLE IF EXISTS iteration_results")
    conn.execute("CREATE TABLE iteration_results(val REAL)")

    conn.execute("""
    SELECT register_plsql('weighted_sum_insert', '', '
        FOR r IN (SELECT val FROM data) LOOP
            IF (@r.val > 50) THEN
                INSERT INTO iteration_results(val) VALUES (@r.val * 1.5);
            ELSE
                INSERT INTO iteration_results(val) VALUES (@r.val);
            END IF;
        END LOOP;
    ');
    """)

    start = time.time()
    conn.execute("SELECT run_plsql('weighted_sum_insert');").fetchone()
    end = time.time()
    res = conn.execute("SELECT count(*) FROM iteration_results").fetchone()[0]
    conn.close()
    return (end - start) * 1000, res

if __name__ == "__main__":
    print("--- Python Benchmarks ---")
    app_time, app_res = bench_app_layer()
    print(f"RESULT: Iteration: App-Layer: {app_time:.2f}ms (Result: {app_res})")

    pl_time, pl_res = bench_plsqlite()
    print(f"RESULT: Iteration: PL/SQLite: {pl_time:.2f}ms (Result: {pl_res})")

    if pl_time > 0:
        print(f"Speedup: {app_time/pl_time:.2f}x")
