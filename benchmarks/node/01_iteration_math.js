const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const dbPath = path.resolve(__dirname, '../../databases/bench.db');
let extPath = '';

if (process.platform === 'win32') {
    extPath = path.resolve(__dirname, '../../build/plsqlite.dll');
} else if (process.platform === 'darwin') {
    extPath = path.resolve(__dirname, '../../build/plsqlite.dylib');
} else {
    extPath = path.resolve(__dirname, '../../build/plsqlite.so');
}

function benchAppLayer() {
    const db = new Database(dbPath);
    const start = Date.now();

    let sum = 0.0;
    const stmt = db.prepare('SELECT val FROM data');
    for (const row of stmt.iterate()) {
        const val = row.val;
        if (val > 50) {
            sum += val * 1.5;
        } else {
            sum += val;
        }
    }

    const end = Date.now();
    db.close();
    return { time: end - start, sum };
}

function benchPLSQLite() {
    const db = new Database(dbPath);
    // better-sqlite3 loads extensions via .loadExtension()
    db.loadExtension(extPath);

    db.prepare(`
        SELECT register_plsql('weighted_sum', '', '
            DECLARE total = 0.0;
            FOR r IN (SELECT val FROM data) LOOP
                IF (@r.val > 50) THEN
                    SET total = @total + (@r.val * 1.5);
                ELSE
                    SET total = @total + @r.val;
                END IF;
            END LOOP;
            RETURN @total;
        ');
    `).run();

    const start = Date.now();
    const sum = db.prepare("SELECT run_plsql('weighted_sum') as res").get().res;
    const end = Date.now();
    db.close();
    return { time: end - start, sum };
}

console.log("--- Node.js Benchmarks (better-sqlite3) ---");
const app = benchAppLayer();
console.log(`RESULT: Iteration: App-Layer: ${app.time.toFixed(2)}ms (Result: ${app.sum})`);

const pl = benchPLSQLite();
console.log(`RESULT: Iteration: PL/SQLite: ${pl.time.toFixed(2)}ms (Result: ${pl.sum})`);

console.log(`Speedup: ${(app.time / pl.time).toFixed(2)}x`);
