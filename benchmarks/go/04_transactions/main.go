package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"time"

	"github.com/mattn/go-sqlite3"
)

func getExtPath() string {
	abs, _ := filepath.Abs("../../build")
	if runtime.GOOS == "windows" {
		return filepath.Join(abs, "plsqlite.dll")
	}
	return filepath.Join(abs, "plsqlite.so")
}

const dbPath = "../../databases/bench.db"

func setupAccounts() {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("UPDATE accounts SET balance = 1000.0")
}

func benchAppLayer(n int) float64 {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	start := time.Now()
	for i := 1; i <= n; i++ {
		tx, err := db.Begin()
		if err != nil {
			log.Fatal(err)
		}

		var bal float64
		err = tx.QueryRow("SELECT balance FROM accounts WHERE id = ?", i).Scan(&bal)
		if err == nil && bal >= 10.0 {
			tx.Exec("UPDATE accounts SET balance = balance - 10.0 WHERE id = ?", i)
			tx.Exec("UPDATE accounts SET balance = balance + 10.0 WHERE id = ?", i+1)
		}
		tx.Commit()
	}
	return time.Since(start).Seconds() * 1000
}

func benchPLSQLite(n int) float64 {
	driverName := fmt.Sprintf("sqlite3_pl_%d", time.Now().UnixNano())
	sql.Register(driverName, &sqlite3.SQLiteDriver{
		Extensions: []string{getExtPath()},
	})

	db, err := sql.Open(driverName, dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	db.Exec(`
        SELECT register_plsql('transfer', 'from_id, to_id, amount', '
            DECLARE bal = 0.0;
            SET bal = (SELECT balance FROM accounts WHERE id = @from_id);
            IF (@bal >= @amount) THEN
                UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
                UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
            END IF;
            RETURN @bal;
        ');
    `)

	start := time.Now()
	for i := 1; i <= n; i++ {
		db.QueryRow("SELECT run_plsql('transfer', ?, ?, 10.0)", i, i+1).Scan(new(interface{}))
	}
	return time.Since(start).Seconds() * 1000
}

func benchPLSQLiteBatched(n int) float64 {
	driverName := fmt.Sprintf("sqlite3_pl_batch_%d", time.Now().UnixNano())
	sql.Register(driverName, &sqlite3.SQLiteDriver{
		Extensions: []string{getExtPath()},
	})

	db, err := sql.Open(driverName, dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	db.Exec(`
        SELECT register_plsql('batch_transfer', 'n', '
            FOR i IN (WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < @n) SELECT x FROM cnt) LOOP
                CALL transfer(@i.x, @i.x + 1, 10.0);
            END LOOP;
            RETURN "DONE";
        ');
    `)

	start := time.Now()
	db.QueryRow("SELECT run_plsql('batch_transfer', ?)", n).Scan(new(interface{}))
	return time.Since(start).Seconds() * 1000
}

func main() {
	nStr := os.Getenv("BENCH_TX_COUNT")
	n, err := strconv.Atoi(nStr)
	if err != nil {
		n = 10
	}
	fmt.Printf("--- Go Transaction Benchmarks (%d transfers) ---\n", n)

	setupAccounts()
	appTime := benchAppLayer(n)
	fmt.Printf("RESULT: Transactions: App-Layer: %.2fms\n", appTime)

	setupAccounts()
	plTime := benchPLSQLite(n)
	fmt.Printf("RESULT: Transactions: PL/SQLite Proc: %.2fms\n", plTime)

	setupAccounts()
	plBatchTime := benchPLSQLiteBatched(n)
	fmt.Printf("RESULT: Transactions: PL/SQLite Batch: %.2fms\n", plBatchTime)

	fmt.Printf("Speedup (App vs Batch): %.2fx\n", appTime/plBatchTime)
}
