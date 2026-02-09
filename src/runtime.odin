package plsqlite

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

// Scope represents a single execution context (stack frame) for a procedure call.
// It stores local variables, return values, and tracks the execution state (e.g., if a RETURN statement was hit).
Scope :: struct {
	proc_name:      string,
	variables:      map[string]SqliteValue,
	prev:           ^Scope,
	return_value:   SqliteValue,
	has_returned:   bool,
	// return_is_null: bool, // No longer needed, SqliteValue can be nil
	stop_execution: bool,
	depth:          int,
	is_error:       bool,
	// Optimization: Statement Cache
	// Stores compiled statements for this scope (mostly for the root scope of a procedure)
	// Key: SQL Source String, Value: List of prepared statements (handles multi-statement blocks)
	stmt_cache:     map[string][dynamic]^sqlite3_stmt,
	is_transient:   bool, // If true, don't cache here, look up parent (e.g., loop scopes)
	is_procedure:   bool, // If true, this is the root scope of a procedure call
}

// Procedure stores cached metadata and prepared statements for a registered PL/SQL function.
Procedure :: struct {
	name:           string,
	args_def:       string,
	transpiled_sql: string,
	stmts_pool:     [dynamic][dynamic]^sqlite3_stmt, // Each index corresponds to a recursion depth
}

// ConnectionContext stores all state tied to a single SQLite database connection.
ConnectionContext :: struct {
	magic:             u64,
	procedure_cache:   map[string]^Procedure,
	current_scope_top: ^Scope,
	ref_count:         int,
}

CONNECTION_CONTEXT_MAGIC :: 0xCAFEBABECAFEBABE

create_connection_context :: proc() -> ^ConnectionContext {
	ctx := new(ConnectionContext)
	ctx.magic = CONNECTION_CONTEXT_MAGIC
	ctx.procedure_cache = make(map[string]^Procedure)
	ctx.ref_count = 0
	return ctx
}

destroy_connection_context :: proc(ctx: ^ConnectionContext) {
	if ctx == nil do return
	log_debug("Destroying ConnectionContext: %p", ctx)

	// Finalize all remaining scopes (should be empty but just in case)
	for ctx.current_scope_top != nil {
		scope_pop(ctx, false)
	}

	free_procedure_cache(ctx)
	delete(ctx.procedure_cache)
	free(ctx)
	log_debug("ConnectionContext destroyed: %p", ctx)
}

// close_hook is called when the database connection is closing.
// It ensures all cached statements are finalized before the DB handle is destroyed.
close_hook :: proc "c" (t: c.uint, db_ptr: rawptr, p: rawptr, x: rawptr) -> c.int {
	if t != SQLITE_TRACE_CLOSE do return 0
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	ctx := (^ConnectionContext)(db_ptr) // db_ptr is the pCtx argument passed to trace_v2
	if ctx != nil && ctx.magic == CONNECTION_CONTEXT_MAGIC {
		log_debug("Close Hook: Magic Validated")
		finalize_all_statements(ctx)
		ctx_release(ctx)
	} else {
		log_debug("Close Hook: INVALID MAGIC %p (expected context in db_ptr)", db_ptr)
	}
	return 0
}

// ctx_release is an xDestroy callback for SQLite functions to handle reference-counted cleanup.
ctx_release :: proc "c" (pApp: rawptr) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	ctx := (^ConnectionContext)(pApp)
	if ctx == nil do return

	log_debug("Ctx Release: ctx=%p, current_ref_count=%d", ctx, ctx.ref_count)
	ctx.ref_count -= 1
	if ctx.ref_count <= 0 {
		destroy_connection_context(ctx)
	}
}

MAX_RECURSION_DEPTH :: 500

// SqliteValue is a typed union representing the value of a variable or expression result in SQLite.
// It supports Integer, Float, Text, and Blob types. NULL is represented implicitly by the union's nil state.
SqliteValue :: union {
	i64,
	f64,
	string,
	[]byte, // BLOB support
	// nil represents NULL
}

DEBUG_ENABLED: bool

log_debug :: proc(format: string, args: ..any) {
	if DEBUG_ENABLED {
		fmt.printf("[PLSQL DEBUG] ")
		fmt.printf(format, ..args)
		fmt.println()
	}
}

free_sqlite_value :: proc(val: SqliteValue) {
	switch v in val {
	case string:
		delete(v)
	case []byte:
		delete(v)
	case i64:
	case f64:
	case: // nil
	}
}

// free_scope_cache finalizes all cached statements and frees memory
free_scope_cache :: proc(s: ^Scope) {
	for key, stmts in s.stmt_cache {
		for stmt in stmts {
			finalize(stmt)
		}
		delete(stmts)
		delete(key) // We clone keys
	}
	delete(s.stmt_cache)
}

clone_sqlite_value :: proc(val: SqliteValue) -> SqliteValue {
	switch v in val {
	case string:
		return strings.clone(v)
	case []byte:
		return slice.clone(v)
	case i64:
		return v
	case f64:
		return v
	case:
		return nil
	}
}

// scope_depth counts how many times the given procedure is currently on the stack.
// This is used to determine the index into the statement pool for recursion.
scope_depth :: proc(ctx: ^ConnectionContext, name: string) -> int {
	count := 0
	curr := ctx.current_scope_top
	for curr != nil {
		if curr.is_procedure && curr.proc_name == name {
			count += 1
		}
		curr = curr.prev
	}
	return count
}

// scope_push creates a new scope for a procedure call and pushes it onto the scope stack.
scope_push :: proc(ctx: ^ConnectionContext, name: string, is_transient := false) -> bool {
	if ctx.current_scope_top != nil && ctx.current_scope_top.depth >= MAX_RECURSION_DEPTH {
		return false
	}
	new_s := new(Scope)
	new_s.proc_name = strings.clone(name)
	new_s.variables = make(map[string]SqliteValue)
	new_s.prev = ctx.current_scope_top
	if ctx.current_scope_top != nil {
		new_s.depth = ctx.current_scope_top.depth + 1
	} else {
		new_s.depth = 1
	}
	new_s.is_transient = is_transient
	new_s.is_procedure = (name != "" && !is_transient)
	new_s.stmt_cache = make(map[string][dynamic]^sqlite3_stmt)
	ctx.current_scope_top = new_s
	log_debug("Scope Push: name=%s, transient=%v, depth=%d", name, is_transient, new_s.depth)
	return true
}

// scope_pop removes the current scope from the stack, cleaning up all allocated memory for variables.
scope_pop :: proc(ctx: ^ConnectionContext, propagate: bool) {
	if ctx.current_scope_top != nil {
		tmp := ctx.current_scope_top
		ctx.current_scope_top = tmp.prev
		top := ctx.current_scope_top

		if propagate && tmp.stop_execution && top != nil {
			top.stop_execution = true
			if tmp.has_returned {
				free_sqlite_value(top.return_value)
				top.return_value = clone_sqlite_value(tmp.return_value)
				top.has_returned = true
			}
			if tmp.is_error {
				top.is_error = true
			}
		}

		log_debug("Scope Pop: name=%s, returned=%v", tmp.proc_name, tmp.has_returned)
		delete(tmp.proc_name)
		for k, v in tmp.variables {
			delete(k)
			free_sqlite_value(v)
		}
		delete(tmp.variables)
		free_sqlite_value(tmp.return_value)
		free_scope_cache(tmp)
		free(tmp)
	}
}

// get_cache_scope returns the nearest non-transient scope suitable for caching statements.
get_cache_scope :: proc(ctx: ^ConnectionContext) -> ^Scope {
	iter := ctx.current_scope_top
	for iter != nil && iter.is_transient && iter.prev != nil {
		iter = iter.prev
	}
	return iter
}

// get_cached_stmts returns a list of prepared statements for the given SQL.
get_cached_stmts :: proc(
	conn: ^ConnectionContext,
	db: ^sqlite3,
	sql: string,
) -> (
	[dynamic]^sqlite3_stmt,
	bool,
) {
	if len(sql) == 0 do return nil, true

	s := get_cache_scope(conn)
	if s == nil do return nil, false

	// Check cache
	if stmts, ok := s.stmt_cache[sql]; ok {
		return stmts, true
	}

	// Cache miss: Prepare all statements in the string
	stmts := make([dynamic]^sqlite3_stmt)

	remaining := sql
	for len(remaining) > 0 {
		stmt: ^sqlite3_stmt
		tail: cstring
		c_sql := strings.clone_to_cstring(remaining)
		defer delete(c_sql)

		rc := prepare_v2(db, c_sql, -1, &stmt, &tail)
		if rc != SQLITE_OK {
			// Cleanup on error
			for st in stmts do finalize(st)
			delete(stmts)
			return nil, false
		}

		if stmt != nil {
			append(&stmts, stmt)
		}

		// Advance remaining
		if tail == nil || (cast([^]u8)tail)[0] == 0 {
			break
		}

		// Calculate offset
		bytes_consumed := uintptr(rawptr(tail)) - uintptr(rawptr(c_sql))
		if int(bytes_consumed) >= len(remaining) {
			break
		}
		remaining = remaining[bytes_consumed:]
		remaining = strings.trim_left_space(remaining)
	}

	// Cache it
	key := strings.clone(sql)
	s.stmt_cache[key] = stmts
	return stmts, true
}

// get_procedure_stmts returns the cached statements for a procedure, preparing them if necessary.
// It handles recursion by returning a different set of statements for each depth.
get_procedure_stmts :: proc(
	ctx: ^ConnectionContext,
	db: ^sqlite3,
	name: string,
	transpiled_sql: string,
	depth: int,
) -> (
	[dynamic]^sqlite3_stmt,
	bool,
) {
	proc_obj, ok := ctx.procedure_cache[name]
	if !ok {
		// Create new procedure object
		proc_obj = new(Procedure)
		proc_obj.name = strings.clone(name)
		proc_obj.transpiled_sql = strings.clone(transpiled_sql)
		proc_obj.stmts_pool = make([dynamic][dynamic]^sqlite3_stmt)
		ctx.procedure_cache[proc_obj.name] = proc_obj
	}

	// Ensure the pool is large enough for the current depth
	for len(proc_obj.stmts_pool) < depth {
		append(&proc_obj.stmts_pool, make([dynamic]^sqlite3_stmt))
	}

	stmts := &proc_obj.stmts_pool[depth - 1]
	if len(stmts^) > 0 {
		return stmts^, true
	}

	// Prepare statements for this specific depth
	remaining := proc_obj.transpiled_sql
	for len(remaining) > 0 {
		stmt: ^sqlite3_stmt
		tail: cstring
		c_sql := strings.clone_to_cstring(remaining)
		defer delete(c_sql)

		rc := prepare_v2(db, c_sql, -1, &stmt, &tail)
		if rc != SQLITE_OK {
			for st in stmts^ do finalize(st)
			clear(stmts)
			return nil, false
		}

		if stmt != nil {
			append(stmts, stmt)
		}

		if tail == nil || (cast([^]u8)tail)[0] == 0 {
			break
		}

		bytes_consumed := uintptr(rawptr(tail)) - uintptr(rawptr(c_sql))
		if int(bytes_consumed) >= len(remaining) {
			break
		}
		remaining = remaining[bytes_consumed:]
		remaining = strings.trim_left_space(remaining)
	}

	return stmts^, true
}

// finalize_all_statements finalizes all cached statements across all procedures.
// This is idempotent and safe to call multiple times.
finalize_all_statements :: proc(ctx: ^ConnectionContext) {
	log_debug("Finalizing all statements for ctx: %p", ctx)
	for name, p in ctx.procedure_cache {
		log_debug("Finalizing statements for proc: %s", name)
		for i := 0; i < len(p.stmts_pool); i += 1 {
			stmts := &p.stmts_pool[i]
			for stmt in stmts {
				finalize(stmt)
			}
			clear(stmts)
		}
	}
}

// free_procedure_cache finalizes all cached statements and frees all procedure metadata.
free_procedure_cache :: proc(ctx: ^ConnectionContext) {
	log_debug("Freeing procedure cache for ctx: %p", ctx)
	for name, p in ctx.procedure_cache {
		log_debug("Freeing procedure: %s", name)
		for i := 0; i < len(p.stmts_pool); i += 1 {
			stmts := &p.stmts_pool[i]
			for stmt in stmts {
				finalize(stmt)
			}
			delete(stmts^)
		}
		delete(p.stmts_pool)
		delete(p.transpiled_sql)
		delete(p.args_def)
		delete(p.name)
		free(p)
	}
}

// execute_stmts executes a list of prepared statements.
execute_stmts :: proc(
	ctx: ^ConnectionContext,
	db: ^sqlite3,
	stmts: [dynamic]^sqlite3_stmt,
	stop_check: bool,
) -> bool {
	for stmt in stmts {
		if stop_check && ctx.current_scope_top != nil && ctx.current_scope_top.stop_execution {
			return false
		}

		step_rc := step(stmt)
		if step_rc != SQLITE_DONE && step_rc != SQLITE_ROW {
			reset(stmt)
			return false
		}

		for step_rc == SQLITE_ROW {
			step_rc = step(stmt)
		}

		rc := reset(stmt)
		if rc != SQLITE_OK {
			return false
		}
	}
	return true
}

exec_callback :: proc "c" (
	arg: rawptr,
	argc: c.int,
	argv: [^]cstring,
	column_names: [^]cstring,
) -> c.int {
	context = plsqlite_context()
	ctx := (^ConnectionContext)(arg)
	if ctx != nil && ctx.current_scope_top != nil && ctx.current_scope_top.stop_execution {
		return 1 // Abort
	}
	return 0
}

// __env_set sets a variable in the specified scope. It handles variable updates in parent scopes
// if the variable is not found in the current scope (dynamic scoping for nested blocks, though current logic mimics lexical lookup).
// It converts the SQLite input value into a typed SqliteValue.
@(export)
__env_set :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil || conn.current_scope_top == nil do return

	target_scope_name_ptr := value_text(apArg[0])
	var_name_ptr := value_text(apArg[1])

	if var_name_ptr == nil do return

	target_scope_name := string(target_scope_name_ptr)
	var_name := string(var_name_ptr)

	// Extract typed value
	var_val: SqliteValue
	v_type := value_type(apArg[2])
	switch v_type {
	case SQLITE_INTEGER:
		var_val = value_int64(apArg[2])
	case SQLITE_FLOAT:
		var_val = value_double(apArg[2])
	case SQLITE_TEXT:
		text_ptr := value_text(apArg[2])
		if text_ptr != nil {
			var_val = strings.clone(string(text_ptr))
		} else {
			var_val = nil
		}
	case SQLITE_BLOB:
		blob_ptr := value_blob(apArg[2])
		blob_bytes := value_bytes(apArg[2])
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
		text_ptr := value_text(apArg[2])
		if text_ptr != nil {
			var_val = strings.clone(string(text_ptr))
		} else {
			var_val = nil
		}
	}

	// Scope resolution:
	// If the variable is qualified with a scope name (e.g., "proc.var"), find that scope in the stack.
	// Otherwise, use the current scope.
	target_scope := conn.current_scope_top
	if len(target_scope_name) > 0 {
		// Specific scope requested: Search from top down until variable found OR scope name matched.
		iter := conn.current_scope_top
		for iter != nil {
			if var_name in iter.variables {
				target_scope = iter
				break
			}
			if strings.equal_fold(iter.proc_name, target_scope_name) {
				target_scope = iter
				break
			}
			iter = iter.prev
		}
	} else {
		// No scope requested: Search up to procedure boundary.
		iter := conn.current_scope_top
		for iter != nil {
			if var_name in iter.variables {
				target_scope = iter
				break
			}
			if !iter.is_transient do break
			iter = iter.prev
		}
	}

	// Optimization: Use pointer access
	if ptr := &target_scope.variables[var_name]; ptr != nil {
		old_val := ptr^
		free_sqlite_value(old_val)
		ptr^ = var_val
	} else {
		target_scope.variables[strings.clone(var_name)] = var_val
	}
	log_debug("Env Set: scope=%s, var=%s", target_scope.proc_name, var_name)

	result_null(ctx)
}

// __env_get retrieves a typed variable from the specified scope.
// It searches up the scope chain if the variable is not found in the target scope.
@(export)
__env_get :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil do return

	target_scope_name_ptr := value_text(apArg[0])
	var_name_ptr := value_text(apArg[1])
	if target_scope_name_ptr == nil || var_name_ptr == nil {
		result_null(ctx)
		return
	}
	target_scope_name := string(target_scope_name_ptr)
	var_name := string(var_name_ptr)

	iter := conn.current_scope_top
	for iter != nil {
		// New Logic: Check if variable exists in this scope first.
		// This handles nested scopes (like loops) correctly if we are searching down to a procedure.
		if var_name in iter.variables {
			val := iter.variables[var_name]
			switch v in val {
			case i64:
				result_int64(ctx, v)
			case f64:
				result_double(ctx, v)
			case string:
				if len(v) > 0 {
					result_text(ctx, cstring(raw_data(v)), c.int(len(v)), SQLITE_TRANSIENT)
				} else {
					result_text(ctx, "", 0, SQLITE_TRANSIENT)
				}
			case []byte:
				result_blob(ctx, raw_data(v), c.int(len(v)), SQLITE_TRANSIENT)
			case:
				result_null(ctx)
			}
			return
		}

		// Boundary Check: If this scope's name matches our target, we STOP searching.
		// If target_scope_name is empty, we stop at the first non-transient scope.
		if len(target_scope_name) > 0 {
			if strings.equal_fold(iter.proc_name, target_scope_name) do break
		} else {
			if !iter.is_transient do break
		}

		iter = iter.prev
	}
	result_null(ctx)
}

// __env_return sets the return value for the current procedure scope and flags execution to stop.
// It converts the input value to a typed SqliteValue and stores it in `current_scope_top.return_value`.
@(export)
__env_return :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil || conn.current_scope_top == nil do return

	// Extract typed value
	var_val: SqliteValue
	v_type := value_type(apArg[0])
	log_debug("Env Return: received type=%d", v_type)
	switch v_type {
	case SQLITE_INTEGER:
		v := value_int64(apArg[0])
		var_val = v
		log_debug("Env Return: i64=%d", v)
	case SQLITE_FLOAT:
		v := value_double(apArg[0])
		var_val = v
		log_debug("Env Return: f64=%f", v)
	case SQLITE_TEXT:
		txt := value_text(apArg[0])
		if txt != nil {
			s := strings.clone(string(txt))
			var_val = s
			log_debug("Env Return: string=%s", s)
		}
	case SQLITE_BLOB:
		blob_ptr := value_blob(apArg[0])
		blob_bytes := value_bytes(apArg[0])
		if blob_ptr != nil && blob_bytes > 0 {
			data := make([]byte, blob_bytes)
			mem.copy(raw_data(data), blob_ptr, int(blob_bytes))
			var_val = data
			log_debug("Env Return: blob, len=%d", len(data))
		}
	case:
		// NULL
		log_debug("Env Return: received NULL")
	}

	conn.current_scope_top.return_value = var_val
	conn.current_scope_top.has_returned = true
	conn.current_scope_top.stop_execution = true
}

// __env_raise reports a custom error message to SQLite and flags execution to stop.
// This triggers a ROLLBACK TO savepoint in the main run_plsql loop.
@(export)
__env_raise :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil || conn.current_scope_top == nil do return

	msg := value_text(apArg[0])
	if msg != nil {
		result_error(ctx, msg, -1)
	} else {
		result_error(ctx, "Unknown PL/SQL error", -1)
	}

	conn.current_scope_top.stop_execution = true
	conn.current_scope_top.is_error = true
}

// os_getenv returns the value of an environment variable as a string, or NULL if not found.
@(export)
os_getenv :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	if nArg < 1 {
		result_null(ctx)
		return
	}
	name_ptr := value_text(apArg[0])
	if name_ptr == nil {
		result_null(ctx)
		return
	}
	name := string(name_ptr)
	val, ok := os.lookup_env(name)
	if !ok {
		result_null(ctx)
		return
	}
	defer delete(val)

	// Zero-Copy Optimization
	result_text(ctx, cstring(raw_data(val)), c.int(len(val)), SQLITE_TRANSIENT)
}

// cond_callback is a utility callback used by `__run_if` to capture the result of the condition query.
cond_callback :: proc "c" (
	arg: rawptr,
	argc: c.int,
	argv: [^]cstring,
	column_names: [^]cstring,
) -> c.int {
	context = plsqlite_context()
	result := (^bool)(arg)
	if argc > 0 && argv[0] != nil {
		val := string(argv[0])
		result^ = (val != "0" && val != "0.0" && val != "")
	}
	return 0
}

// __run_if implements the IF control flow structure.
// It executes the condition query. If true, it runs the `true_sql` block; otherwise, it runs `false_sql`.
// It uses statement caching for performance.
@(export)
__run_if :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil || conn.current_scope_top == nil || conn.current_scope_top.stop_execution do return

	db := context_db_handle(ctx)
	cond_query := string(value_text(apArg[0]))
	true_sql := string(value_text(apArg[1]))
	false_sql := string(value_text(apArg[2]))

	// 1. Evaluate Condition
	cond_stmts, ok := get_cached_stmts(conn, db, cond_query)
	if !ok || len(cond_stmts) == 0 {
		result_error(ctx, "Failed to prepare condition SQL", -1)
		return
	}

	// Assuming condition is a single SELECT returning one valid
	stmt := cond_stmts[0]
	cond_result := false

	if step(stmt) == SQLITE_ROW {
		// Equivalent to cond_callback
		text_ptr := column_text(stmt, 0)
		if text_ptr != nil {
			val := string(text_ptr)
			cond_result = (val != "0" && val != "0.0" && val != "")
		}
	}
	reset(stmt) // Always reset

	// 2. Execute Branch
	target_sql := cond_result ? true_sql : false_sql
	if len(target_sql) > 0 {
		stmts, ok := get_cached_stmts(conn, db, target_sql)
		if !ok {
			result_error(ctx, "Failed to prepare branch SQL", -1)
			return
		}
		if !execute_stmts(conn, db, stmts, true) {
			if conn.current_scope_top != nil && conn.current_scope_top.stop_execution do return
			result_error(ctx, errmsg(db), -1)
		}
	}
}

// __proc_loop implements the FOR loop control flow with caching.
// Optimization: Persistent Loop Scope (reduces allocations)
@(export)
__proc_loop :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil || conn.current_scope_top == nil || conn.current_scope_top.stop_execution do return

	db := context_db_handle(ctx)
	query := string(value_text(apArg[0]))
	body_sql := string(value_text(apArg[1]))
	var_name := string(value_text(apArg[2]))
	proc_name := string(value_text(apArg[3]))

	// Prepare Loop Query (Cached)
	query_stmts, ok_q := get_cached_stmts(conn, db, query)
	if !ok_q || len(query_stmts) == 0 {
		result_error(ctx, "Failed to prepare loop query", -1)
		return
	}
	stmt := query_stmts[0]

	// Prepare Body Statements (Cached)
	// We optimize by fetching them once before the loop
	body_stmts: [dynamic]^sqlite3_stmt
	if len(body_sql) > 0 {
		bs, ok_b := get_cached_stmts(conn, db, body_sql)
		if !ok_b {
			result_error(ctx, "Failed to prepare loop body", -1)
			return
		}
		body_stmts = bs
	}

	// Optimization: Persistent Loop Scope (reduces allocations)
	// We use the iterator name as the scope name to isolate it,
	// while allowing transparent lookup of other variables in the parent.
	scope_push(conn, var_name, true)

	// Loop over the result set
	for step(stmt) == SQLITE_ROW && !conn.current_scope_top.stop_execution {

		col_count := column_count(stmt)
		for i in 0 ..< col_count {
			name := string(column_name(stmt, i))
			var_val := extract_column_value(stmt, i)

			if ptr := &conn.current_scope_top.variables[name]; ptr != nil {
				free_sqlite_value(ptr^)
				ptr^ = var_val
			} else {
				conn.current_scope_top.variables[strings.clone(name)] = var_val
			}
		}

		if len(body_stmts) > 0 {
			if !execute_stmts(conn, db, body_stmts, true) {
				if conn.current_scope_top != nil && conn.current_scope_top.stop_execution do break
				result_error(ctx, errmsg(db), -1)
				break
			}
		}
	}

	scope_pop(conn, true)
	reset(stmt)
}

// Helper to extract typed value from column
extract_column_value :: proc(stmt: ^sqlite3_stmt, i: c.int) -> SqliteValue {
	c_type := column_type(stmt, i)
	switch c_type {
	case SQLITE_INTEGER:
		return column_int64(stmt, i)
	case SQLITE_FLOAT:
		return column_double(stmt, i)
	case SQLITE_TEXT:
		ptr := column_text(stmt, i)
		return strings.clone(string(ptr)) if ptr != nil else nil
	case SQLITE_NULL:
		return nil
	case:
		ptr := column_text(stmt, i)
		return strings.clone(string(ptr)) if ptr != nil else nil
	}
}

// __range_loop implements a numeric loop from start to end with a given step.
@(export)
__range_loop :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)
	conn := (^ConnectionContext)(user_data(ctx))
	if conn == nil || conn.current_scope_top == nil || conn.current_scope_top.stop_execution do return

	db := context_db_handle(ctx)
	var_name := string(value_text(apArg[0]))
	body_sql := string(value_text(apArg[4]))

	body_stmts, ok_b := get_cached_stmts(conn, db, body_sql)
	if !ok_b {
		result_error(ctx, "Failed to prepare loop body", -1)
		return
	}

	is_real :=
		value_type(apArg[1]) == SQLITE_FLOAT ||
		value_type(apArg[2]) == SQLITE_FLOAT ||
		value_type(apArg[3]) == SQLITE_FLOAT

	scope_push(conn, var_name, true)
	// Pre-insert with start value to ensure key exists and avoid repeated clones
	cloned_var_name := strings.clone(var_name)
	conn.current_scope_top.variables[cloned_var_name] = nil

	if is_real {
		start := value_double(apArg[1])
		end := value_double(apArg[2])
		step_val := value_double(apArg[3])

		if step_val == 0 {
			result_error(ctx, "RANGE loop step cannot be zero", -1)
			return
		}

		i := start
		if step_val > 0 {
			if end <= start {
				result_error(ctx, "Increasing RANGE loop end must be > start", -1)
				return
			}
			for i <= end {
				if conn.current_scope_top.stop_execution do break
				conn.current_scope_top.variables[var_name] = i
				if len(body_stmts) > 0 {
					if !execute_stmts(conn, db, body_stmts, true) do break
				}
				i += step_val
			}
		} else {
			if start <= end {
				result_error(ctx, "Decreasing RANGE loop start must be > end", -1)
				return
			}
			for i >= end {
				if conn.current_scope_top.stop_execution do break
				conn.current_scope_top.variables[var_name] = i
				if len(body_stmts) > 0 {
					if !execute_stmts(conn, db, body_stmts, true) do break
				}
				i += step_val
			}
		}
	} else {
		start := value_int64(apArg[1])
		end := value_int64(apArg[2])
		step_val := value_int64(apArg[3])

		if step_val == 0 {
			result_error(ctx, "RANGE loop step cannot be zero", -1)
			return
		}

		i := start
		if step_val > 0 {
			if end <= start {
				result_error(ctx, "Increasing RANGE loop end must be > start", -1)
				return
			}
			for i <= end {
				if conn.current_scope_top.stop_execution do break
				conn.current_scope_top.variables[var_name] = i
				if len(body_stmts) > 0 {
					if !execute_stmts(conn, db, body_stmts, true) do break
				}
				i += step_val
			}
		} else {
			if start <= end {
				result_error(ctx, "Decreasing RANGE loop start must be > end", -1)
				return
			}
			for i >= end {
				if conn.current_scope_top.stop_execution do break
				conn.current_scope_top.variables[var_name] = i
				if len(body_stmts) > 0 {
					if !execute_stmts(conn, db, body_stmts, true) do break
				}
				i += step_val
			}
		}
	}
	scope_pop(conn, true)
}
