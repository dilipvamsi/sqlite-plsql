import sqlite3
import time
import os
import sys

# Path to the extension
EXT_PATH = os.path.abspath("../../build/plsqlite.so")
DB_PATH = "../../databases/bench.db"

def setup_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("DROP TABLE IF EXISTS bulk_data;")
    conn.execute("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);")
    conn.close()

def bench_app_layer(n=10000):
    conn = sqlite3.connect(DB_PATH)
    start = time.time()

    # Python app logic: multiple inserts in one transaction
    conn.execute("BEGIN TRANSACTION;")
    for i in range(n):
        conn.execute("INSERT INTO bulk_data (val) VALUES (?);", (f"row_{i}",))
    conn.execute("COMMIT;")

    end = time.time()
    conn.close()
    return (end - start) * 1000

def bench_plsqlite(n=10000):
    conn = sqlite3.connect(DB_PATH)
    conn.enable_load_extension(True)
    conn.load_extension(EXT_PATH)

    conn.execute("""
    SELECT register_plsql('bulk_insert', 'n', '
        DECLARE i = 0;
        FOR r IN (WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < @n) SELECT x FROM cnt) LOOP
            INSERT INTO bulk_data (val) VALUES (''row_'' || @r.x);
        END LOOP;
        RETURN ''DONE'';
    ');
    """)

    start = time.time()
    conn.execute("SELECT run_plsql('bulk_insert', ?);", (n,))
    end = time.time()

    conn.close()
    return (end - start) * 1000

if __name__ == "__main__":
    print("--- Python Bulk Inserts (10k rows) ---")
    setup_db()
    app_time = bench_app_layer()
    print(f"RESULT: Bulk: App-Layer: {app_time:.2f}ms")

    setup_db()
    pl_time = bench_plsqlite()
    print(f"RESULT: Bulk: PL/SQLite: {pl_time:.2f}ms")

    print(f"Speedup: {app_time/pl_time:.2f}x")
