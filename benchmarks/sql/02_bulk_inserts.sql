-- Case 2: Bulk Inserts (10k rows)

DROP TABLE IF EXISTS bulk_data;
CREATE TABLE bulk_data (id INTEGER PRIMARY KEY, val TEXT);

SELECT register_plsql('bulk_insert', 'n', '
    RANGE i IN (1, @n) LOOP
        INSERT INTO bulk_data (val) VALUES (''row_'' || @i);
    END LOOP;
    RETURN ''DONE'';
');

SELECT 'CASE: Bulk';
.timer on
SELECT run_plsql('bulk_insert', 10000);
.timer off
