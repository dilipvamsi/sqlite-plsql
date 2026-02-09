package main

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"benchmarks/go/utils"
)

func setupAccounts() {
	db, err := utils.GetConnection(false)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("UPDATE accounts SET balance = 1000.0")
}

func benchAppLayer(n int) float64 {
	db, err := utils.GetConnection(false)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("UPDATE accounts SET balance = 1000.0")

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
	db, err := utils.GetConnection(true)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("UPDATE accounts SET balance = 1000.0")

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
	db, err := utils.GetConnection(true)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("UPDATE accounts SET balance = 1000.0")

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

	db.Exec(`
        SELECT register_plsql('batch_transfer', 'n', '
            RANGE i IN (1, @n) LOOP
                CALL transfer(@i, @i + 1, 10.0);
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

	if plBatchTime > 0 {
		fmt.Printf("Speedup (App vs Batch): %.2fx\n", appTime/plBatchTime)
	}
}
