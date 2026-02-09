-- Case 1: Iterative Logic with Transformation (100k rows)

DROP TABLE IF EXISTS iteration_results;
CREATE TABLE iteration_results(val REAL);

SELECT register_plsql('weighted_sum_insert', '', '
    FOR r IN (SELECT val FROM data) LOOP
        IF (@r.val > 50) THEN
            INSERT INTO iteration_results(val) VALUES (@r.val * 1.5);
        ELSE
            INSERT INTO iteration_results(val) VALUES (@r.val);
        END IF;
    END LOOP;
');

SELECT 'CASE: Iteration';
.timer on
SELECT run_plsql('weighted_sum_insert');
.timer off

SELECT 'Inserted count:', count(*) FROM iteration_results;
