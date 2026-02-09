-- Case 4: Complex Transaction Logic (10 transfers)

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
    RANGE i IN (1, @n) LOOP
        CALL transfer(@i, @i + 1, 10.0);
    END LOOP;
    RETURN ''DONE'';
');

SELECT 'CASE: Transactions';
.timer on
SELECT run_plsql('batch_transfer', COALESCE(CAST(os_getenv('BENCH_TX_COUNT') AS INTEGER), 10));
.timer off
