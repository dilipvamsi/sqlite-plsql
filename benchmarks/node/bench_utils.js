const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

function getExtPath() {
    const buildDir = path.resolve(__dirname, '../../build');
    if (process.platform === 'win32') return path.join(buildDir, 'plsqlite.dll');
    if (process.platform === 'darwin') return path.join(buildDir, 'plsqlite.dylib');
    return path.join(buildDir, 'plsqlite.so');
}

function getDbConnection() {
    const useMem = process.env.BENCH_USE_MEMORY === '1' || process.env.BENCH_USE_MEMORY === 'true';
    const dbPath = useMem ? ':memory:' : path.resolve(__dirname, '../../databases/bench.db');

    const db = new Database(dbPath);

    if (useMem) {
        const seedPath = path.resolve(__dirname, '../../benchmarks/sql/seed.sql');
        const seedSql = fs.readFileSync(seedPath, 'utf8');
        db.exec(seedSql);
    }

    return db;
}

function loadPLSQLite(db) {
    db.loadExtension(getExtPath());
}

module.exports = {
    getDbConnection,
    loadPLSQLite
};
