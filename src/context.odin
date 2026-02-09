package plsqlite

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"

// Global tracking allocator
track: mem.Tracking_Allocator
track_initialized: bool

// plsqlite_context returns a context that uses the tracking allocator.
// It initializes the allocator on the first call.
plsqlite_context :: proc() -> runtime.Context {
	if !track_initialized {
		mem.tracking_allocator_init(&track, runtime.default_allocator())
		track_initialized = true
	}

	ctx := runtime.default_context()
	ctx.allocator = mem.tracking_allocator(&track)
	return ctx
}

// plsql_leak_report is an SQL function that prints the current memory usage and leaks.
// Usage: SELECT plsql_leak_report();
plsql_leak_report :: proc "c" (ctx: ^sqlite3_context, nArg: c.int, apArg: [^]^sqlite3_value) {
	context = plsqlite_context()

	if len(track.allocation_map) > 0 {
		fmt.printf("=== Memory Leaks Detected ===\n")
		for _, entry in track.allocation_map {
			fmt.printf("- %v bytes @ %v\n", entry.size, entry.location)
		}
		fmt.printf("=============================\n")
		result_text(ctx, "Leaks detected! Check stdout.", -1, SQLITE_TRANSIENT)
	} else {
		fmt.printf("=== No Memory Leaks ===\n")
		result_text(ctx, "No leaks detected.", -1, SQLITE_TRANSIENT)
	}

	// Also print memory stats
	fmt.printf("Total Allocated: %v bytes\n", track.total_memory_allocated)
	fmt.printf("Current Allocation Count: %v\n", len(track.allocation_map))
}
