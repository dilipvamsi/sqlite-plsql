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

func benchAppLayer() (float64, float64) {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	start := time.Now()
	rows, err := db.Query("SELECT val FROM data")
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	var sum float64
	for rows.Next() {
		var val float64
		rows.Scan(&val)
		if val > 50 {
			sum += val * 1.5
		} else {
			sum += val
		}
	}

	elapsed := time.Since(start).Seconds() * 1000
	return elapsed, sum
}

func benchPLSQLite() (float64, float64) {
	driverName := fmt.Sprintf("sqlite3_with_ext_%d", time.Now().UnixNano())
	sql.Register(driverName, &sqlite3.SQLiteDriver{
		Extensions: []string{getExtPath()},
	})

	db, err := sql.Open(driverName, dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	_, err = db.Exec(`
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
    `)
	if err != nil {
		log.Fatal("Register fail:", err)
	}

	start := time.Now()
	var sum float64
	err = db.QueryRow("SELECT run_plsql('weighted_sum')").Scan(&sum)
	if err != nil {
		log.Fatal("Run fail:", err)
	}
	elapsed := time.Since(start).Seconds() * 1000
	return elapsed, sum
}

func main() {
	fmt.Println("--- Go Benchmarks ---")

	appTime, appSum := benchAppLayer()
	fmt.Printf("RESULT: Iteration: App-Layer: %.2fms (Result: %.2f)\n", appTime, appSum)

	plTime, plSum := benchPLSQLite()
	fmt.Printf("RESULT: Iteration: PL/SQLite: %.2fms (Result: %.2f)\n", plTime, plSum)

	fmt.Printf("Speedup: %.2fx\n", appTime/plTime)
}
