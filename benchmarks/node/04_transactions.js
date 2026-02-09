const Database = require('better-sqlite3');
const path = require('path');

const dbPath = path.resolve(__dirname, '../../databases/bench.db');
const extPath = path.resolve(__dirname, '../../build/plsqlite.so');

function setupAccounts() {
    const db = new Database(dbPath);
    db.prepare("UPDATE accounts SET balance = 1000.0").run();
    db.close();
}

function benchAppLayer(n = 100) {
    const db = new Database(dbPath);
    const start = Date.now();

    const selectStmt = db.prepare("SELECT balance FROM accounts WHERE id = ?");
    const updateFrom = db.prepare("UPDATE accounts SET balance = balance - ? WHERE id = ?");
    const updateTo = db.prepare("UPDATE accounts SET balance = balance + ? WHERE id = ?");

    const transfer = db.transaction((from_id, to_id, amount) => {
        const row = selectStmt.get(from_id);
        if (row && row.balance >= amount) {
            updateFrom.run(amount, from_id);
            updateTo.run(amount, to_id);
        }
    });

    for (let i = 1; i <= n; i++) {
        transfer(i, i + 1, 10.0);
    }

    const elapsed = Date.now() - start;
    db.close();
    return elapsed;
}

function benchPLSQLite(n = 100) {
    const db = new Database(dbPath);
    db.loadExtension(extPath);

    db.prepare(`
        SELECT register_plsql('transfer', 'from_id, to_id, amount', '
            DECLARE bal = 0.0;
            SET bal = (SELECT balance FROM accounts WHERE id = @from_id);
            IF (@bal >= @amount) THEN
                UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
                UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
            END IF;
            RETURN @bal;
        ');
    `).run();

    const runStmt = db.prepare("SELECT run_plsql('transfer', ?, ?, 10.0)");

    const start = Date.now();
    for (let i = 1; i <= n; i++) {
        runStmt.get(i, i + 1);
    }

    const elapsed = Date.now() - start;
    db.close();
    return elapsed;
}

function benchPLSQLiteBatched(n = 100) {
    const db = new Database(dbPath);
    db.loadExtension(extPath);

    db.prepare(`
        SELECT register_plsql('batch_transfer', 'n', '
            FOR i IN (WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < @n) SELECT x FROM cnt) LOOP
                CALL transfer(@i.x, @i.x + 1, 10.0);
            END LOOP;
            RETURN ''DONE'';
        ');
    `).run();

    const start = Date.now();
    db.prepare("SELECT run_plsql('batch_transfer', ?)").get(n);
    const elapsed = Date.now() - start;
    db.close();
    return elapsed;
}

const n = parseInt(process.env.BENCH_TX_COUNT || "10", 10);
console.log(`--- Node.js Transaction Benchmarks (${n} transfers) ---`);

setupAccounts();
const appTime = benchAppLayer(n);
console.log(`RESULT: Transactions: App-Layer: ${appTime}ms`);

setupAccounts();
const plTime = benchPLSQLite(n);
console.log(`RESULT: Transactions: PL/SQLite Proc: ${plTime}ms`);

setupAccounts();
const plBatchTime = benchPLSQLiteBatched(n);
console.log(`RESULT: Transactions: PL/SQLite Batch: ${plBatchTime}ms`);

if (plBatchTime > 0) {
    console.log(`Speedup (App vs Batch): ${(appTime / plBatchTime).toFixed(2)}x`);
}
