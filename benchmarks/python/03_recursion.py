import sqlite3
import time
import os
import sys

def get_ext_path():
    if os.name == 'nt':
        return os.path.abspath("../../build/plsqlite.dll")
    elif sys.platform == 'darwin':
        return os.path.abspath("../../build/plsqlite.dylib")
    return os.path.abspath("../../build/plsqlite.so")

DB_PATH = "../../databases/bench.db"
EXT_PATH = get_ext_path()

def bench_app_layer(depth=200):
    start = time.time()
    def recurse(n):
        if n <= 0: return 0
        return n + recurse(n - 1)
    res = recurse(depth)
    end = time.time()
    return (end - start) * 1000, res

def bench_plsqlite(depth=200):
    conn = sqlite3.connect(DB_PATH)
    conn.enable_load_extension(True)
    conn.load_extension(EXT_PATH)
    conn.execute("""
    SELECT register_plsql('rec_sum', 'n', '
        IF (@n <= 0) THEN
            RETURN 0;
        ELSE
            DECLARE inner_res = 0;
            SET inner_res = (SELECT run_plsql("rec_sum", @n - 1));
            RETURN @n + @inner_res;
        END IF;
    ');
    """)
    start = time.time()
    res = conn.execute("SELECT run_plsql('rec_sum', ?)", (depth,)).fetchone()[0]
    end = time.time()
    conn.close()
    return (end - start) * 1000, res

if __name__ == "__main__":
    print("--- Python Recursion Benchmarks ---")
    depth = 200
    app_time, app_res = bench_app_layer(depth)
    print(f"RESULT: Recursion: App-Layer: {app_time:.4f}ms (Result: {app_res})")

    pl_time, pl_res = bench_plsqlite(depth)
    print(f"RESULT: Recursion: PL/SQLite Proc: {pl_time:.2f}ms (Result: {pl_res})")

    print(f"Speedup: {app_time/pl_time:.4f}x")
