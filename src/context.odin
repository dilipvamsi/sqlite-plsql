package plsqlite

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"

// Global context definition
tracking_allocator: mem.Tracking_Allocator
tracking_allocator_initialized: bool = false

@(thread_local)
temp_arena: mem.Arena
temp_arena_initialized: bool = false

plsqlite_context :: proc() -> runtime.Context {
	ctx := runtime.default_context()

	if !temp_arena_initialized {
		// Use a reasonable initial size, it will grow if needed because we use the default allocator as backing
		arena_buf := make([]byte, 64 * 1024)
		mem.arena_init(&temp_arena, arena_buf)
		temp_arena_initialized = true
	}
	ctx.temp_allocator = mem.arena_allocator(&temp_arena)

	if DEBUG_ENABLED {
		if !tracking_allocator_initialized {
			mem.tracking_allocator_init(&tracking_allocator, runtime.default_allocator())
			tracking_allocator_initialized = true
		}
		ctx.allocator = mem.tracking_allocator(&tracking_allocator)
	}

	return ctx
}

// __plsql_leak_report reports SQLite memory usage stats.
// Note: PL/SQL runtime memory usage is not tracked here when using the default allocator.
__plsql_leak_report :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	defer free_all(context.temp_allocator)

	used := memory_used()
	high := memory_highwater(0)

	fmt.printf("=== SQLite Memory Stats ===\n")
	fmt.printf("Current Memory Used: %v bytes\n", used)
	fmt.printf("Highwater Mark:      %v bytes\n", high)
	fmt.printf("(Note: PL/SQL allocations use system allocator and are not included above)\n")

	if DEBUG_ENABLED && tracking_allocator_initialized {
		fmt.printf("\n=== PL/SQL Tracking Allocator Stats ===\n")
		fmt.printf("Total Allocations: %d\n", tracking_allocator.total_allocation_count)
		fmt.printf("Total Frees:       %d\n", tracking_allocator.total_free_count)

		if len(tracking_allocator.allocation_map) > 0 {
			fmt.printf("!!! %d DETECTED LEAKS !!!\n", len(tracking_allocator.allocation_map))
			for _, entry in tracking_allocator.allocation_map {
				fmt.printf("- %v bytes at %v\n", entry.size, entry.location)
			}
		} else {
			fmt.printf("No leaks detected in PL/SQL runtime.\n")
		}
		fmt.printf("========================================\n")
	}
	fmt.printf("===========================\n")

	msg := fmt.tprintf("Used: %d, High: %d", used, high)
	c_msg := strings.clone_to_cstring(msg)
	defer delete(c_msg)
	result_text(ctx, c_msg, -1, SQLITE_TRANSIENT)
}

// __plsql_reset clears the tracking allocator to distinguish tracker overhead from real leaks.
// Note: We don't destroy it anymore to avoid invalid reads when connection closes later.
__plsql_reset :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()
	if tracking_allocator_initialized {
		clear(&tracking_allocator.allocation_map)
		tracking_allocator.total_allocation_count = 0
		tracking_allocator.total_free_count = 0
	}
	result_null(ctx)
}
