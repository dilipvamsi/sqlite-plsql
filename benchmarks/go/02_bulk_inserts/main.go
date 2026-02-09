package main

import (
	"fmt"
	"log"
	"time"

	"benchmarks/go/utils"
)

func setupDb() {
	db, err := utils.GetConnection(false)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("DROP TABLE IF EXISTS bulk_data;")
	db.Exec("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);")
}

func benchAppLayer(n int) float64 {
	db, err := utils.GetConnection(false)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("DROP TABLE IF EXISTS bulk_data;")
	db.Exec("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);")

	start := time.Now()
	tx, _ := db.Begin()
	stmt, _ := tx.Prepare("INSERT INTO bulk_data (val) VALUES (?)")
	for i := 0; i < n; i++ {
		stmt.Exec(fmt.Sprintf("row_%d", i))
	}
	_ = tx.Commit()

	return time.Since(start).Seconds() * 1000
}

func benchPLSQLite(n int) float64 {
	db, err := utils.GetConnection(true)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.Exec("DROP TABLE IF EXISTS bulk_data;")
	db.Exec("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);")

	_, _ = db.Exec(`
        SELECT register_plsql('bulk_insert', 'n', '
            DECLARE i = 0;
            RANGE i IN (1, @n) LOOP
                INSERT INTO bulk_data (val) VALUES (''row_'' || @i);
            END LOOP;
                RETURN ''DONE'';
        ');
    `)

	start := time.Now()
	_, _ = db.Exec("SELECT run_plsql('bulk_insert', ?)", n)
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

	if plTime > 0 {
		fmt.Printf("Speedup: %.2fx\n", appTime/plTime)
	}
}
