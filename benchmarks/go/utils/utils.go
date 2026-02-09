package utils

import (
	"database/sql"
	"log"
	"os"
	"path/filepath"
	"runtime"

	"github.com/mattn/go-sqlite3"
)

var (
	driverInitialized bool
	driverName        string = "sqlite3_with_plsqlite"
)

func init() {
	// We'll register the driver once.
	// To support both ext and no-ext, we'll just always enable ext loading capability?
	// Actually go-sqlite3 enables it if we provide Extensions.
}

func GetExtPath() string {
	abs, _ := filepath.Abs("../../build")
	if runtime.GOOS == "windows" {
		return filepath.Join(abs, "plsqlite.dll")
	} else if runtime.GOOS == "darwin" {
		return filepath.Join(abs, "plsqlite.dylib")
	}
	return filepath.Join(abs, "plsqlite.so")
}

func GetDbPath() (string, bool) {
	useMem := os.Getenv("BENCH_USE_MEMORY")
	if useMem == "1" || useMem == "true" || useMem == "TRUE" {
		return ":memory:", true
	}
	abs, _ := filepath.Abs("../../databases/bench.db")
	return abs, false
}

func GetConnection(ext bool) (*sql.DB, error) {
	dbPath, isMem := GetDbPath()

	// Use a unique sub-name for memory to avoid conflicts between different benchmark runs in the same process
	// but within one benchmark we WANT shared cache for multiple connections.
	dsn := dbPath
	if isMem {
		dsn = "file:gobench?mode=memory&cache=shared"
	}

	currentDriver := "sqlite3"
	if ext {
		currentDriver = "sqlite3_ext"
		if !driverInitialized {
			sql.Register(currentDriver, &sqlite3.SQLiteDriver{
				Extensions: []string{GetExtPath()},
			})
			driverInitialized = true
		}
	}

	db, err := sql.Open(currentDriver, dsn)
	if err != nil {
		return nil, err
	}

	if isMem {
		// Seed the data if it doesn't exist
		var exists int
		db.QueryRow("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='data'").Scan(&exists)
		if exists == 0 {
			seedPath, _ := filepath.Abs("../../benchmarks/sql/seed.sql")
			seedSql, err := os.ReadFile(seedPath)
			if err != nil {
				log.Fatalf("Failed to read seed.sql: %v", err)
			}
			_, err = db.Exec(string(seedSql))
			if err != nil {
				log.Fatalf("Failed to seed memory DB: %v", err)
			}
		}
		// DO NOT SetMaxOpenConns(1) as it causes deadlocks in some benchmarks
	}

	return db, nil
}
