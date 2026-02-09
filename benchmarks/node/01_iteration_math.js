const { getDbConnection, loadPLSQLite } = require('./bench_utils');

function benchAppLayer() {
    const db = getDbConnection();
    db.prepare("DROP TABLE IF EXISTS iteration_results").run();
    db.prepare("CREATE TABLE iteration_results(val REAL)").run();
    const start = Date.now();

    const stmt = db.prepare('SELECT val FROM data');
    const rows = stmt.all();
    const insertMany = db.transaction((rows) => {
        const insertStmt = db.prepare('INSERT INTO iteration_results(val) VALUES (?)');
        for (const row of rows) {
            const val = row.val;
            if (val > 50) {
                insertStmt.run(val * 1.5);
            } else {
                insertStmt.run(val);
            }
        }
    });

    insertMany(rows);

    const end = Date.now();
    const count = db.prepare("SELECT count(*) as c FROM iteration_results").get().c;
    db.close();
    return { time: end - start, sum: count };
}

function benchPLSQLite() {
    const db = getDbConnection();
    loadPLSQLite(db);
    db.prepare("DROP TABLE IF EXISTS iteration_results").run();
    db.prepare("CREATE TABLE iteration_results(val REAL)").run();

    db.prepare(`
        SELECT register_plsql('weighted_sum_insert', '', '
            FOR r IN (SELECT val FROM data) LOOP
                IF (@r.val > 50) THEN
                    INSERT INTO iteration_results(val) VALUES (@r.val * 1.5);
                ELSE
                    INSERT INTO iteration_results(val) VALUES (@r.val);
                END IF;
            END LOOP;
        ');
    `).run();

    const start = Date.now();
    db.prepare("SELECT run_plsql('weighted_sum_insert')").run();
    const end = Date.now();
    const count = db.prepare("SELECT count(*) as c FROM iteration_results").get().c;
    db.close();
    return { time: end - start, sum: count };
}

console.log("--- Node.js Benchmarks (better-sqlite3) ---");
const app = benchAppLayer();
console.log(`RESULT: Iteration: App-Layer: ${app.time.toFixed(2)}ms (Result: ${app.sum})`);

const pl = benchPLSQLite();
console.log(`RESULT: Iteration: PL/SQLite: ${pl.time.toFixed(2)}ms (Result: ${pl.sum})`);

if (pl.time > 0) {
    console.log(`Speedup: ${(app.time / pl.time).toFixed(2)}x`);
}
