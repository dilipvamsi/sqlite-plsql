package plsqlite

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

// Global API pointer (declared in sqlite.odin)

// validates the transpiled SQL by running an EXPLAIN query.
// This ensures that the generated SQL is syntactically correct and references valid tables/columns.
// Returns an error message if the SQL is invalid, or nil if it's valid.
validate_transpiled_sql :: proc "c" (db: ^sqlite3, sql: string) -> cstring {
	context = plsqlite_context()
	stmt: ^sqlite3_stmt
	explain_sql := fmt.tprintf("EXPLAIN %s", sql)
	c_explain := strings.clone_to_cstring(explain_sql)
	defer delete(c_explain)

	if prepare_v2(db, c_explain, -1, &stmt, nil) != SQLITE_OK {
		msg := errmsg(db)
		full_msg := fmt.tprintf("Invalid SQL in procedure: %s", msg)
		return strings.clone_to_cstring(full_msg)
	}

	finalize(stmt)
	return nil
}

// register_plsql_func is the implementation of the `register_plsql` SQL function.
// It takes 3 arguments:
// 1. Procedure Name (string)
// 2. Arguments Definition (string, e.g., "a, b")
// 3. Procedure Body (string, PL/SQL code)
//
// It transpiles the PL/SQL body into standard SQL and stores it in the `__plsql_procedures` table.
register_plsql_func :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil {
		result_error(ctx, "Internal Error: Connection Context not found", -1)
		return
	}

	if nArg < 3 {
		result_error(ctx, "register_plsql requires 3 arguments: name, args, body", -1)
		return
	}

	name_opt := value_text(apArg[0])
	args_opt := value_text(apArg[1])
	body_opt := value_text(apArg[2])

	name := string(name_opt)
	args_def := string(args_opt)
	body := string(body_opt)

	transpiled := transpile_plsqlite(body, name)
	defer delete(transpiled)

	db := context_db_handle(ctx)

	// Validate transpiled SQL
	if err_msg := validate_transpiled_sql(db, transpiled); err_msg != nil {
		result_error(ctx, err_msg, -1)
		return
	}

	stmt: ^sqlite3_stmt
	insert_sql := "INSERT OR REPLACE INTO __plsql_procedures (name, args, source_code, transpiled_sql) VALUES (?, ?, ?, ?);"
	c_insert_sql := strings.clone_to_cstring(insert_sql)
	defer delete(c_insert_sql)

	if prepare_v2(db, c_insert_sql, -1, &stmt, nil) == SQLITE_OK {
		c_name := strings.clone_to_cstring(name)
		c_args := strings.clone_to_cstring(args_def)
		c_body := strings.clone_to_cstring(body)
		c_transpiled := strings.clone_to_cstring(transpiled)

		bind_text(stmt, 1, c_name, -1, SQLITE_TRANSIENT)
		bind_text(stmt, 2, c_args, -1, SQLITE_TRANSIENT)
		bind_text(stmt, 3, c_body, -1, SQLITE_TRANSIENT)
		bind_text(stmt, 4, c_transpiled, -1, SQLITE_TRANSIENT)

		step(stmt)
		finalize(stmt)

		delete(c_name)
		delete(c_args)
		delete(c_body)
		delete(c_transpiled)

		// Invalidate cache for this procedure
		if p, ok := conn.procedure_cache[name]; ok {
			for i := 0; i < len(p.stmts_pool); i += 1 {
				stmts := &p.stmts_pool[i]
				for st in stmts {
					finalize(st)
				}
				clear(stmts)
			}
			clear(&p.stmts_pool)
			// We can keep the proc object but clear statements to force re-prepare
			if p.transpiled_sql != transpiled {
				delete(p.transpiled_sql)
				p.transpiled_sql = strings.clone(transpiled)
			}
		}
	}

	result_text(ctx, "Procedure registered successfully", -1, SQLITE_TRANSIENT)
}

// run_plsql_func is the implementation of the `run_plsql` SQL function.
// It takes the procedure name as the first argument, followed by any arguments expected by the procedure.
//
// It retrieves the transpiled SQL from `__plsql_procedures`, creates a new scope,
// binds arguments, and executes the transpiled SQL. It handles transaction management (SAVEPOINT/ROLLBACK)
// and error propagation.
run_plsql_func :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil {
		result_error(ctx, "Internal Error: Connection Context not found", -1)
		return
	}

	if nArg < 1 {
		result_error(ctx, "run_plsql requires at least 1 argument: procedure name", -1)
		return
	}

	name_ptr := value_text(apArg[0])
	name := string(name_ptr)

	db := context_db_handle(ctx)

	stmt: ^sqlite3_stmt
	select_sql := "SELECT args, source_code, transpiled_sql FROM __plsql_procedures WHERE name = ?;"
	c_select_sql := strings.clone_to_cstring(select_sql)
	defer delete(c_select_sql)

	if prepare_v2(db, c_select_sql, -1, &stmt, nil) != SQLITE_OK {
		result_error(ctx, errmsg(db), -1)
		return
	}
	defer finalize(stmt)

	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)
	// Bind the procedure name to the SELECT query
	bind_text(stmt, 1, c_name, -1, SQLITE_TRANSIENT)

	if step(stmt) == SQLITE_ROW {
		// Found the procedure, extract definition
		args_def := string(column_text(stmt, 0))
		// source_code := string(column_text(stmt, 1)) // Unused
		transpiled := string(column_text(stmt, 2))

		if !scope_push(conn, name) {
			err_msg := strings.clone_to_cstring("PL/SQL recursion limit exceeded")
			defer delete(err_msg)
			result_error(ctx, err_msg, -1)
			return
		}

		// Bind arguments
		bind_procedure_arguments(conn, args_def, nArg, apArg)

		// Execute transpiled SQL
		// Start a savepoint for transaction management within the procedure
		savepoint_sql := fmt.tprintf("SAVEPOINT sp_%s", name)
		c_savepoint := strings.clone_to_cstring(savepoint_sql)
		defer delete(c_savepoint)
		exec(db, c_savepoint, nil, nil, nil)

		// OPTIMIZATION: Use Procedure Statement Cache
		depth := scope_depth(conn, name)
		stmts, ok_p := get_procedure_stmts(conn, db, name, transpiled, depth)
		success := false
		if ok_p && len(stmts) > 0 {
			success = execute_stmts(conn, db, stmts, true)
		} else {
			// Fallback to exec (should not happen if registered correctly)
			c_transpiled := strings.clone_to_cstring(transpiled)
			rc := exec(db, c_transpiled, exec_callback, conn, nil)
			delete(c_transpiled)
			success = (rc == SQLITE_OK || rc == SQLITE_DONE)
		}

		if !success {
			// If error and not a normal RETURN, rollback
			if !conn.current_scope_top.stop_execution || conn.current_scope_top.is_error {
				// Capture error message before rollback clears it
				c_msg := errmsg(db)
				msg_str := ""
				if c_msg != nil {
					msg_str = string(c_msg)
				}
				saved_msg := strings.clone(msg_str)
				defer delete(saved_msg)

				// Rollback the transaction for this procedure call
				rollback_sql := fmt.tprintf("ROLLBACK TO sp_%s", name)
				c_rollback := strings.clone_to_cstring(rollback_sql)
				defer delete(c_rollback)
				exec(db, c_rollback, nil, nil, nil)

				final_msg: cstring
				if len(saved_msg) == 0 || saved_msg == "not an error" {
					final_msg = strings.clone_to_cstring(
						"PL/SQL execution failed (possible recursion limit or inner error)",
					)
				} else {
					final_msg = strings.clone_to_cstring(saved_msg)
				}
				defer delete(final_msg)

				result_error(ctx, final_msg, -1)
				scope_pop(conn, false)
				return
			}
			// If stop_execution is true, it might be a RETURN which aborts exec.
			// In that case we release savepoint and return value.
		}

		release_sql := fmt.tprintf("RELEASE SAVEPOINT sp_%s", name)
		c_release := strings.clone_to_cstring(release_sql)
		defer delete(c_release)
		exec(db, c_release, nil, nil, nil)

		log_debug(
			"Run PLSQL: name=%s, has_returned=%v, stop_execution=%v",
			name,
			conn.current_scope_top.has_returned,
			conn.current_scope_top.stop_execution,
		)
		if conn.current_scope_top.has_returned {
			val := conn.current_scope_top.return_value
			log_debug("Return Value set, processing switch")
			switch v in val {
			case i64:
				log_debug("Returning i64: %d", v)
				result_int64(ctx, v)
			case f64:
				log_debug("Returning f64: %f", v)
				result_double(ctx, v)
			case string:
				log_debug("Returning string: %s", v)
				c_val := strings.clone_to_cstring(v)
				defer delete(c_val)
				result_text(ctx, c_val, -1, SQLITE_TRANSIENT)
			case []byte:
				log_debug("Returning blob, len=%d", len(v))
				result_blob(ctx, raw_data(v), c.int(len(v)), SQLITE_TRANSIENT)
			case:
				log_debug("Returning NULL (unhandled or nil case)")
				result_null(ctx)
			}
		} else {
			result_null(ctx)
		}

		scope_pop(conn, false) // Don't propagate stop_execution out of the procedure call
	} else {
		err_msg := fmt.tprintf("Procedure not found: %s", name)
		c_err_msg := strings.clone_to_cstring(err_msg)
		defer delete(c_err_msg)
		result_error(ctx, c_err_msg, -1)
	}
}

// bind_procedure_arguments parses the argument definition string and binds the provided
// values to the current scope. It supports typed values (Integer, Float, Text, Blob, Null).
bind_procedure_arguments :: proc(
	ctx: ^ConnectionContext,
	args_def_str: string,
	nArg: c.int,
	apArg: [^]^sqlite3_value,
) {
	if len(args_def_str) == 0 {
		return
	}

	// Bind arguments to new scope
	args := strings.split(args_def_str, ",")
	// clean up split results properly
	defer delete(args)

	for arg_name, i in args {
		trimmed_name := strings.trim_space(arg_name)
		if i + 1 < int(nArg) {
			// Extract typed value
			var_val: SqliteValue
			v_type := value_type(apArg[i + 1])
			switch v_type {
			case SQLITE_INTEGER:
				var_val = value_int64(apArg[i + 1])
			case SQLITE_FLOAT:
				var_val = value_double(apArg[i + 1])
			case SQLITE_TEXT:
				text_ptr := value_text(apArg[i + 1])
				if text_ptr != nil {
					var_val = strings.clone(string(text_ptr))
				} else {
					var_val = nil
				}
			case SQLITE_BLOB:
				blob_ptr := value_blob(apArg[i + 1])
				blob_bytes := value_bytes(apArg[i + 1])
				if blob_ptr != nil && blob_bytes > 0 {
					data := make([]byte, blob_bytes)
					mem.copy(raw_data(data), blob_ptr, int(blob_bytes))
					var_val = data
				} else {
					var_val = nil
				}
			case SQLITE_NULL:
				var_val = nil
			case:
				text_ptr := value_text(apArg[i + 1])
				if text_ptr != nil {
					var_val = strings.clone(string(text_ptr))
				} else {
					var_val = nil
				}
			}

			if ctx.current_scope_top != nil {
				if trimmed_name in ctx.current_scope_top.variables {
					old_val := ctx.current_scope_top.variables[trimmed_name]
					free_sqlite_value(old_val)
					ctx.current_scope_top.variables[trimmed_name] = var_val
				} else {
					ctx.current_scope_top.variables[strings.clone(trimmed_name)] = var_val
				}
			} else {
				// Should not happen if scope_push called correctly
				free_sqlite_value(var_val)
			}
		}
	}
}

// sqlite3_extension_init is the entry point for the SQLite extension.
// It initializes the Odin runtime context, sets up the API pointer, creates the metadata table,
// and registers all internal (`__env_*`, `__run_if`, `__proc_loop`) and public (`register_plsql`, `run_plsql`) functions.
@(export)
@(link_name = "sqlite3_plsqlite_init")
sqlite3_extension_init :: proc "c" (
	db: ^sqlite3,
	pzErrMsg: ^cstring,
	pApi: ^sqlite3_api_routines,
) -> c.int {
	context = plsqlite_context()
	api = pApi

	// Initialize debug flag
	debug_env := os.get_env("PLSQL_DEBUG")
	DEBUG_ENABLED = debug_env == "1" || debug_env == "true"
	if DEBUG_ENABLED {
		fmt.println("[PLSQL] Debug logging ENABLED")
	}

	// Create metadata table
	sql := "CREATE TABLE IF NOT EXISTS __plsql_procedures (name TEXT PRIMARY KEY, args TEXT, source_code TEXT, transpiled_sql TEXT);"
	c_sql := strings.clone_to_cstring(sql)
	defer delete(c_sql)
	if exec(db, c_sql, nil, nil, pzErrMsg) != SQLITE_OK do return 1

	// Initialize Per-Connection Context
	ctx := create_connection_context()
	ctx.ref_count = 11 // 11 registered functions

	// Register close hook to finalize statements before connection closes
	trace_v2(db, SQLITE_TRACE_CLOSE, close_hook, ctx)

	// Register internal functions
	create_function_v2(db, "__env_set", 3, SQLITE_UTF8, ctx, __env_set, nil, nil, ctx_release)
	create_function_v2(db, "__env_get", 2, SQLITE_UTF8, ctx, __env_get, nil, nil, ctx_release)
	create_function_v2(
		db,
		"__env_return",
		1,
		SQLITE_UTF8,
		ctx,
		__env_return,
		nil,
		nil,
		ctx_release,
	)
	create_function_v2(db, "__run_if", 3, SQLITE_UTF8, ctx, __run_if, nil, nil, ctx_release)
	create_function_v2(db, "__proc_loop", 4, SQLITE_UTF8, ctx, __proc_loop, nil, nil, ctx_release)
	create_function_v2(
		db,
		"__range_loop",
		6,
		SQLITE_UTF8,
		ctx,
		__range_loop,
		nil,
		nil,
		ctx_release,
	)
	create_function_v2(db, "__env_raise", 1, SQLITE_UTF8, ctx, __env_raise, nil, nil, ctx_release)

	// Register public functions
	create_function_v2(
		db,
		"register_plsql",
		3,
		SQLITE_UTF8,
		ctx,
		register_plsql_func,
		nil,
		nil,
		ctx_release,
	)
	create_function_v2(
		db,
		"run_plsql",
		-1,
		SQLITE_UTF8,
		ctx,
		run_plsql_func,
		nil,
		nil,
		ctx_release,
	)
	create_function_v2(db, "os_getenv", 1, SQLITE_UTF8, ctx, os_getenv, nil, nil, ctx_release)

	create_function_v2(
		db,
		"__plsql_leak_report",
		0,
		SQLITE_UTF8,
		ctx,
		__plsql_leak_report,
		nil,
		nil,
		ctx_release,
	)

	return SQLITE_OK
}
