-- Case 4: Complex Transactional Logic (Account Transfers)
.load build/plsqlite

SELECT register_plsql('transfer', 'from_id, to_id, amount', '
    DECLARE bal = 0.0;
    SET bal = (SELECT balance FROM accounts WHERE id = @from_id);
    IF (@bal >= @amount) THEN
        UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
        UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
    END IF;
    RETURN @bal;
');

SELECT register_plsql('batch_transfer', 'n', '
    FOR i IN (WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < @n) SELECT x FROM cnt) LOOP
        CALL transfer(@i.x, @i.x + 1, 10.0);
    END LOOP;
    RETURN ''DONE'';
');

SELECT 'CASE: Transactions';
.timer on
SELECT run_plsql('batch_transfer', COALESCE(CAST(os_getenv('BENCH_TX_COUNT') AS INTEGER), 10));
.timer off
