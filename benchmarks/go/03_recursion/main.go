package main

import (
	"fmt"
	"log"
	"time"

	"benchmarks/go/utils"
)

func benchAppLayer(depth int) (float64, int) {
	db, err := utils.GetConnection(false)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	db.Exec("DROP TABLE IF EXISTS recursion_log")
	db.Exec("CREATE TABLE recursion_log(depth INTEGER, val INTEGER)")
	tx, _ := db.Begin()
	stmt, _ := tx.Prepare("INSERT INTO recursion_log(depth, val) VALUES (?, ?)")
	defer stmt.Close()

	var recurse func(int) int
	recurse = func(n int) int {
		if n <= 0 {
			return 0
		}
		stmt.Exec(n, n*2)
		return n + recurse(n-1)
	}

	start := time.Now()
	recurse(depth)
	tx.Commit()
	elapsed := time.Since(start).Seconds() * 1000

	var count int
	db.QueryRow("SELECT count(*) FROM recursion_log").Scan(&count)
	return elapsed, count
}

func benchPLSQLite(depth int) (float64, int) {
	db, err := utils.GetConnection(true)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	db.Exec("DROP TABLE IF EXISTS recursion_log")
	db.Exec("CREATE TABLE recursion_log(depth INTEGER, val INTEGER)")

	_, err = db.Exec(`
        SELECT register_plsql('rec_log_insert', 'n', '
            IF (@n <= 0) THEN
                RETURN 0;
            END IF;
            INSERT INTO recursion_log(depth, val) VALUES (@n, @n * 2);
            RETURN @n + (SELECT run_plsql(''rec_log_insert'', @n - 1));
        ');
    `)
	if err != nil {
		log.Fatal("Register fail:", err)
	}

	start := time.Now()
	_, err = db.Exec("SELECT run_plsql('rec_log_insert', ?)", depth)
	if err != nil {
		log.Fatal("Run fail:", err)
	}
	elapsed := time.Since(start).Seconds() * 1000

	var count int
	db.QueryRow("SELECT count(*) FROM recursion_log").Scan(&count)
	return elapsed, count
}

func main() {
	depth := 100
	fmt.Printf("--- Go Recursion (%d depth) ---\n", depth)

	appTime, appCount := benchAppLayer(depth)
	fmt.Printf("RESULT: Recursion: App-Layer: %.4fms (Result: %d)\n", appTime, appCount)

	plTime, plCount := benchPLSQLite(depth)
	fmt.Printf("RESULT: Recursion: PL/SQLite: %.2fms (Result: %d)\n", plTime, plCount)

	if plTime > 0 {
		fmt.Printf("Speedup: %.4fx\n", appTime/plTime)
	}
}
