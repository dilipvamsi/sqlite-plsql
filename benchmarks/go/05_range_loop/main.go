package main

import (
	"fmt"
	"log"
	"time"

	"benchmarks/go/utils"
)

func benchGoRangeInsert(n int) (float64, int) {
	db, err := utils.GetConnection(false)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("DROP TABLE IF EXISTS range_test")
	db.Exec("CREATE TABLE range_test(id INTEGER PRIMARY KEY, val INTEGER)")

	start := time.Now()
	tx, err := db.Begin()
	if err != nil {
		log.Fatal(err)
	}
	stmt, _ := tx.Prepare("INSERT INTO range_test(val) VALUES (?)")
	for i := 1; i <= n; i++ {
		stmt.Exec(i)
	}
	tx.Commit()
	elapsed := time.Since(start).Seconds() * 1000

	var count int
	db.QueryRow("SELECT count(*) FROM range_test").Scan(&count)
	return elapsed, count
}

func benchPLSQLiteRangeInsert(n int) (float64, int) {
	db, err := utils.GetConnection(true)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("DROP TABLE IF EXISTS range_test")
	db.Exec("CREATE TABLE range_test(id INTEGER PRIMARY KEY, val INTEGER)")

	_, err = db.Exec(`
        SELECT register_plsql('range_insert_test', 'n', '
            RANGE i IN (1, @n) LOOP
                INSERT INTO range_test(val) VALUES (@i);
            END LOOP;
        ');
    `)
	if err != nil {
		log.Fatal("Register fail:", err)
	}

	start := time.Now()
	_, err = db.Exec("SELECT run_plsql('range_insert_test', ?)", n)
	if err != nil {
		log.Fatal("Run fail:", err)
	}
	elapsed := time.Since(start).Seconds() * 1000

	var count int
	db.QueryRow("SELECT count(*) FROM range_test").Scan(&count)
	return elapsed, count
}

func main() {
	N := 10000
	fmt.Printf("--- RANGE-Insert Benchmarks (%d iterations) ---\n", N)

	goTime, goRes := benchGoRangeInsert(N)
	fmt.Printf("RESULT: Range: App-Layer: %.2fms (Result: %d)\n", goTime, goRes)

	plTime, plRes := benchPLSQLiteRangeInsert(N)
	fmt.Printf("RESULT: Range: PL/SQLite: %.2fms (Result: %d)\n", plTime, plRes)

	if plTime > 0 {
		fmt.Printf("Speedup: %.2fx\n", goTime/plTime)
	}
}
