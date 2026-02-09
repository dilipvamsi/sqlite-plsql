-- Case 3: Recursion (200 depth)
.load build/plsqlite

SELECT register_plsql('rec_sum', 'n', '
    IF (@n <= 0) THEN RETURN 0; END IF;
    RETURN @n + (SELECT run_plsql(''rec_sum'', @n - 1));
');

SELECT 'CASE: Recursion';
.timer on
SELECT run_plsql('rec_sum', 200);
.timer off
