#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>

/* Comprehensive leak check covering all PL/SQLite functions and code paths */

int exec_sql(sqlite3 *db, const char *sql, const char *desc) {
  char *err = 0;
  int rc = sqlite3_exec(db, sql, 0, 0, &err);
  if (rc != SQLITE_OK) {
    fprintf(stderr, "Error in %s: %s\n", desc, err);
    sqlite3_free(err);
    return 1;
  }
  return 0;
}

int main() {
  sqlite3 *db;
  char *zErrMsg = 0;
  int rc;

  rc = sqlite3_open(":memory:", &db);
  if (rc) {
    fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
    return 1;
  }

  sqlite3_enable_load_extension(db, 1);
  rc = sqlite3_load_extension(db, "./build/plsqlite.so", 0, &zErrMsg);
  if (rc != SQLITE_OK) {
    fprintf(stderr, "Load extension error: %s\n", zErrMsg);
    sqlite3_free(zErrMsg);
    sqlite3_close(db);
    return 1;
  }
  printf("Extension loaded successfully.\n");

  /* Create test tables */
  exec_sql(db, "CREATE TABLE nums (id INTEGER, val REAL);", "create nums");
  exec_sql(db, "INSERT INTO nums VALUES (1, 10.5), (2, 20.5), (3, 30.5);",
           "insert nums");
  exec_sql(db, "CREATE TABLE empty_table (id INTEGER);", "create empty");

  printf("=== Testing basic variables ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_basic', 'x', 'DECLARE y = @x; SET y = "
           "@y + 10; RETURN @y;');",
           "register p_basic");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_basic', 5);", "run p_basic");
  }

  printf("=== Testing variable overwrite ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_overwrite', '', 'DECLARE x = 1; SET x "
           "= 2; SET x = 3; RETURN @x;');",
           "register p_overwrite");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_overwrite');", "run p_overwrite");
  }

  printf("=== Testing IF true branch ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_if_true', '', 'IF (1) THEN RETURN "
           "\"yes\"; ELSE RETURN \"no\"; END IF;');",
           "register p_if_true");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_if_true');", "run p_if_true");
  }

  printf("=== Testing IF false branch ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_if_false', '', 'IF (0) THEN RETURN "
           "\"yes\"; ELSE RETURN \"no\"; END IF;');",
           "register p_if_false");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_if_false');", "run p_if_false");
  }

  printf("=== Testing IF no else ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_if_no_else', '', 'IF (0) THEN RETURN "
           "\"yes\"; END IF; RETURN \"default\";');",
           "register p_if_no_else");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_if_no_else');", "run p_if_no_else");
  }

  printf("=== Testing FOR loop with data ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_for', '', 'DECLARE sum = 0; FOR r IN "
           "(SELECT val FROM nums) LOOP SET sum = @sum + @r.val; END LOOP; "
           "RETURN @sum;');",
           "register p_for");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_for');", "run p_for");
  }

  printf("=== Testing FOR loop with empty result ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_for_empty', '', 'DECLARE count = 0; "
           "FOR r IN (SELECT * FROM empty_table) LOOP SET count = @count + 1; "
           "END LOOP; RETURN @count;');",
           "register p_for_empty");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_for_empty');", "run p_for_empty");
  }

  printf("=== Testing nested loops ===\n");
  exec_sql(
      db,
      "SELECT register_plsql('p_nested', '', 'DECLARE s = 0; FOR a IN "
      "(SELECT id FROM nums) LOOP FOR b IN (SELECT val FROM nums WHERE id = "
      "@a.id) LOOP SET s = @s + @b.val; END LOOP; END LOOP; RETURN @s;');",
      "register p_nested");
  for (int i = 0; i < 50; i++) {
    exec_sql(db, "SELECT run_plsql('p_nested');", "run p_nested");
  }

  printf("=== Testing cross-procedure access ===\n");
  exec_sql(
      db,
      "SELECT register_plsql('p_caller', '', 'DECLARE secret = 42; DECLARE "
      "updated = 0; SELECT run_plsql(\"p_getter\"); RETURN @updated;');",
      "register p_caller");
  exec_sql(db,
           "SELECT register_plsql('p_getter', '', 'DECLARE val = "
           "@p_caller.secret; SET p_caller.updated = @val + 8; RETURN @val;');",
           "register p_getter");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_caller');", "run p_caller");
  }

  printf("=== Testing namespaced SET ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_ns_set', '', 'SET other.value = 123; "
           "RETURN 1;');",
           "register p_ns_set");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_ns_set');", "run p_ns_set");
  }

  printf("=== Testing multiple arguments ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_multi_arg', 'a, b, c', 'RETURN @a + "
           "@b + @c;');",
           "register p_multi_arg");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_multi_arg', 1, 2, 3);",
             "run p_multi_arg");
  }

  printf("=== Testing no return ===\n");
  exec_sql(db, "SELECT register_plsql('p_no_return', '', 'DECLARE x = 1;');",
           "register p_no_return");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_no_return');", "run p_no_return");
  }

  printf("=== Testing SQL passthrough (INSERT) ===\n");
  exec_sql(db, "CREATE TABLE passthrough (val INTEGER);", "create passthrough");
  exec_sql(db,
           "SELECT register_plsql('p_insert', 'v', 'INSERT INTO "
           "passthrough VALUES (@v);');",
           "register p_insert");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_insert', 42);", "run p_insert");
  }

  printf("=== Testing UPDATE SET exclusion ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_update', '', 'UPDATE nums SET val = "
           "100 WHERE id = 1; SET x = 20; RETURN @x;');",
           "register p_update");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_update');", "run p_update");
  }

  printf("=== Testing hash collision stress ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_hash', '', 'DECLARE a1=1; DECLARE "
           "a2=2; DECLARE a3=3; DECLARE a4=4; DECLARE a5=5; DECLARE b1=1; "
           "DECLARE b2=2; DECLARE b3=3; DECLARE b4=4; DECLARE b5=5; DECLARE "
           "c1=1; DECLARE c2=2; DECLARE c3=3; DECLARE c4=4; DECLARE c5=5; "
           "RETURN @a1 + @a5 + @b1 + @b5 + @c1 + @c5;');",
           "register p_hash");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT run_plsql('p_hash');", "run p_hash");
  }

  printf("=== Testing atomicity (error rollback) ===\n");
  exec_sql(db, "CREATE TABLE balance (user_id INTEGER, amount REAL);",
           "create balance");
  exec_sql(db, "INSERT INTO balance VALUES (1, 100.0);", "insert balance");
  exec_sql(db,
           "SELECT register_plsql('p_risky', 'uid, amt', 'UPDATE balance "
           "SET amount = amount - @amt WHERE user_id = @uid; SELECT "
           "non_existent_func();');",
           "register p_risky");
  /* Intentionally trigger errors to test rollback */
  for (int i = 0; i < 50; i++) {
    sqlite3_exec(db, "SELECT run_plsql('p_risky', 1, 10.0);", 0, 0,
                 0); /* Ignore error */
  }

  printf("=== Testing procedure re-registration ===\n");
  for (int i = 0; i < 100; i++) {
    exec_sql(db, "SELECT register_plsql('p_rereg', '', 'RETURN 1;');",
             "re-register p_rereg");
  }

  printf("=== Testing Loop Runtime Error ===\n");
  /* Create a table that will cause an error during selection if we drop it or
     something, but simpler: use an invalid function in loop body query?
     Actually, let's use a division by zero in the loop query if possible, or
     just invalid SQL. */
  exec_sql(db,
           "SELECT register_plsql('p_loop_error', '', 'FOR r IN (SELECT 1/0) "
           "LOOP RETURN 1; END LOOP; RETURN 0;');",
           "register p_loop_error");
  exec_sql(db, "SELECT run_plsql('p_loop_error');",
           "run p_loop_error (should fail)");

  printf("=== Testing Deep Recursion Return ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_rec', 'n', 'IF (@n <= 0) THEN RETURN 0; "
           "END IF; RETURN @n + CALL p_rec(@n - 1);');",
           "register p_rec");
  exec_sql(db, "SELECT run_plsql('p_rec', 5);", "run p_rec recursion");

  printf("=== Testing Invalid SQL in SET (Runtime) ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_set_error', '', 'DECLARE x = 1; SET x = "
           "(SELECT * FROM non_existent_table); RETURN @x;');",
           "register p_set_error");
  exec_sql(db, "SELECT run_plsql('p_set_error');",
           "run p_set_error (should fail)");

  exec_sql(db, "SELECT run_plsql('p_set_error');",
           "run p_set_error (should fail)");

  printf("=== Testing Large String Manipulation ===\n");
  /* Concatenate strings to create a large value (~32KB) */
  exec_sql(db,
           "SELECT register_plsql('p_large_str', '', 'DECLARE s = ''x''; "
           "FOR i IN (WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 "
           "FROM cnt WHERE x<12) SELECT x FROM cnt) LOOP "
           "  SET s = (SELECT @s || @s); "
           "END LOOP; "
           "RETURN length(@s);');",
           "register p_large_str");
  exec_sql(db, "SELECT run_plsql('p_large_str');", "run p_large_str");

  printf("=== Testing Many Arguments (Stack/Parsing Stress) ===\n");
  /* 20 arguments */
  exec_sql(
      db,
      "SELECT register_plsql('p_many', "
      "'a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t', "
      "'RETURN @a+@b+@c+@d+@e+@f+@g+@h+@i+@j+@k+@l+@m+@n+@o+@p+@q+@r+@s+@t;');",
      "register p_many");
  exec_sql(
      db, "SELECT run_plsql('p_many',1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1);",
      "run p_many");

  printf("=== Testing Deeply Nested Static Scopes ===\n");
  /* Nested IFs to test scope pushing/popping without recursion */
  exec_sql(db,
           "SELECT register_plsql('p_nested_if', 'x', "
           "'IF (@x > 0) THEN "
           "  IF (@x > 1) THEN "
           "    IF (@x > 2) THEN "
           "      IF (@x > 3) THEN "
           "        RETURN 4; "
           "      END IF; "
           "      RETURN 3; "
           "    END IF; "
           "    RETURN 2; "
           "  END IF; "
           "  RETURN 1; "
           "END IF; "
           "RETURN 0;');",
           "register p_nested_if");
  for (int i = 0; i < 5; i++) {
    char buf[64];
    sprintf(buf, "SELECT run_plsql('p_nested_if', %d);", i);
    exec_sql(db, buf, "run p_nested_if");
  }

  printf("=== Testing RAISE statement (error propagation/rollback) ===\n");
  exec_sql(db,
           "SELECT register_plsql('p_fail', '', 'RAISE \"planned error\";');",
           "register p_fail");
  for (int i = 0; i < 50; i++) {
    sqlite3_exec(db, "SELECT run_plsql('p_fail');", 0, 0, 0);
  }

  printf("=== Testing Nested RAISE statement ===\n");
  exec_sql(db, "CREATE TABLE leak_t (val TEXT);", "create leak_t");
  exec_sql(db,
           "SELECT register_plsql('p_child_fail', '', 'INSERT INTO leak_t "
           "VALUES (\"data\"); RAISE \"child fail\";');",
           "register p_child_fail");
  exec_sql(db,
           "SELECT register_plsql('p_parent_fail', '', 'INSERT INTO leak_t "
           "VALUES (\"parent data\"); CALL p_child_fail();');",
           "register p_parent_fail");
  for (int i = 0; i < 50; i++) {
    sqlite3_exec(db, "SELECT run_plsql('p_parent_fail');", 0, 0, 0);
  }

  printf("Execution finished. Closing database...\n");
  sqlite3_close(db);

  printf("Leak check completed. Run this with Valgrind for detailed report.\n");
  printf("Command: valgrind --leak-check=full ./build/leak_check\n");

  return 0;
}
