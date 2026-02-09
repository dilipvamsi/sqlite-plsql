-- Seed benchmark data
DROP TABLE IF EXISTS data;
CREATE TABLE data (val REAL);
WITH RECURSIVE cnt(x) AS (
    SELECT 1
    UNION ALL
    SELECT x + 1 FROM cnt WHERE x < 100000
)
INSERT INTO data (val) SELECT random() % 100 FROM cnt;

-- Seed accounts for transaction benchmarks
DROP TABLE IF EXISTS accounts;
CREATE TABLE accounts (id INTEGER PRIMARY KEY, balance REAL);
INSERT INTO accounts (id, balance)
SELECT x, 1000.0 FROM (
    WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM cnt WHERE x < 10000)
    SELECT x FROM cnt
);
