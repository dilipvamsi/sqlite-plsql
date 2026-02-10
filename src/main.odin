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
validate_transpiled_sql :: proc "c" (db: ^sqlite3, sql: cstring, length: c.int) -> cstring {
	context = plsqlite_context()
	stmt: ^sqlite3_stmt
	explain_sql := fmt.ctprintf("EXPLAIN %.*s", length, sql)
	c_explain := explain_sql

	if prepare_v2(db, c_explain, -1, &stmt, nil) != SQLITE_OK {
		msg := errmsg(db)
		return fmt.ctprintf("Invalid SQL in procedure: %s", msg)
	}

	finalize(stmt)
	return nil
}

register_procedure_internal :: proc(
	ctx: ^sqlite3_context,
	conn: ^ConnectionContext,
	name: cstring,
	args_def: cstring,
	body: cstring,
) -> bool {
	db := context_db_handle(ctx)
	body_str := string(body)
	name_str := string(name)
	transpiled := transpile_plsqlite(body_str, name_str)
	defer delete(transpiled)

	// Validate transpiled SQL
	if err_msg := validate_transpiled_sql(
		db,
		cstring(raw_data(transpiled)),
		c.int(len(transpiled)),
	); err_msg != nil {
		result_error(ctx, err_msg, -1)
		return false
	}

	stmt: ^sqlite3_stmt
	c_insert_sql := cstring(
		"INSERT OR REPLACE INTO __plsql_procedures (name, args, source_code, transpiled_sql) VALUES (?, ?, ?, ?);",
	)

	if prepare_v2(db, c_insert_sql, -1, &stmt, nil) == SQLITE_OK {
		bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
		bind_text(stmt, 2, args_def, -1, SQLITE_TRANSIENT)
		bind_text(stmt, 3, body, -1, SQLITE_TRANSIENT)
		bind_text(stmt, 4, cstring(raw_data(transpiled)), c.int(len(transpiled)), SQLITE_TRANSIENT)

		step(stmt)
		finalize(stmt)

		// Invalidate cache for this procedure in the current connection
		if p, ok := conn.procedure_cache[name_str]; ok {
			for i := 0; i < len(p.stmts_pool); i += 1 {
				stmts := &p.stmts_pool[i]
				for st in stmts^ {
					finalize(st)
				}
				clear(stmts)
			}
			clear(&p.stmts_pool)

			if string(p.transpiled_sql) != transpiled {
				delete(p.transpiled_sql)
				p.transpiled_sql = strings.clone_to_cstring(transpiled)
			}
			args_def_str := string(args_def)
			if p.args_def != args_def_str {
				delete(p.args_def)
				p.args_def = strings.clone(args_def_str)
				for n in p.arg_names do delete(n)
				delete(p.arg_names)
				p.arg_names = parse_arg_names(p.args_def)
			}
		}
		return true
	} else {
		result_error(ctx, errmsg(db), -1)
		return false
	}
}

// register_plsql_func is the implementation of the `register_plsql` SQL function.
// It takes 3 arguments:
// 1. Procedure Name (string)
// 2. Arguments Definition (string, e.g., "a, b")
// 3. Procedure Body (string, PL/SQL code)
register_plsql_func :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)

	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil {
		result_error(ctx, "Internal Error: Connection Context not found", -1)
		return
	}

	if nArg < 3 {
		result_error(ctx, "register_plsql requires 3 arguments: name, args, body", -1)
		return
	}

	name := value_text(apArg[0])
	args_def := value_text(apArg[1])
	body := value_text(apArg[2])

	if register_procedure_internal(ctx, conn, name, args_def, body) {
		result_text(ctx, "Procedure registered successfully", -1, SQLITE_TRANSIENT)
	}
}

// replace_plsql_func is the implementation of the `replace_plsql` SQL function.
// It is an alias for register_plsql but explicitly signals update intent.
replace_plsql_func :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil {
		result_error(ctx, "Internal Error: Connection Context not found", -1)
		return
	}

	if nArg < 3 {
		result_error(ctx, "replace_plsql requires 3 arguments: name, args, body", -1)
		return
	}

	name := value_text(apArg[0])
	args_def := value_text(apArg[1])
	body := value_text(apArg[2])

	if register_procedure_internal(ctx, conn, name, args_def, body) {
		result_text(ctx, "Procedure replaced successfully", -1, SQLITE_TRANSIENT)
	}
}

// unregister_plsql_func is the implementation of the `unregister_plsql` SQL function.
// It takes 1 argument: the procedure name.
unregister_plsql_func :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil {
		result_error(ctx, "Internal Error: Connection Context not found", -1)
		return
	}

	if nArg < 1 {
		result_error(ctx, "unregister_plsql requires 1 argument: procedure name", -1)
		return
	}

	name_ptr := value_text(apArg[0])
	if name_ptr == nil {
		result_error(ctx, "NULL procedure name", -1)
		return
	}
	name := string(name_ptr)

	db := context_db_handle(ctx)

	log_debug("Unregistering procedure: %s", name)

	// 1. Remove from DB
	stmt: ^sqlite3_stmt
	c_delete_sql := cstring("DELETE FROM __plsql_procedures WHERE name = ?;")

	if prepare_v2(db, c_delete_sql, -1, &stmt, nil) == SQLITE_OK {
		bind_text(stmt, 1, name_ptr, -1, SQLITE_TRANSIENT)
		step(stmt)
		finalize(stmt)

		// 2. Invalidate and remove from cache
		if p, ok := conn.procedure_cache[name]; ok {
			log_debug("Removing procedure from cache: %s", name)
			// Remove from map FIRST so other threads/calls don't see it
			delete_key(&conn.procedure_cache, name)

			// Finalize pooled statements
			for i := 0; i < len(p.stmts_pool); i += 1 {
				stmts := &p.stmts_pool[i]
				for st in stmts {
					finalize(st)
				}
				delete(stmts^)
			}
			delete(p.stmts_pool)
			for n in p.arg_names {
				delete(n)
			}
			delete(p.arg_names)
			delete(p.transpiled_sql)
			delete(p.args_def)
			delete(p.name) // This is the cloned string that was the key
			free(p)
		} else {
			log_debug("Procedure not found in cache: %s", name)
		}

		result_text(ctx, "Procedure unregistered successfully", -1, SQLITE_TRANSIENT)
	} else {
		err_msg := errmsg(db)
		log_debug("Failed to prepare delete SQL: %s", err_msg)
		result_error(ctx, err_msg, -1)
	}
}

// run_plsql_func is the implementation of the `run_plsql` SQL function.
// It takes the procedure name as the first argument, followed by any arguments expected by the procedure.
//
// It retrieves the transpiled SQL from `__plsql_procedures`, creates a new scope,
// binds arguments, and executes the transpiled SQL. It handles transaction management (SAVEPOINT/ROLLBACK)
// and error propagation.
run_plsql_func :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)

	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil {
		result_error(ctx, "Internal Error: Connection Context not found", -1)
		return
	}

	if nArg < 1 {
		result_error(ctx, "run_plsql requires at least 1 argument: procedure name", -1)
		return
	}

	c_name := value_text(apArg[0])
	name := string(c_name)

	db := context_db_handle(ctx)

	stmt: ^sqlite3_stmt
	c_select_sql := cstring(
		"SELECT args, source_code, transpiled_sql FROM __plsql_procedures WHERE name = ?;",
	)

	if prepare_v2(db, c_select_sql, -1, &stmt, nil) != SQLITE_OK {
		result_error(ctx, errmsg(db), -1)
		return
	}
	defer finalize(stmt)

	// Bind the procedure name to the SELECT query
	bind_text(stmt, 1, c_name, -1, SQLITE_TRANSIENT)

	if step(stmt) == SQLITE_ROW {
		// Found the procedure, extract definition
		args_def_cs := column_text(stmt, 0)
		transpiled_cs := column_text(stmt, 2)

		if !scope_push(conn, c_name) {
			err_msg := cstring("PL/SQL recursion limit exceeded")
			result_error(ctx, err_msg, -1)
			return
		}

		// OPTIMIZATION: Use Procedure Statement Cache
		depth := scope_depth(conn, c_name)
		stmts, ok_p := get_procedure_stmts(conn, db, c_name, args_def_cs, transpiled_cs, depth)

		if !ok_p {
			result_error(ctx, "Failed to retrieve procedure statements", -1)
			return
		}

		// Bind arguments using pre-parsed names from cache
		proc_obj := conn.procedure_cache[name]
		bind_procedure_arguments(conn, proc_obj.arg_names, nArg, apArg)

		// Execute transpiled SQL
		// Start a savepoint for transaction management within the procedure
		c_savepoint_sql := fmt.ctprintf("SAVEPOINT sp_%s", name)
		exec(db, c_savepoint_sql, nil, nil, nil)

		success := execute_stmts(conn, db, stmts, true)

		if !success {
			// If error and not a normal RETURN, rollback
			if !conn.current_scope_top.stop_execution || conn.current_scope_top.is_error {
				// Capture error message before rollback clears it
				saved_msg := fmt.ctprintf("%s", errmsg(db))

				// Rollback the transaction for this procedure call
				rollback_sql := fmt.ctprintf("ROLLBACK TO sp_%s", name)
				exec(db, rollback_sql, nil, nil, nil)

				final_msg: cstring
				if len(saved_msg) == 0 || saved_msg == "not an error" {
					final_msg = fmt.ctprintf(
						"PL/SQL execution failed (possible recursion limit or inner error)",
					)
				} else {
					final_msg = fmt.ctprintf("%s", saved_msg)
				}
				// final_msg is on temp allocator, will be freed by caller's free_all
				result_error(ctx, final_msg, -1)
				scope_pop(conn, false)
				return
			}
			// If stop_execution is true, it might be a RETURN which aborts exec.
			// In that case we release savepoint and return value.
		}

		release_sql := fmt.ctprintf("RELEASE SAVEPOINT sp_%s", name)
		exec(db, release_sql, nil, nil, nil)

		log_debug(
			"Run PLSQL: name=%s, has_returned=%v, stop_execution=%v",
			c_name,
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
			case cstring:
				log_debug("Returning cstring: %s", v)
				result_text(ctx, v, -1, SQLITE_TRANSIENT)
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
		err_msg := fmt.ctprintf("Procedure not found: %s", name)
		result_error(ctx, err_msg, -1)
	}
}

// bind_procedure_arguments parses the argument definition string and binds the provided
// values to the current scope. It supports typed values (Integer, Float, Text, Blob, Null).
bind_procedure_arguments :: proc(
	ctx: ^ConnectionContext,
	arg_names: []string,
	nArg: c.int,
	apArg: [^]^sqlite3_value,
) {
	for trimmed_name, i in arg_names {
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
				var_val = value_clone_text(apArg[i + 1])
			case SQLITE_BLOB:
				var_val = value_clone_blob(apArg[i + 1])
			case SQLITE_NULL:
				var_val = nil
			case:
				var_val = value_clone_text(apArg[i + 1])
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

// register_function is a helper to automate ConnectionContext reference counting.
register_function :: proc(
	db: ^sqlite3,
	name: cstring,
	nArg: c.int,
	ctx: ^ConnectionContext,
	xFunc: proc "c" (ctx: ^sqlite3_context, n: c.int, v: [^]^sqlite3_value),
) {
	create_function_v2(db, name, nArg, SQLITE_UTF8, ctx, xFunc, nil, nil, ctx_release)
	ctx.ref_count += 1
}

// register_trace is a helper to automate ConnectionContext reference counting for trace callbacks.
register_trace :: proc(
	db: ^sqlite3,
	mask: c.uint,
	ctx: ^ConnectionContext,
	xCallback: proc "c" (t: c.uint, db_ptr: rawptr, p: rawptr, x: rawptr) -> c.int,
) {
	trace_v2(db, mask, xCallback, ctx)
	ctx.ref_count += 1
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
	debug_env, debug_exists := os.lookup_env("PLSQL_DEBUG")
	if debug_exists {
		DEBUG_ENABLED = debug_env == "1" || debug_env == "true"
		delete(debug_env)
	}
	if DEBUG_ENABLED {
		fmt.println("[PLSQL] Debug logging ENABLED")
	}

	// Create metadata table
	c_sql := cstring(
		"CREATE TABLE IF NOT EXISTS __plsql_procedures (name TEXT PRIMARY KEY, args TEXT, source_code TEXT, transpiled_sql TEXT);",
	)
	if exec(db, c_sql, nil, nil, pzErrMsg) != SQLITE_OK do return 1

	// Initialize Per-Connection Context
	ctx := create_connection_context()

	// Register close hook to finalize statements before connection closes
	register_trace(db, SQLITE_TRACE_CLOSE, ctx, close_hook)

	// Register internal functions
	register_function(db, "__env_set", 3, ctx, __env_set)
	register_function(db, "__env_get", 2, ctx, __env_get)
	register_function(db, "__env_return", 1, ctx, __env_return)
	register_function(db, "__run_if", 3, ctx, __run_if)
	register_function(db, "__proc_loop", 4, ctx, __proc_loop)
	register_function(db, "__range_loop", 6, ctx, __range_loop)
	register_function(db, "__env_raise", 1, ctx, __env_raise)
	register_function(db, "__plsql_reset", 0, ctx, __plsql_reset)

	// Register public functions
	register_function(db, "register_plsql", 3, ctx, register_plsql_func)
	register_function(db, "replace_plsql", 3, ctx, replace_plsql_func)
	register_function(db, "unregister_plsql", 1, ctx, unregister_plsql_func)
	register_function(db, "run_plsql", -1, ctx, run_plsql_func)
	register_function(db, "os_getenv", 1, ctx, os_getenv)
	register_function(db, "__plsql_leak_report", 0, ctx, __plsql_leak_report)

	return SQLITE_OK
}
