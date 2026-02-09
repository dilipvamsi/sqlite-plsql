package main

import (
	"fmt"
	"log"
	"time"

	"benchmarks/go/utils"
)

func benchAppLayer() (float64, int) {
	db, err := utils.GetConnection(false)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	db.Exec("DROP TABLE IF EXISTS iteration_results")
	db.Exec("CREATE TABLE iteration_results(val REAL)")

	start := time.Now()
	rows, err := db.Query("SELECT val FROM data")
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	tx, err := db.Begin()
	if err != nil {
		log.Fatal(err)
	}
	stmt, _ := tx.Prepare("INSERT INTO iteration_results(val) VALUES (?)")
	defer stmt.Close()

	for rows.Next() {
		var val float64
		rows.Scan(&val)
		if val > 50 {
			stmt.Exec(val * 1.5)
		} else {
			stmt.Exec(val)
		}
	}
	tx.Commit()

	elapsed := time.Since(start).Seconds() * 1000
	var count int
	db.QueryRow("SELECT count(*) FROM iteration_results").Scan(&count)
	return elapsed, count
}

func benchPLSQLite() (float64, int) {
	db, err := utils.GetConnection(true)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	db.Exec("DROP TABLE IF EXISTS iteration_results")
	db.Exec("CREATE TABLE iteration_results(val REAL)")

	_, err = db.Exec(`
        SELECT register_plsql('weighted_sum_insert', '', '
            FOR r IN (SELECT val FROM data) LOOP
                IF (@r.val > 50) THEN
                    INSERT INTO iteration_results(val) VALUES (@r.val * 1.5);
                ELSE
                    INSERT INTO iteration_results(val) VALUES (@r.val);
                END IF;
            END LOOP;
        ');
    `)
	if err != nil {
		log.Fatal("Register fail:", err)
	}

	start := time.Now()
	_, err = db.Exec("SELECT run_plsql('weighted_sum_insert')")
	if err != nil {
		log.Fatal("Run fail:", err)
	}
	elapsed := time.Since(start).Seconds() * 1000

	var count int
	db.QueryRow("SELECT count(*) FROM iteration_results").Scan(&count)
	return elapsed, count
}

func main() {
	fmt.Println("--- Go Iteration Benchmarks ---")

	appTime, appCount := benchAppLayer()
	fmt.Printf("RESULT: Iteration: App-Layer: %.2fms (Result: %d)\n", appTime, appCount)

	plTime, plCount := benchPLSQLite()
	fmt.Printf("RESULT: Iteration: PL/SQLite: %.2fms (Result: %d)\n", plTime, plCount)

	if plTime > 0 {
		fmt.Printf("Speedup: %.2fx\n", appTime/plTime)
	}
}
