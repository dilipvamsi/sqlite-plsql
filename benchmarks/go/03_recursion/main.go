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

func recurse(n int) int {
	if n <= 0 {
		return 0
	}
	return n + recurse(n-1)
}

func benchAppLayer(depth int) (float64, int) {
	start := time.Now()
	res := recurse(depth)
	elapsed := time.Since(start).Seconds() * 1000
	return elapsed, res
}

func benchPLSQLite(depth int) (float64, int) {
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
        SELECT register_plsql('rec_sum', 'n', '
            IF (@n <= 0) THEN
                RETURN 0;
            END IF;
            RETURN @n + CALL rec_sum(@n - 1);
        ');
    `)

	start := time.Now()
	var res int
	db.QueryRow("SELECT run_plsql('rec_sum', ?)", depth).Scan(&res)
	elapsed := time.Since(start).Seconds() * 1000
	return elapsed, res
}

func main() {
	fmt.Println("--- Go Recursion (200 depth) ---")

	appTime, appRes := benchAppLayer(200)
	fmt.Printf("RESULT: Recursion: App-Layer: %.4fms (Result: %d)\n", appTime, appRes)

	plTime, plRes := benchPLSQLite(200)
	fmt.Printf("RESULT: Recursion: PL/SQLite: %.2fms (Result: %d)\n", plTime, plRes)

	fmt.Printf("Speedup: %.4fx\n", appTime/plTime)
}
