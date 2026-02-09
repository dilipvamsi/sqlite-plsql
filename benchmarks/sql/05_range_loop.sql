-- Case 5: RANGE loop with INSERT (10k iterations)

DROP TABLE IF EXISTS range_test;
CREATE TABLE range_test(id INTEGER PRIMARY KEY, val INTEGER);

SELECT register_plsql('range_insert_test', 'n', '
    RANGE i IN (1, @n) LOOP
        INSERT INTO range_test(val) VALUES (@i);
    END LOOP;
');

SELECT 'CASE: RANGE Loop (10k inserts)';
.timer on
SELECT run_plsql('range_insert_test', 10000);
.timer off

SELECT 'Inserted count:', count(*) FROM range_test;
