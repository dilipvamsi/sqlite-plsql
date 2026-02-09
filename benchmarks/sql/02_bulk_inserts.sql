-- Case 2: Bulk Inserts (10k rows)
.load build/plsqlite

DROP TABLE IF EXISTS bulk_data;
CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);

SELECT register_plsql('bulk_insert', 'n', '
    FOR r IN (WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < @n) SELECT x FROM cnt) LOOP
        INSERT INTO bulk_data (val) VALUES (''row_'' || @r.x);
    END LOOP;
    RETURN ''DONE'';
');

SELECT 'CASE: Bulk';
.timer on
SELECT run_plsql('bulk_insert', 10000);
.timer off
