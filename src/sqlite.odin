package plsqlite

import "core:c"

// SQLite Types
sqlite3 :: struct {}
sqlite3_context :: struct {}
sqlite3_value :: struct {}
sqlite3_stmt :: struct {}
sqlite3_backup :: struct {}
sqlite3_blob :: struct {}
sqlite3_mutex :: struct {}
sqlite3_vfs :: struct {}
sqlite3_index_info :: struct {}
sqlite3_str :: struct {}
sqlite3_module :: struct {}

sqlite3_callback :: #type proc "c" (
	unused: rawptr,
	argc: c.int,
	argv: [^]cstring,
	column_names: [^]cstring,
) -> c.int

sqlite3_api_routines :: struct {
	aggregate_context:      rawptr,
	aggregate_count:        rawptr,
	bind_blob:              rawptr,
	bind_double:            rawptr,
	bind_int:               rawptr,
	bind_int64:             rawptr,
	bind_null:              rawptr,
	bind_parameter_count:   rawptr,
	bind_parameter_index:   rawptr,
	bind_parameter_name:    rawptr,
	bind_text:              rawptr,
	bind_text16:            rawptr,
	bind_value:             rawptr,
	busy_handler:           rawptr,
	busy_timeout:           rawptr,
	changes:                rawptr,
	close:                  rawptr,
	collation_needed:       rawptr,
	collation_needed16:     rawptr,
	column_blob:            rawptr,
	column_bytes:           rawptr,
	column_bytes16:         rawptr,
	column_count:           rawptr,
	column_database_name:   rawptr,
	column_database_name16: rawptr,
	column_decltype:        rawptr,
	column_decltype16:      rawptr,
	column_double:          rawptr,
	column_int:             rawptr,
	column_int64:           rawptr,
	column_name:            rawptr,
	column_name16:          rawptr,
	column_origin_name:     rawptr,
	column_origin_name16:   rawptr,
	column_table_name:      rawptr,
	column_table_name16:    rawptr,
	column_text:            rawptr,
	column_text16:          rawptr,
	column_type:            rawptr,
	column_value:           rawptr,
	commit_hook:            rawptr,
	complete:               rawptr,
	complete16:             rawptr,
	create_collation:       rawptr,
	create_collation16:     rawptr,
	create_function:        rawptr,
	create_function16:      rawptr,
	create_module:          rawptr,
	data_count:             rawptr,
	db_handle:              rawptr,
	declare_vtab:           rawptr,
	enable_shared_cache:    rawptr,
	errcode:                rawptr,
	errmsg:                 rawptr,
	errmsg16:               rawptr,
	exec:                   rawptr,
	expired:                rawptr,
	finalize:               rawptr,
	free:                   rawptr,
	free_table:             rawptr,
	get_autocommit:         rawptr,
	get_auxdata:            rawptr,
	get_table:              rawptr,
	global_recover:         rawptr,
	interruptx:             rawptr,
	last_insert_rowid:      rawptr,
	libversion:             rawptr,
	libversion_number:      rawptr,
	malloc:                 rawptr,
	mprintf:                rawptr,
	open:                   rawptr,
	open16:                 rawptr,
	prepare:                rawptr,
	prepare16:              rawptr,
	profile:                rawptr,
	progress_handler:       rawptr,
	realloc:                rawptr,
	reset:                  rawptr,
	result_blob:            rawptr,
	result_double:          rawptr,
	result_error:           rawptr,
	result_error16:         rawptr,
	result_int:             rawptr,
	result_int64:           rawptr,
	result_null:            rawptr,
	result_text:            rawptr,
	result_text16:          rawptr,
	result_text16be:        rawptr,
	result_text16le:        rawptr,
	result_value:           rawptr,
	rollback_hook:          rawptr,
	set_authorizer:         rawptr,
	set_auxdata:            rawptr,
	xsnprintf:              rawptr,
	step:                   rawptr,
	table_column_metadata:  rawptr,
	thread_cleanup:         rawptr,
	total_changes:          rawptr,
	trace:                  rawptr,
	transfer_bindings:      rawptr,
	update_hook:            rawptr,
	user_data:              rawptr,
	value_blob:             rawptr,
	value_bytes:            rawptr,
	value_bytes16:          rawptr,
	value_double:           rawptr,
	value_int:              rawptr,
	value_int64:            rawptr,
	value_numeric_type:     rawptr,
	value_text:             rawptr,
	value_text16:           rawptr,
	value_text16be:         rawptr,
	value_text16le:         rawptr,
	value_type:             rawptr,
	vmprintf:               rawptr,
	overload_function:      rawptr,
	prepare_v2:             rawptr,
	prepare16_v2:           rawptr,
	clear_bindings:         rawptr,
	create_module_v2:       rawptr,
	bind_zeroblob:          rawptr,
	blob_bytes:             rawptr,
	blob_close:             rawptr,
	blob_open:              rawptr,
	blob_read:              rawptr,
	blob_write:             rawptr,
	create_collation_v2:    rawptr,
	file_control:           rawptr,
	memory_highwater:       rawptr,
	memory_used:            rawptr,
	mutex_alloc:            rawptr,
	mutex_enter:            rawptr,
	mutex_free:             rawptr,
	mutex_leave:            rawptr,
	mutex_try:              rawptr,
	open_v2:                rawptr,
	release_memory:         rawptr,
	result_error_nomem:     rawptr,
	result_error_toobig:    rawptr,
	sleep:                  rawptr,
	soft_heap_limit:        rawptr,
	vfs_find:               rawptr,
	vfs_register:           rawptr,
	vfs_unregister:         rawptr,
	xthreadsafe:            rawptr,
	result_zeroblob:        rawptr,
	result_error_code:      rawptr,
	test_control:           rawptr,
	randomness:             rawptr,
	context_db_handle:      rawptr,
	extended_result_codes:  rawptr,
	limit:                  rawptr,
	next_stmt:              rawptr,
	sql:                    rawptr,
	status:                 rawptr,
	backup_finish:          rawptr,
	backup_init:            rawptr,
	backup_pagecount:       rawptr,
	backup_remaining:       rawptr,
	backup_step:            rawptr,
	compileoption_get:      rawptr,
	compileoption_used:     rawptr,
	create_function_v2:     rawptr,
	db_config:              rawptr,
	db_mutex:               rawptr,
	db_status:              rawptr,
	extended_errcode:       rawptr,
	log:                    rawptr,
	soft_heap_limit64:      rawptr,
	sourceid:               rawptr,
	stmt_status:            rawptr,
	strnicmp:               rawptr,
	unlock_notify:          rawptr,
	wal_autocheckpoint:     rawptr,
	wal_checkpoint:         rawptr,
	wal_hook:               rawptr,
	blob_reopen:            rawptr,
	vtab_config:            rawptr,
	vtab_on_conflict:       rawptr,
	close_v2:               rawptr,
	db_filename:            rawptr,
	db_readonly:            rawptr,
	db_release_memory:      rawptr,
	errstr:                 rawptr,
	stmt_busy:              rawptr,
	stmt_readonly:          rawptr,
	stricmp:                rawptr,
	uri_boolean:            rawptr,
	uri_int64:              rawptr,
	uri_parameter:          rawptr,
	xvsnprintf:             rawptr,
	wal_checkpoint_v2:      rawptr,
	auto_extension:         rawptr,
	bind_blob64:            rawptr,
	bind_text64:            rawptr,
	cancel_auto_extension:  rawptr,
	load_extension:         rawptr,
	malloc64:               rawptr,
	msize:                  rawptr,
	realloc64:              rawptr,
	reset_auto_extension:   rawptr,
	result_blob64:          rawptr,
	result_text64:          rawptr,
	strglob:                rawptr,
	value_dup:              rawptr,
	value_free:             rawptr,
	result_zeroblob64:      rawptr,
	bind_zeroblob64:        rawptr,
	value_subtype:          rawptr,
	result_subtype:         rawptr,
	status64:               rawptr,
	strlike:                rawptr,
	db_cacheflush:          rawptr,
	system_errno:           rawptr,
	trace_v2:               rawptr,
	expanded_sql:           rawptr,
	set_last_insert_rowid:  rawptr,
	prepare_v3:             rawptr,
	prepare16_v3:           rawptr,
	bind_pointer:           rawptr,
	result_pointer:         rawptr,
	value_pointer:          rawptr,
	vtab_nochange:          rawptr,
	value_nochange:         rawptr,
	vtab_collation:         rawptr,
	keyword_count:          rawptr,
	keyword_name:           rawptr,
	keyword_check:          rawptr,
	str_new:                rawptr,
	str_finish:             rawptr,
	str_appendf:            rawptr,
	str_vappendf:           rawptr,
	str_append:             rawptr,
	str_appendall:          rawptr,
	str_appendchar:         rawptr,
	str_reset:              rawptr,
	str_errcode:            rawptr,
	str_length:             rawptr,
	str_value:              rawptr,
	create_window_function: rawptr,
	normalized_sql:         rawptr,
	stmt_isexplain:         rawptr,
	value_frombind:         rawptr,
	drop_modules:           rawptr,
	hard_heap_limit64:      rawptr,
	uri_key:                rawptr,
	filename_database:      rawptr,
	filename_journal:       rawptr,
	filename_wal:           rawptr,
	create_filename:        rawptr,
	free_filename:          rawptr,
	database_file_object:   rawptr,
	txn_state:              rawptr,
	changes64:              rawptr,
	total_changes64:        rawptr,
	autovacuum_pages:       rawptr,
	error_offset:           rawptr,
	vtab_rhs_value:         rawptr,
	vtab_distinct:          rawptr,
	vtab_in:                rawptr,
	vtab_in_first:          rawptr,
	vtab_in_next:           rawptr,
	deserialize:            rawptr,
	serialize:              rawptr,
	db_name:                rawptr,
	value_encoding:         rawptr,
	is_interrupted:         rawptr,
}

api: ^sqlite3_api_routines

// Helper wrappers for convenience
value_text :: proc "c" (val: ^sqlite3_value) -> cstring {
	if api == nil || api.value_text == nil do return nil
	fn := cast(proc "c" (_: ^sqlite3_value) -> cstring)api.value_text
	return fn(val)
}

result_text :: proc "c" (ctx: ^sqlite3_context, data: cstring, n: c.int, xDel: rawptr) {
	if api == nil || api.result_text == nil do return
	fn := cast(proc "c" (_: ^sqlite3_context, _: cstring, _: c.int, _: rawptr))api.result_text
	fn(ctx, data, n, xDel)
}

result_error :: proc "c" (ctx: ^sqlite3_context, msg: cstring, n: c.int) {
	if api == nil || api.result_error == nil do return
	fn := cast(proc "c" (_: ^sqlite3_context, _: cstring, _: c.int))api.result_error
	fn(ctx, msg, n)
}

result_null :: proc "c" (ctx: ^sqlite3_context) {
	if api == nil || api.result_null == nil do return
	fn := cast(proc "c" (_: ^sqlite3_context))api.result_null
	fn(ctx)
}

create_function :: proc "c" (
	db: ^sqlite3,
	name: cstring,
	nArg: c.int,
	eTextRep: c.int,
	p: rawptr,
	xFunc: proc "c" (ctx: ^sqlite3_context, n: c.int, v: [^]^sqlite3_value),
	xStep: proc "c" (ctx: ^sqlite3_context, n: c.int, v: [^]^sqlite3_value),
	xFinal: proc "c" (ctx: ^sqlite3_context),
) -> c.int {
	if api == nil || api.create_function == nil do return 1
	fn := cast(proc "c" (
		_: ^sqlite3,
		_: cstring,
		_: c.int,
		_: c.int,
		_: rawptr,
		_: rawptr,
		_: rawptr,
		_: rawptr,
	) -> c.int)api.create_function
	return fn(
		db,
		name,
		nArg,
		eTextRep,
		p,
		cast(rawptr)xFunc,
		cast(rawptr)xStep,
		cast(rawptr)xFinal,
	)
}

create_function_v2 :: proc "c" (
	db: ^sqlite3,
	name: cstring,
	nArg: c.int,
	eTextRep: c.int,
	p: rawptr,
	xFunc: proc "c" (ctx: ^sqlite3_context, n: c.int, v: [^]^sqlite3_value),
	xStep: proc "c" (ctx: ^sqlite3_context, n: c.int, v: [^]^sqlite3_value),
	xFinal: proc "c" (ctx: ^sqlite3_context),
	xDestroy: proc "c" (p: rawptr),
) -> c.int {
	if api == nil || api.create_function_v2 == nil do return 1
	fn := cast(proc "c" (
		_: ^sqlite3,
		_: cstring,
		_: c.int,
		_: c.int,
		_: rawptr,
		_: rawptr,
		_: rawptr,
		_: rawptr,
		_: rawptr,
	) -> c.int)api.create_function_v2
	return fn(
		db,
		name,
		nArg,
		eTextRep,
		p,
		cast(rawptr)xFunc,
		cast(rawptr)xStep,
		cast(rawptr)xFinal,
		cast(rawptr)xDestroy,
	)
}

exec :: proc "c" (
	db: ^sqlite3,
	sql: cstring,
	callback: sqlite3_callback,
	p: rawptr,
	pzErrMsg: [^]cstring,
) -> c.int {
	if api == nil || api.exec == nil do return 1
	fn := cast(proc "c" (
		_: ^sqlite3,
		_: cstring,
		_: rawptr,
		_: rawptr,
		_: [^]cstring,
	) -> c.int)api.exec
	return fn(db, sql, cast(rawptr)callback, p, pzErrMsg)
}

prepare_v2 :: proc "c" (
	db: ^sqlite3,
	sql: cstring,
	n: c.int,
	ppStmt: ^^sqlite3_stmt,
	pzTail: ^cstring,
) -> c.int {
	if api == nil || api.prepare_v2 == nil do return 1
	fn := cast(proc "c" (
		_: ^sqlite3,
		_: cstring,
		_: c.int,
		_: ^^sqlite3_stmt,
		_: ^cstring,
	) -> c.int)api.prepare_v2
	return fn(db, sql, n, ppStmt, pzTail)
}

step :: proc "c" (stmt: ^sqlite3_stmt) -> c.int {
	if api == nil || api.step == nil do return 1
	fn := cast(proc "c" (_: ^sqlite3_stmt) -> c.int)api.step
	return fn(stmt)
}

finalize :: proc "c" (stmt: ^sqlite3_stmt) -> c.int {
	if api == nil || api.finalize == nil do return 1
	fn := cast(proc "c" (_: ^sqlite3_stmt) -> c.int)api.finalize
	return fn(stmt)
}

bind_text :: proc "c" (
	stmt: ^sqlite3_stmt,
	i: c.int,
	data: cstring,
	n: c.int,
	xDel: rawptr,
) -> c.int {
	if api == nil || api.bind_text == nil do return 1
	fn := cast(proc "c" (
		_: ^sqlite3_stmt,
		_: c.int,
		_: cstring,
		_: c.int,
		_: rawptr,
	) -> c.int)api.bind_text
	return fn(stmt, i, data, n, xDel)
}

column_text :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> cstring {
	if api == nil || api.column_text == nil do return nil
	fn := cast(proc "c" (_: ^sqlite3_stmt, _: c.int) -> cstring)api.column_text
	return fn(stmt, iCol)
}

column_name :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> cstring {
	if api == nil || api.column_name == nil do return nil
	fn := cast(proc "c" (_: ^sqlite3_stmt, _: c.int) -> cstring)api.column_name
	return fn(stmt, iCol)
}

column_count :: proc "c" (stmt: ^sqlite3_stmt) -> c.int {
	if api == nil || api.column_count == nil do return 0
	fn := cast(proc "c" (_: ^sqlite3_stmt) -> c.int)api.column_count
	return fn(stmt)
}

column_int :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> c.int {
	if api == nil || api.column_int == nil do return 0
	fn := cast(proc "c" (_: ^sqlite3_stmt, _: c.int) -> c.int)api.column_int
	return fn(stmt, iCol)
}

errmsg :: proc "c" (db: ^sqlite3) -> cstring {
	if api == nil || api.errmsg == nil do return nil
	fn := cast(proc "c" (_: ^sqlite3) -> cstring)api.errmsg
	return fn(db)
}

context_db_handle :: proc "c" (ctx: ^sqlite3_context) -> ^sqlite3 {
	if api == nil || api.context_db_handle == nil do return nil
	fn := cast(proc "c" (_: ^sqlite3_context) -> ^sqlite3)api.context_db_handle
	return fn(ctx)
}

user_data :: proc "c" (ctx: ^sqlite3_context) -> rawptr {
	if api == nil || api.user_data == nil do return nil
	fn := cast(proc "c" (_: ^sqlite3_context) -> rawptr)api.user_data
	return fn(ctx)
}

value_type :: proc "c" (val: ^sqlite3_value) -> c.int {
	if api == nil || api.value_type == nil do return SQLITE_NULL
	fn := cast(proc "c" (_: ^sqlite3_value) -> c.int)api.value_type
	return fn(val)
}

value_int64 :: proc "c" (val: ^sqlite3_value) -> i64 {
	if api == nil || api.value_int64 == nil do return 0
	fn := cast(proc "c" (_: ^sqlite3_value) -> i64)api.value_int64
	return fn(val)
}

value_double :: proc "c" (val: ^sqlite3_value) -> f64 {
	if api == nil || api.value_double == nil do return 0
	fn := cast(proc "c" (_: ^sqlite3_value) -> f64)api.value_double
	return fn(val)
}

value_blob :: proc "c" (val: ^sqlite3_value) -> rawptr {
	if api == nil || api.value_blob == nil do return nil
	fn := cast(proc "c" (_: ^sqlite3_value) -> rawptr)api.value_blob
	return fn(val)
}

value_bytes :: proc "c" (val: ^sqlite3_value) -> c.int {
	if api == nil || api.value_bytes == nil do return 0
	fn := cast(proc "c" (_: ^sqlite3_value) -> c.int)api.value_bytes
	return fn(val)
}

result_int64 :: proc "c" (ctx: ^sqlite3_context, val: i64) {
	if api == nil || api.result_int64 == nil do return
	fn := cast(proc "c" (_: ^sqlite3_context, _: i64))api.result_int64
	fn(ctx, val)
}

result_double :: proc "c" (ctx: ^sqlite3_context, val: f64) {
	if api == nil || api.result_double == nil do return
	fn := cast(proc "c" (_: ^sqlite3_context, _: f64))api.result_double
	fn(ctx, val)
}

result_blob :: proc "c" (ctx: ^sqlite3_context, val: rawptr, n: c.int, xDel: rawptr) {
	if api == nil || api.result_blob == nil do return
	fn := cast(proc "c" (_: ^sqlite3_context, _: rawptr, _: c.int, _: rawptr))api.result_blob
	fn(ctx, val, n, xDel)
}

column_type :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> c.int {
	if api == nil || api.column_type == nil do return SQLITE_NULL
	fn := cast(proc "c" (_: ^sqlite3_stmt, _: c.int) -> c.int)api.column_type
	return fn(stmt, iCol)
}

column_int64 :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> i64 {
	if api == nil || api.column_int64 == nil do return 0
	fn := cast(proc "c" (_: ^sqlite3_stmt, _: c.int) -> i64)api.column_int64
	return fn(stmt, iCol)
}

column_double :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> f64 {
	if api == nil || api.column_double == nil do return 0
	fn := cast(proc "c" (_: ^sqlite3_stmt, _: c.int) -> f64)api.column_double
	return fn(stmt, iCol)
}

column_blob :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> rawptr {
	if api == nil || api.column_blob == nil do return nil
	fn := cast(proc "c" (_: ^sqlite3_stmt, _: c.int) -> rawptr)api.column_blob
	return fn(stmt, iCol)
}

column_bytes :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> c.int {
	if api == nil || api.column_bytes == nil do return 0
	fn := cast(proc "c" (_: ^sqlite3_stmt, _: c.int) -> c.int)api.column_bytes
	return fn(stmt, iCol)
}

SQLITE_OK :: 0
SQLITE_ROW :: 100
SQLITE_DONE :: 101
SQLITE_STATIC :: rawptr(uintptr(0))
SQLITE_TRANSIENT :: rawptr(uintptr(18446744073709551615))
SQLITE_UTF8 :: 1

SQLITE_INTEGER :: 1
SQLITE_FLOAT :: 2
SQLITE_TEXT :: 3
SQLITE_BLOB :: 4
SQLITE_NULL :: 5

SQLITE_TRACE_STMT :: 0x01
SQLITE_TRACE_PROFILE :: 0x02
SQLITE_TRACE_ROW :: 0x04
SQLITE_TRACE_CLOSE :: 0x08

reset :: proc "c" (stmt: ^sqlite3_stmt) -> c.int {
	if api == nil || api.reset == nil do return 1
	fn := cast(proc "c" (_: ^sqlite3_stmt) -> c.int)api.reset
	return fn(stmt)
}

malloc :: proc "c" (n: c.int) -> rawptr {
	if api == nil || api.malloc == nil do return nil
	fn := cast(proc "c" (_: c.int) -> rawptr)api.malloc
	return fn(n)
}

realloc :: proc "c" (p: rawptr, n: c.int) -> rawptr {
	if api == nil || api.realloc == nil do return nil
	fn := cast(proc "c" (_: rawptr, _: c.int) -> rawptr)api.realloc
	return fn(p, n)
}

free :: proc "c" (p: rawptr) {
	if api == nil || api.free == nil do return
	fn := cast(proc "c" (_: rawptr))api.free
	fn(p)
}

memory_used :: proc "c" () -> i64 {
	if api == nil || api.memory_used == nil do return 0
	fn := cast(proc "c" () -> i64)api.memory_used
	return fn()
}

memory_highwater :: proc "c" (reset: c.int) -> i64 {
	if api == nil || api.memory_highwater == nil do return 0
	fn := cast(proc "c" (_: c.int) -> i64)api.memory_highwater
	return fn(reset)
}

trace_v2 :: proc "c" (
	db: ^sqlite3,
	mask: c.uint,
	xCallback: proc "c" (t: c.uint, db_ptr: rawptr, p: rawptr, x: rawptr) -> c.int,
	pCtx: rawptr,
) -> c.int {
	if api == nil || api.trace_v2 == nil do return 1
	fn := cast(proc "c" (_: ^sqlite3, _: c.uint, _: rawptr, _: rawptr) -> c.int)api.trace_v2
	return fn(db, mask, cast(rawptr)xCallback, pCtx)
}
