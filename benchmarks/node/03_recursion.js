const Database = require('better-sqlite3');
const path = require('path');

const dbPath = path.resolve(__dirname, '../../databases/bench.db');
const extPath = path.resolve(__dirname, '../../build/plsqlite.so');

function benchAppLayer(depth = 200) {
    const start = process.hrtime.bigint();

    function recurse(n) {
        if (n <= 0) return 0;
        return n + recurse(n - 1);
    }

    const res = recurse(depth);
    const end = process.hrtime.bigint();
    return { time: Number(end - start) / 1000000, res };
}

function benchPLSQLite(depth = 200) {
    const db = new Database(dbPath);
    db.loadExtension(extPath);

    db.prepare(`
        SELECT register_plsql('rec_sum', 'n', '
            IF (@n <= 0) THEN
                RETURN 0;
            ELSE
                DECLARE inner_res = 0;
                SET inner_res = (SELECT run_plsql(''rec_sum'', @n - 1));
                RETURN @n + @inner_res;
            END IF;
        ');
    `).run();

    const start = process.hrtime.bigint();
    const res = db.prepare("SELECT run_plsql('rec_sum', ?) as res").get(depth).res;
    const end = process.hrtime.bigint();
    db.close();
    return { time: Number(end - start) / 1000000, res };
}

console.log("--- Node.js Recursion Benchmarks ---");
const depth = 200;

const app = benchAppLayer(depth);
console.log(`RESULT: Recursion: App-Layer: ${app.time.toFixed(4)}ms (Result: ${app.res})`);

const pl = benchPLSQLite(depth);
console.log(`RESULT: Recursion: PL/SQLite Proc: ${pl.time.toFixed(2)}ms (Result: ${pl.res})`);

console.log(`Speedup: ${(app.time / pl.time).toFixed(4)}x`);
