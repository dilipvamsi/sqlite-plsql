-- Case 1: Iteration & Math (100k rows)
.load build/plsqlite

SELECT register_plsql('weighted_sum', '', '
    DECLARE total = 0.0;
    FOR r IN (SELECT val FROM data) LOOP
        IF (@r.val > 50) THEN SET total = @total + (@r.val * 1.5);
        ELSE SET total = @total + @r.val; END IF;
    END LOOP;
    RETURN @total;
');

SELECT 'CASE: Iteration';
.timer on
SELECT run_plsql('weighted_sum');
.timer off
