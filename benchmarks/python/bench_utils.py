import sqlite3
import os
import sys

def get_ext_path():
    if os.name == 'nt':
        return os.path.abspath("../../build/plsqlite.dll")
    elif sys.platform == 'darwin':
        return os.path.abspath("../../build/plsqlite.dylib")
    return os.path.abspath("../../build/plsqlite.so")

def get_db_path():
    use_mem = os.getenv("BENCH_USE_MEMORY", "0") in ("1", "true", "TRUE")
    if use_mem:
        return ":memory:"
    return os.path.abspath("../../databases/bench.db")

def get_connection():
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)

    # If using memory, we need to seed it
    if db_path == ":memory:":
        seed_path = os.path.abspath("../../benchmarks/sql/seed.sql")
        with open(seed_path, 'r') as f:
            conn.executescript(f.read())

    return conn

def load_plsqlite(conn):
    conn.enable_load_extension(True)
    conn.load_extension(get_ext_path())
