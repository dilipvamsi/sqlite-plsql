use rusqlite::{Connection, Result};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub fn get_ext_path() -> PathBuf {
    let base = PathBuf::from("../../build");
    if cfg!(target_os = "windows") {
        base.join("plsqlite.dll")
    } else if cfg!(target_os = "macos") {
        base.join("plsqlite.dylib")
    } else {
        base.join("plsqlite.so")
    }
}

extern "C" {
    fn sqlite3_enable_load_extension(db: *mut std::ffi::c_void, onoff: i32) -> i32;
}

pub fn get_db_connection(load_ext: bool) -> Result<Connection> {
    let use_mem = env::var("BENCH_USE_MEMORY").map(|v| v == "1" || v == "true").unwrap_or(false);

    let conn = if use_mem {
        let c = Connection::open_in_memory()?;
        let seed_path = Path::new("../../benchmarks/sql/seed.sql");
        let seed_sql = fs::read_to_string(seed_path).expect("failed to read seed.sql");
        c.execute_batch(&seed_sql)?;
        c
    } else {
        Connection::open("../../databases/bench.db")?
    };

    if load_ext {
        unsafe {
            let handle = conn.handle();
            sqlite3_enable_load_extension(handle as _, 1);
            conn.load_extension(get_ext_path(), None)?;
        }
    }

    Ok(conn)
}
