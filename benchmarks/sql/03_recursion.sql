-- Case 3: Recursion with Logging (100 depth)

DROP TABLE IF EXISTS recursion_log;
CREATE TABLE recursion_log(depth INTEGER, val INTEGER);

SELECT register_plsql('rec_log_insert', 'n', '
    IF (@n <= 0) THEN RETURN 0; END IF;
    INSERT INTO recursion_log(depth, val) VALUES (@n, @n * 2);
    RETURN @n + (SELECT run_plsql(''rec_log_insert'', @n - 1));
');

SELECT 'CASE: Recursion';
.timer on
SELECT run_plsql('rec_log_insert', 100);
.timer off

SELECT 'Log count:', count(*) FROM recursion_log;
