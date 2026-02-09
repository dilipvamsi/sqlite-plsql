import sqlite3
import time
import os
import sys

# Path to the extension
if os.name == 'nt':
    EXT_PATH = os.path.abspath("build/plsqlite.dll")
elif sys.platform == 'darwin':
    EXT_PATH = os.path.abspath("build/plsqlite.dylib")
else:
    EXT_PATH = os.path.abspath("../../build/plsqlite.so")

DB_PATH = "../../databases/bench.db"

def bench_app_layer():
    conn = sqlite3.connect(DB_PATH)
    start = time.time()

    sum_val = 0.0
    for row in conn.execute("SELECT val FROM data"):
        val = row[0]
        if val > 50:
            sum_val += val * 1.5
        else:
            sum_val += val

    end = time.time()
    conn.close()
    return (end - start) * 1000, sum_val

def bench_plsqlite():
    conn = sqlite3.connect(DB_PATH)
    conn.enable_load_extension(True)
    conn.load_extension(EXT_PATH)
    conn.execute("""
    SELECT register_plsql('weighted_sum', '', '
        DECLARE total = 0.0;
        FOR r IN (SELECT val FROM data) LOOP
            IF (@r.val > 50) THEN
                SET total = @total + (@r.val * 1.5);
            ELSE
                SET total = @total + @r.val;
            END IF;
        END LOOP;
        RETURN @total;
    ');
    """)

    start = time.time()
    result = conn.execute("SELECT run_plsql('weighted_sum');").fetchone()[0]
    end = time.time()
    conn.close()
    return (end - start) * 1000, result

if __name__ == "__main__":
    print("--- Python Benchmarks ---")
    app_time, app_res = bench_app_layer()
    print(f"RESULT: Iteration: App-Layer: {app_time:.2f}ms (Result: {app_res})")

    pl_time, pl_res = bench_plsqlite()
    print(f"RESULT: Iteration: PL/SQLite: {pl_time:.2f}ms (Result: {pl_res})")

    print(f"Speedup: {app_time/pl_time:.2f}x")
