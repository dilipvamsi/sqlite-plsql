const { getDbConnection, loadPLSQLite } = require('./bench_utils');

function benchNodeRange(n) {
    const db = getDbConnection();
    db.prepare("DROP TABLE IF EXISTS range_test").run();
    db.prepare("CREATE TABLE range_test(id INTEGER PRIMARY KEY, val INTEGER)").run();
    const start = Date.now();
    db.transaction((n) => {
        const stmt = db.prepare("INSERT INTO range_test(val) VALUES (?)");
        for (let i = 1; i <= n; i++) {
            stmt.run(i);
        }
    })(n);
    const end = Date.now();
    const count = db.prepare("SELECT count(*) as c FROM range_test").get().c;
    db.close();
    return { time: end - start, total: count };
}

function benchPLSQLiteRange(n) {
    const db = getDbConnection();
    loadPLSQLite(db);
    db.prepare("DROP TABLE IF EXISTS range_test").run();
    db.prepare("CREATE TABLE range_test(id INTEGER PRIMARY KEY, val INTEGER)").run();

    db.prepare(`
        SELECT register_plsql('range_insert_test', 'n', '
            RANGE i IN (1, @n) LOOP
                INSERT INTO range_test(val) VALUES (@i);
            END LOOP;
        ');
    `).run();

    const start = Date.now();
    db.prepare("SELECT run_plsql('range_insert_test', ?)").run(n);
    const end = Date.now();
    const count = db.prepare("SELECT count(*) as c FROM range_test").get().c;
    db.close();
    return { time: end - start, total: count };
}

const N = 10000;
console.log(`--- RANGE-Insert Benchmarks (${N.toLocaleString()} iterations) ---`);

const nodeRes = benchNodeRange(N);
console.log(`RESULT: Range: App-Layer: ${nodeRes.time.toFixed(2)}ms (Result: ${nodeRes.total})`);

const plRes = benchPLSQLiteRange(N);
console.log(`RESULT: Range: PL/SQLite: ${plRes.time.toFixed(2)}ms (Result: ${plRes.total})`);

if (plRes.time > 0) {
    console.log(`Speedup: ${(nodeRes.time / plRes.time).toFixed(2)}x`);
}
