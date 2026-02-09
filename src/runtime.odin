package plsqlite

import "base:runtime"
import "core:c"
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
} // SqliteValue is implicitly nullable if used as a union?
// No, Odin unions are nil-able only if `Maybe` or `union #shared_nil`.
// Wait. `union { i64, f64, string }` can be `nil`?
// Yes, a union value can be nil (tag 0).

current_scope_top: ^Scope

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

// scope_push creates a new scope for a procedure call and pushes it onto the scope stack.
// It increments the recursion depth and returns false if the maximum depth is exceeded.
scope_push :: proc(name: string) -> bool {
	if current_scope_top != nil && current_scope_top.depth >= MAX_RECURSION_DEPTH {
		return false
	}
	new_s := new(Scope)
	new_s.proc_name = strings.clone(name)
	new_s.variables = make(map[string]SqliteValue)
	new_s.prev = current_scope_top
	if current_scope_top != nil {
		new_s.depth = current_scope_top.depth + 1
	} else {
		new_s.depth = 1
	}
	current_scope_top = new_s
	return true
}

// scope_pop removes the current scope from the stack, cleaning up all allocated memory for variables.
// If `propagate` is true, it propagates the `stop_execution` flag and return value to the parent scope
// (used for RETURN statements).
scope_pop :: proc(propagate: bool) {
	if current_scope_top != nil {
		tmp := current_scope_top
		current_scope_top = tmp.prev

		if propagate && tmp.stop_execution && current_scope_top != nil {
			current_scope_top.stop_execution = true
			if tmp.has_returned {
				free_sqlite_value(current_scope_top.return_value)
				current_scope_top.return_value = clone_sqlite_value(tmp.return_value)
				current_scope_top.has_returned = true
			}
		}

		delete(tmp.proc_name)
		for k, v in tmp.variables {
			delete(k)
			free_sqlite_value(v)
		}
		delete(tmp.variables)
		free_sqlite_value(tmp.return_value)
		free(tmp)
	}
}

exec_callback :: proc "c" (
	unused: rawptr,
	argc: c.int,
	argv: [^]cstring,
	column_names: [^]cstring,
) -> c.int {
	context = runtime.default_context()
	if current_scope_top != nil && current_scope_top.stop_execution {
		return 1 // Abort
	}
	return 0
}

// __env_set sets a variable in the specified scope. It handles variable updates in parent scopes
// if the variable is not found in the current scope (dynamic scoping for nested blocks, though current logic mimics lexical lookup).
// It converts the SQLite input value into a typed SqliteValue.
@(export)
__env_set :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = runtime.default_context()
	if current_scope_top == nil do return

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
			// Clone blob data
			data := make([]byte, blob_bytes)
			mem.copy(raw_data(data), blob_ptr, int(blob_bytes))
			var_val = data
		} else {
			var_val = nil
		}
	case SQLITE_NULL:
		var_val = nil
	case:
		// Default to text if unknown
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
	target_scope := current_scope_top
	if len(target_scope_name) > 0 && target_scope.proc_name != target_scope_name {
		iter := target_scope.prev
		for iter != nil {
			if iter.proc_name == target_scope_name {
				target_scope = iter
				break
			}
			iter = iter.prev
		}
	}

	if var_name in target_scope.variables {
		old_val := target_scope.variables[var_name]
		free_sqlite_value(old_val)
		target_scope.variables[var_name] = var_val
	} else {
		target_scope.variables[strings.clone(var_name)] = var_val
	}

	result_null(ctx)
}

// __env_get retrieves a typed variable from the specified scope.
// It searches up the scope chain if the variable is not found in the target scope.
@(export)
__env_get :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = runtime.default_context()
	target_scope_name_ptr := value_text(apArg[0])
	var_name_ptr := value_text(apArg[1])
	if target_scope_name_ptr == nil || var_name_ptr == nil {
		result_null(ctx)
		return
	}
	target_scope_name := string(target_scope_name_ptr)
	var_name := string(var_name_ptr)

	iter := current_scope_top
	for iter != nil {
		if strings.equal_fold(iter.proc_name, target_scope_name) {
			if var_name in iter.variables {
				val := iter.variables[var_name]

				switch v in val {
				case i64:
					result_int64(ctx, v)
				case f64:
					result_double(ctx, v)
				case string:
					c_val := strings.clone_to_cstring(v)
					defer delete(c_val)
					result_text(ctx, c_val, -1, SQLITE_TRANSIENT)
				case []byte:
					result_blob(ctx, raw_data(v), c.int(len(v)), SQLITE_TRANSIENT)
				case:
					result_null(ctx)
				}
				return
			}
		}
		iter = iter.prev
	}
	result_null(ctx)
}

// __env_return sets the return value for the current procedure scope and flags execution to stop.
// It converts the input value to a typed SqliteValue and stores it in `current_scope_top.return_value`.
@(export)
__env_return :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = runtime.default_context()
	if current_scope_top == nil do return

	// Extract typed value
	var_val: SqliteValue
	v_type := value_type(apArg[0])
	switch v_type {
	case SQLITE_INTEGER:
		var_val = value_int64(apArg[0])
	case SQLITE_FLOAT:
		var_val = value_double(apArg[0])
	case SQLITE_TEXT:
		txt := value_text(apArg[0])
		if txt != nil {
			var_val = strings.clone(string(txt))
		}
	case SQLITE_BLOB:
		blob_ptr := value_blob(apArg[0])
		blob_bytes := value_bytes(apArg[0])
		if blob_ptr != nil && blob_bytes > 0 {
			data := make([]byte, blob_bytes)
			mem.copy(raw_data(data), blob_ptr, int(blob_bytes))
			var_val = data
		}
	case: // NULL
	}

	current_scope_top.return_value = var_val
	current_scope_top.has_returned = true
	current_scope_top.stop_execution = true
}

// __env_raise reports a custom error message to SQLite and flags execution to stop.
// This triggers a ROLLBACK TO savepoint in the main run_plsql loop.
@(export)
__env_raise :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = runtime.default_context()
	if current_scope_top == nil do return

	msg := value_text(apArg[0])
	if msg != nil {
		result_error(ctx, msg, -1)
	} else {
		result_error(ctx, "Unknown PL/SQL error", -1)
	}

	current_scope_top.stop_execution = true
	current_scope_top.is_error = true
}

// os_getenv returns the value of an environment variable as a string, or NULL if not found.
@(export)
os_getenv :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = runtime.default_context()
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

	c_val := strings.clone_to_cstring(val)
	defer delete(c_val)
	result_text(ctx, c_val, -1, SQLITE_TRANSIENT)
}

// cond_callback is a utility callback used by `__run_if` to capture the result of the condition query.
cond_callback :: proc "c" (
	arg: rawptr,
	argc: c.int,
	argv: [^]cstring,
	column_names: [^]cstring,
) -> c.int {
	context = runtime.default_context()
	result := (^bool)(arg)
	if argc > 0 && argv[0] != nil {
		val := string(argv[0])
		result^ = (val != "0" && val != "0.0" && val != "")
	}
	return 0
}

// __run_if implements the IF control flow structure.
// It executes the condition query. If true, it runs the `true_sql` block; otherwise, it runs `false_sql`.
// It stops execution if `stop_execution` is flagged (e.g., by a RETURN in the block).
@(export)
__run_if :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = runtime.default_context()
	if current_scope_top == nil || current_scope_top.stop_execution do return

	db := context_db_handle(ctx)
	cond_query := string(value_text(apArg[0]))
	true_sql := string(value_text(apArg[1]))
	false_sql := string(value_text(apArg[2]))

	// Evaluate the condition (SQL query)
	cond_result := false
	c_cond := strings.clone_to_cstring(cond_query)
	defer delete(c_cond)
	if exec(db, c_cond, cond_callback, &cond_result, nil) != SQLITE_OK {
		result_error(ctx, errmsg(db), -1)
		return
	}

	if cond_result {
		if len(true_sql) > 0 {
			c_true := strings.clone_to_cstring(true_sql)
			defer delete(c_true)
			if exec(db, c_true, exec_callback, nil, nil) != SQLITE_OK {
				if current_scope_top != nil && current_scope_top.stop_execution do return
				result_error(ctx, errmsg(db), -1)
				return
			}
		}
	} else {
		if len(false_sql) > 0 {
			c_false := strings.clone_to_cstring(false_sql)
			defer delete(c_false)
			if exec(db, c_false, exec_callback, nil, nil) != SQLITE_OK {
				if current_scope_top != nil && current_scope_top.stop_execution do return
				result_error(ctx, errmsg(db), -1)
				return
			}
		}
	}
}

// __proc_loop implements the FOR loop control flow.
// It executes the `query` to get a cursor. For each row, it pushes a new scope, binds loop variables,
// and executes `body_sql`. It handles early exit via `stop_execution`.
@(export)
__proc_loop :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = runtime.default_context()
	if current_scope_top == nil || current_scope_top.stop_execution do return

	db := context_db_handle(ctx)
	query := string(value_text(apArg[0]))
	body_sql := string(value_text(apArg[1]))
	var_name := string(value_text(apArg[2]))

	stmt: ^sqlite3_stmt
	c_query := strings.clone_to_cstring(query)
	defer delete(c_query)
	if prepare_v2(db, c_query, -1, &stmt, nil) != SQLITE_OK {
		result_error(ctx, errmsg(db), -1)
		return
	}

	// Loop over the result set
	for step(stmt) == SQLITE_ROW && !current_scope_top.stop_execution {
		// New scope for each iteration, named after the loop variable for easy access
		scope_push(var_name)

		col_count := column_count(stmt)
		for i in 0 ..< col_count {
			name := string(column_name(stmt, i))

			// Extract typed value from column
			var_val: SqliteValue
			c_type := column_type(stmt, i)
			switch c_type {
			case SQLITE_INTEGER:
				var_val = column_int64(stmt, i)
			case SQLITE_FLOAT:
				var_val = column_double(stmt, i)
			case SQLITE_TEXT:
				text_ptr := column_text(stmt, i)
				if text_ptr != nil {
					var_val = strings.clone(string(text_ptr))
				} else {
					var_val = nil
				}
			case SQLITE_NULL:
				var_val = nil
			case:
				text_ptr := column_text(stmt, i)
				if text_ptr != nil {
					var_val = strings.clone(string(text_ptr))
				} else {
					var_val = nil
				}
			}

			current_scope_top.variables[strings.clone(name)] = var_val
		}

		c_body := strings.clone_to_cstring(body_sql)
		if exec(db, c_body, exec_callback, nil, nil) != SQLITE_OK {
			if current_scope_top != nil && current_scope_top.stop_execution {
				delete(c_body)
				scope_pop(true)
				finalize(stmt)
				return
			}
			result_error(ctx, errmsg(db), -1)
			delete(c_body)
			scope_pop(true)
			finalize(stmt)
			return
		}
		delete(c_body)

		scope_pop(true)
	}
	finalize(stmt)
}
