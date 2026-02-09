package main

import (
	"database/sql"
	"fmt"
	"log"
	"path/filepath"
	"runtime"
	"time"

	"github.com/mattn/go-sqlite3"
)

func getExtPath() string {
	abs, _ := filepath.Abs("../../build")
	if runtime.GOOS == "windows" {
		return filepath.Join(abs, "plsqlite.dll")
	} else if runtime.GOOS == "darwin" {
		return filepath.Join(abs, "plsqlite.dylib")
	}
	return filepath.Join(abs, "plsqlite.so")
}

const dbPath = "../../databases/bench.db"

func setupDb() {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("DROP TABLE IF EXISTS bulk_data;")
	db.Exec("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);")
}

func benchAppLayer(n int) float64 {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	start := time.Now()
	tx, _ := db.Begin()
	stmt, _ := tx.Prepare("INSERT INTO bulk_data (val) VALUES (?)")
	for i := 0; i < n; i++ {
		stmt.Exec(fmt.Sprintf("row_%d", i))
	}
	tx.Commit()

	return time.Since(start).Seconds() * 1000
}

func benchPLSQLite(n int) float64 {
	driverName := fmt.Sprintf("sqlite3_with_ext_%d", time.Now().UnixNano())
	sql.Register(driverName, &sqlite3.SQLiteDriver{
		Extensions: []string{getExtPath()},
	})

	db, err := sql.Open(driverName, dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	db.Exec(`
        SELECT register_plsql('bulk_insert', 'n', '
            DECLARE i = 0;
            FOR r IN (WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < @n) SELECT x FROM cnt) LOOP
                INSERT INTO bulk_data (val) VALUES (''row_'' || @r.x);
            END LOOP;
                RETURN ''DONE'';
        ');
    `)

	start := time.Now()
	db.Exec("SELECT run_plsql('bulk_insert', ?)", n)
	return time.Since(start).Seconds() * 1000
}

func main() {
	fmt.Println("--- Go Bulk Inserts (10k rows) ---")
	setupDb()
	appTime := benchAppLayer(10000)
	fmt.Printf("RESULT: Bulk: App-Layer: %.2fms\n", appTime)

	setupDb()
	plTime := benchPLSQLite(10000)
	fmt.Printf("RESULT: Bulk: PL/SQLite: %.2fms\n", plTime)

	fmt.Printf("Speedup: %.2fx\n", appTime/plTime)
}
