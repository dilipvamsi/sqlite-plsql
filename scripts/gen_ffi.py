import re

def generate_odin_ffi(header_path):
    with open(header_path, 'r') as f:
        content = f.read()

    # Find the struct body
    start_marker = "struct sqlite3_api_routines {"
    start_idx = content.find(start_marker)
    if start_idx == -1:
        print("Could not find start marker")
        return

    end_idx = content.find("};", start_idx)
    struct_body = content[start_idx + len(start_marker):end_idx]

    # We want to find the first level of function pointers.
    # These look like: [type] (*[name])([args])
    # However, the [args] can contain other function pointers.
    # The key is that they are SEMICOLON separated at the top level.

    lines = struct_body.split(';')
    names = []

    for line in lines:
        line = line.strip()
        if not line: continue

        # Match the first "(*name)" pattern in each semicolon-separated block
        # This should correctly pick up the member name even if args have nested parens
        m = re.search(r'\(\*(.*?)\)', line)
        if m:
            name = m.group(1).strip()
            # If name is empty, it might be a weird case, but usually it works.
            if name:
                names.append(name)

    header = """package plsqlite

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
"""
    footer = """}

api: ^sqlite3_api_routines

// Helper wrappers for convenience
value_text :: proc "c" (val: ^sqlite3_value) -> cstring {
    if api == nil || api.value_text == nil do return nil
    fn := cast(proc "c" (^sqlite3_value) -> cstring)api.value_text
    return fn(val)
}

result_text :: proc "c" (ctx: ^sqlite3_context, data: cstring, n: c.int, xDel: rawptr) {
    if api == nil || api.result_text == nil do return
    fn := cast(proc "c" (^sqlite3_context, cstring, c.int, rawptr))api.result_text
    fn(ctx, data, n, xDel)
}

result_error :: proc "c" (ctx: ^sqlite3_context, msg: cstring, n: c.int) {
    if api == nil || api.result_error == nil do return
    fn := cast(proc "c" (^sqlite3_context, cstring, c.int))api.result_error
    fn(ctx, msg, n)
}

result_null :: proc "c" (ctx: ^sqlite3_context) {
    if api == nil || api.result_null == nil do return
    fn := cast(proc "c" (^sqlite3_context))api.result_null
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
    fn := cast(proc "c" (^sqlite3, cstring, c.int, c.int, rawptr, rawptr, rawptr, rawptr) -> c.int)api.create_function
    return fn(db, name, nArg, eTextRep, p, cast(rawptr)xFunc, cast(rawptr)xStep, cast(rawptr)xFinal)
}

exec :: proc "c" (db: ^sqlite3, sql: cstring, callback: sqlite3_callback, p: rawptr, pzErrMsg: [^]cstring) -> c.int {
    if api == nil || api.exec == nil do return 1
    fn := cast(proc "c" (^sqlite3, cstring, rawptr, rawptr, [^]cstring) -> c.int)api.exec
    return fn(db, sql, cast(rawptr)callback, p, pzErrMsg)
}

prepare_v2 :: proc "c" (db: ^sqlite3, sql: cstring, n: c.int, ppStmt: ^^sqlite3_stmt, pzTail: ^cstring) -> c.int {
    if api == nil || api.prepare_v2 == nil do return 1
    fn := cast(proc "c" (^sqlite3, cstring, c.int, ^^sqlite3_stmt, ^cstring) -> c.int)api.prepare_v2
    return fn(db, sql, n, ppStmt, pzTail)
}

step :: proc "c" (stmt: ^sqlite3_stmt) -> c.int {
    if api == nil || api.step == nil do return 1
    fn := cast(proc "c" (^sqlite3_stmt) -> c.int)api.step
    return fn(stmt)
}

finalize :: proc "c" (stmt: ^sqlite3_stmt) -> c.int {
    if api == nil || api.finalize == nil do return 1
    fn := cast(proc "c" (^sqlite3_stmt) -> c.int)api.finalize
    return fn(stmt)
}

bind_text :: proc "c" (stmt: ^sqlite3_stmt, i: c.int, data: cstring, n: c.int, xDel: rawptr) -> c.int {
    if api == nil || api.bind_text == nil do return 1
    fn := cast(proc "c" (^sqlite3_stmt, c.int, cstring, c.int, rawptr) -> c.int)api.bind_text
    return fn(stmt, i, data, n, xDel)
}

column_text :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> cstring {
    if api == nil || api.column_text == nil do return nil
    fn := cast(proc "c" (^sqlite3_stmt, c.int) -> cstring)api.column_text
    return fn(stmt, iCol)
}

column_name :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> cstring {
    if api == nil || api.column_name == nil do return nil
    fn := cast(proc "c" (^sqlite3_stmt, c.int) -> cstring)api.column_name
    return fn(stmt, iCol)
}

column_count :: proc "c" (stmt: ^sqlite3_stmt) -> c.int {
    if api == nil || api.column_count == nil do return 0
    fn := cast(proc "c" (^sqlite3_stmt) -> c.int)api.column_count
    return fn(stmt)
}

column_int :: proc "c" (stmt: ^sqlite3_stmt, iCol: c.int) -> c.int {
    if api == nil || api.column_int == nil do return 0
    fn := cast(proc "c" (^sqlite3_stmt, c.int) -> c.int)api.column_int
    return fn(stmt, iCol)
}

errmsg :: proc "c" (db: ^sqlite3) -> cstring {
    if api == nil || api.errmsg == nil do return nil
    fn := cast(proc "c" (^sqlite3) -> cstring)api.errmsg
    return fn(db)
}

context_db_handle :: proc "c" (ctx: ^sqlite3_context) -> ^sqlite3 {
    if api == nil || api.context_db_handle == nil do return nil
    fn := cast(proc "c" (^sqlite3_context) -> ^sqlite3)api.context_db_handle
    return fn(ctx)
}

SQLITE_OK :: 0
SQLITE_ROW :: 100
SQLITE_DONE :: 101
SQLITE_STATIC    :: rawptr(uintptr(0))
SQLITE_TRANSIENT :: rawptr(uintptr(18446744073709551615))
SQLITE_UTF8 :: 1
"""

    with open('sqlite_gen.odin', 'w') as f:
        f.write(header)
        for name in names:
            f.write(f"\t{name}: rawptr,\n")
        f.write(footer)

if __name__ == "__main__":
    generate_odin_ffi('headers/sqlite3ext.h')
    print("Odin FFI generated successfully.")
