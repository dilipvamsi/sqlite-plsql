const { getDbConnection, loadPLSQLite } = require('./bench_utils');

function setupDb() {
    const db = getDbConnection();
    db.exec("DROP TABLE IF EXISTS bulk_data;");
    db.exec("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);");
    db.close();
}

function benchAppLayer(n = 10000) {
    const db = getDbConnection();
    db.exec("DROP TABLE IF EXISTS bulk_data;");
    db.exec("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);");
    const start = Date.now();

    const insert = db.prepare("INSERT INTO bulk_data (val) VALUES (?)");
    const runInTx = db.transaction((items) => {
        for (const item of items) insert.run(item);
    });

    const data = [];
    for (let i = 0; i < n; i++) data.push(`row_${i}`);

    runInTx(data);

    const end = Date.now();
    db.close();
    return end - start;
}

function benchPLSQLite(n = 10000) {
    const db = getDbConnection();
    db.exec("DROP TABLE IF EXISTS bulk_data;");
    db.exec("CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);");
    loadPLSQLite(db);

    db.prepare(`
        SELECT register_plsql('bulk_insert', 'n', '
            DECLARE i = 0;
            RANGE i IN (1, @n) LOOP
                INSERT INTO bulk_data (val) VALUES (''row_'' || @i);
            END LOOP;
            RETURN ''DONE'';
        ');
    `).run();

    const start = Date.now();
    db.prepare("SELECT run_plsql('bulk_insert', ?)").run(n);
    const end = Date.now();

    db.close();
    return end - start;
}

console.log("--- Node.js Bulk Inserts (10k rows) ---");
setupDb();
const appTime = benchAppLayer();
console.log(`RESULT: Bulk: App-Layer: ${appTime.toFixed(2)}ms`);

setupDb();
const plTime = benchPLSQLite();
console.log(`RESULT: Bulk: PL/SQLite: ${plTime.toFixed(2)}ms`);

if (plTime > 0) {
    console.log(`Speedup: ${(appTime / plTime).toFixed(2)}x`);
}
