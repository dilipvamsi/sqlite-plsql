const { getDbConnection, loadPLSQLite } = require('./bench_utils');

function benchAppLayer(depth = 100) {
    const db = getDbConnection();
    db.prepare("DROP TABLE IF EXISTS recursion_log").run();
    db.prepare("CREATE TABLE recursion_log(depth INTEGER, val INTEGER)").run();
    const start = process.hrtime.bigint();

    const insertStmt = db.prepare("INSERT INTO recursion_log(depth, val) VALUES (?, ?)");
    function recurse(n) {
        if (n <= 0) return 0;
        insertStmt.run(n, n * 2);
        return n + recurse(n - 1);
    }

    db.transaction(() => recurse(depth))();
    const end = process.hrtime.bigint();
    const count = db.prepare("SELECT count(*) as c FROM recursion_log").get().c;
    db.close();
    return { time: Number(end - start) / 1000000, res: count };
}

function benchPLSQLite(depth = 100) {
    const db = getDbConnection();
    loadPLSQLite(db);
    db.prepare("DROP TABLE IF EXISTS recursion_log").run();
    db.prepare("CREATE TABLE recursion_log(depth INTEGER, val INTEGER)").run();

    db.prepare(`
        SELECT register_plsql('rec_log_insert', 'n', '
            IF (@n <= 0) THEN 
                RETURN 0; 
            END IF;
            INSERT INTO recursion_log(depth, val) VALUES (@n, @n * 2);
            RETURN @n + (SELECT run_plsql(''rec_log_insert'', @n - 1));
        ');
    `).run();

    const start = process.hrtime.bigint();
    db.prepare("SELECT run_plsql('rec_log_insert', ?)").run(depth);
    const end = process.hrtime.bigint();
    const count = db.prepare("SELECT count(*) as c FROM recursion_log").get().c;
    db.close();
    return { time: Number(end - start) / 1000000, res: count };
}

console.log("--- Node.js Recursion Benchmarks ---");
const depth = 100;

const app = benchAppLayer(depth);
console.log(`RESULT: Recursion: App-Layer: ${app.time.toFixed(4)}ms (Result: ${app.res})`);

const pl = benchPLSQLite(depth);
console.log(`RESULT: Recursion: PL/SQLite Proc: ${pl.time.toFixed(2)}ms (Result: ${pl.res})`);

if (pl.time > 0) {
    console.log(`Speedup: ${(app.time / pl.time).toFixed(4)}x`);
}
