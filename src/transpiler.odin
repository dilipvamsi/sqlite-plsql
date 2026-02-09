package plsqlite

import "core:fmt"
import "core:strings"
import "core:unicode"

is_alphanumeric :: proc(r: rune) -> bool {
	return unicode.is_alpha(r) || unicode.is_digit(r) || r == '_'
}

// Safe slice helper to avoid out-of-bounds access on invalid UTF-8 or short strings
safe_slice :: proc(s: string, start, end: int) -> string {
	if start < 0 || start >= len(s) || end < start {
		return ""
	}
	real_end := end
	if real_end > len(s) {
		real_end = len(s)
	}
	return s[start:real_end]
}

has_prefix_insensitive :: proc(s, prefix: string) -> bool {
	if len(s) < len(prefix) do return false
	// Use slice safely
	check := safe_slice(s, 0, len(prefix))
	return strings.equal_fold(check, prefix)
}

is_boundary :: proc(s: string, idx: int) -> bool {
	if idx <= 0 do return true
	if idx >= len(s) do return true

	prev := rune(s[idx - 1])
	curr := rune(s[idx])

	res := is_alphanumeric(prev) != is_alphanumeric(curr)
	log_debug(
		"is_boundary: idx=%d, prev=%c(%v), curr=%c(%v), res=%v",
		idx,
		prev,
		is_alphanumeric(prev),
		curr,
		is_alphanumeric(curr),
		res,
	)
	return res
}

// find_keyword searches for a keyword in the string `s` starting from `start_idx`.
// It ensures the keyword is a distinct word (surrounded by boundaries) and ignores case.
find_keyword :: proc(s: string, keyword: string, start_idx: int) -> int {
	if start_idx < 0 || start_idx >= len(s) do return -1

	for i := start_idx; i <= len(s) - len(keyword); i += 1 {
		if has_prefix_insensitive(s[i:], keyword) {
			if is_boundary(s, i) && is_boundary(s, i + len(keyword)) {
				log_debug("find_keyword: matched %s at %d", keyword, i)
				return i
			}
		}
	}
	return -1
}

sql_quote :: proc(s: string, allocator := context.allocator) -> string {
	context = plsqlite_context()
	builder := strings.builder_make(allocator)
	for i in 0 ..< len(s) {
		if s[i] == '\'' {
			strings.write_string(&builder, "''")
		} else {
			strings.write_byte(&builder, s[i])
		}
	}
	return strings.to_string(builder)
}

// find_closing_paren finds the index of the matching closing parenthesis for the open parenthesis at `start_idx`.
// It handles nested parentheses to ensure the correct closing tag is found.
find_closing_paren :: proc(s: string, start_idx: int) -> int {
	level := 1
	for i := start_idx + 1; i < len(s); i += 1 {
		if s[i] == '(' do level += 1
		else if s[i] == ')' {
			level -= 1
			if level == 0 do return i
		}
	}
	return -1
}

// Pass 1: Variable substitution (@var -> __env_get)
transpile_variables :: proc(sql: string, proc_name: string) -> string {
	builder := strings.builder_make()
	idx := 0
	in_quote := false

	for idx < len(sql) {
		// Handle string literals to avoid replacing @ inside strings
		if sql[idx] == '\'' {
			in_quote = !in_quote
			strings.write_byte(&builder, sql[idx])
			idx += 1
			continue
		}

		// Found a variable start
		if !in_quote && sql[idx] == '@' {
			idx += 1
			var_name_start := idx
			// Scan until non-alphanumeric character (allow dots for scope.name)
			for idx < len(sql) {
				r := rune(sql[idx])
				if is_alphanumeric(r) || r == '.' {
					idx += 1
				} else {
					break
				}
			}

			var_name_len := idx - var_name_start
			if var_name_len > 0 {
				var_full_name := sql[var_name_start:idx]
				dot_idx := strings.index(var_full_name, ".")
				if dot_idx != -1 {
					// Format: @scope.variable -> __env_get('scope', 'variable')
					scope := var_full_name[:dot_idx]
					name := var_full_name[dot_idx + 1:]
					fmt.sbprintf(&builder, "__env_get('%s', '%s')", scope, name)
				} else {
					// Format: @variable -> __env_get('proc', 'variable')
					// We use the proc name as a boundary marker for search-up logic
					fmt.sbprintf(&builder, "__env_get('%s', '%s')", proc_name, var_full_name)
				}
			} else {
				// Lone @
				strings.write_byte(&builder, ' ')
			}
		} else {
			strings.write_byte(&builder, sql[idx])
			idx += 1
		}
	}

	return strings.to_string(builder)
}

// Pass 2: CALL statements (CALL proc(...) -> run_plsql('proc', ...))
// transpile_calls finds all `CALL proc_name(args)` patterns and replaces them with
// `run_plsql('proc_name', args)`. This allows procedures to be called as part of SQL expressions.
transpile_calls :: proc(sql: string) -> string {
	builder := strings.builder_make()
	idx := 0
	in_quote := false

	for idx < len(sql) {
		if sql[idx] == '\'' {
			in_quote = !in_quote
			strings.write_byte(&builder, sql[idx])
			idx += 1
			continue
		}

		if !in_quote &&
		   has_prefix_insensitive(sql[idx:], "CALL") &&
		   is_boundary(sql, idx) &&
		   is_boundary(sql, idx + 4) {
			// Find proc name
			proc_start := idx + 4
			for proc_start < len(sql) && unicode.is_space(rune(sql[proc_start])) do proc_start += 1

			proc_end := proc_start
			for proc_end < len(sql) && is_alphanumeric(rune(sql[proc_end])) do proc_end += 1

			if proc_end > proc_start {
				proc_name := sql[proc_start:proc_end]

				// Find open paren
				open_rel := strings.index(sql[proc_end:], "(")
				if open_rel != -1 {
					open_abs := proc_end + open_rel
					close_abs := find_closing_paren(sql, open_abs)
					if close_abs != -1 {
						args := sql[open_abs + 1:close_abs]
						trimmed_args := strings.trim_space(args)

						// Check if standalone statement
						is_stmt := false
						check_idx := idx - 1
						for check_idx >= 0 && unicode.is_space(rune(sql[check_idx])) do check_idx -= 1

						if check_idx < 0 {
							is_stmt = true
						} else {
							preceding := sql[check_idx]
							if preceding == ';' {
								is_stmt = true
							} else {
								// Check for THEN, ELSE, LOOP
								if check_idx >= 3 && has_prefix_insensitive(sql[check_idx - 3:], "THEN") do is_stmt = true
								else if check_idx >= 3 && has_prefix_insensitive(sql[check_idx - 3:], "ELSE") do is_stmt = true
								else if check_idx >= 3 && has_prefix_insensitive(sql[check_idx - 3:], "LOOP") do is_stmt = true
							}
						}

						if is_stmt {
							if len(trimmed_args) > 0 {
								fmt.sbprintf(
									&builder,
									"SELECT run_plsql('%s', %s);",
									proc_name,
									trimmed_args,
								)
							} else {
								fmt.sbprintf(&builder, "SELECT run_plsql('%s');", proc_name)
							}

							// Skip the semicolon if it exists in the original source
							semi_rel := strings.index(sql[close_abs:], ";")
							if semi_rel != -1 {
								idx = close_abs + semi_rel + 1
							} else {
								idx = close_abs + 1
							}
						} else {
							// Function call in an expression
							if len(trimmed_args) > 0 {
								fmt.sbprintf(
									&builder,
									"run_plsql('%s', %s)",
									proc_name,
									trimmed_args,
								)
							} else {
								fmt.sbprintf(&builder, "run_plsql('%s')", proc_name)
							}
							idx = close_abs + 1
						}
						continue
					}
				}
			}
		}
		strings.write_byte(&builder, sql[idx])
		idx += 1
	}

	return strings.to_string(builder)
}

// Pass 3: RETURN statements
// transpile_returns finds `RETURN expr;` statements and converts them into
// `SELECT __env_return(expr);`. This ensures proper return value handling and execution stopping.
transpile_returns :: proc(sql: string) -> string {
	builder := strings.builder_make()
	idx := 0
	in_quote := false

	for idx < len(sql) {
		if sql[idx] == '\'' {
			in_quote = !in_quote
			strings.write_byte(&builder, sql[idx])
			idx += 1
			continue
		}

		if !in_quote &&
		   has_prefix_insensitive(sql[idx:], "RETURN") &&
		   is_boundary(sql, idx) &&
		   is_boundary(sql, idx + 6) {
			semi_idx := strings.index(sql[idx:], ";")
			if semi_idx != -1 {
				expr := strings.trim_space(sql[idx + 6:idx + semi_idx])
				if len(expr) == 0 {
					fmt.sbprintf(&builder, "SELECT __env_return(NULL);")
				} else {
					fmt.sbprintf(&builder, "SELECT __env_return(%s);", expr)
				}
				idx += semi_idx + 1
				continue
			}
		}
		strings.write_byte(&builder, sql[idx])
		idx += 1
	}

	return strings.to_string(builder)
}

find_matching_block :: proc(s: string, start_idx: int, open_tag, close_tag: string) -> int {
	level := 1
	idx := start_idx + len(open_tag)
	in_quote := false

	for idx < len(s) {
		if s[idx] == '\'' {
			in_quote = !in_quote
			idx += 1
			continue
		}
		if !in_quote {
			if has_prefix_insensitive(s[idx:], open_tag) {
				// Check boundary at end of tag
				last_char := open_tag[len(open_tag) - 1]
				if !is_alphanumeric(rune(last_char)) || is_boundary(s, idx + len(open_tag)) {
					level += 1
					idx += len(open_tag)
					continue
				}
			}
			if has_prefix_insensitive(s[idx:], close_tag) {
				last_char := close_tag[len(close_tag) - 1]
				if !is_alphanumeric(rune(last_char)) || is_boundary(s, idx + len(close_tag)) {
					level -= 1
					if level == 0 {
						return idx
					}
					idx += len(close_tag)
					continue
				}
			}
			idx += 1
		} else {
			idx += 1
		}
	}
	return -1
}

// transpile_control_flow handles complex control structures (IF/ELSE, FOR loops).
// It recursively finds blocks and transforms them into calls to `__run_if` and `__proc_loop`.
// It handles nested blocks by finding matching END tags.
transpile_control_flow :: proc(sql: string, proc_name: string) -> string {
	builder := strings.builder_make()
	idx := 0
	in_quote := false

	for idx < len(sql) {
		if sql[idx] == '\'' {
			in_quote = !in_quote
			strings.write_byte(&builder, sql[idx])
			idx += 1
			continue
		}

		// IF
		if !in_quote &&
		   has_prefix_insensitive(sql[idx:], "IF") &&
		   is_boundary(sql, idx) &&
		   is_boundary(sql, idx + 2) {
			then_abs := find_keyword(sql, "THEN", idx + 2)
			if then_abs != -1 {
				end_rel := find_matching_block(sql, then_abs, "THEN", "END IF")
				if end_rel != -1 {
					condition := strings.trim_space(sql[idx + 2:then_abs])
					body := sql[then_abs + 4:end_rel]

					else_abs := find_keyword(body, "ELSE", 0)
					true_branch, false_branch: string
					if else_abs != -1 {
						true_raw := body[:else_abs]
						false_raw := body[else_abs + 4:]
						true_branch = transpile_plsqlite_recursive(true_raw, proc_name)
						false_branch = transpile_plsqlite_recursive(false_raw, proc_name)
					} else {
						true_branch = transpile_plsqlite_recursive(body, proc_name)
						false_branch = strings.clone("")
					}
					defer delete(true_branch)
					defer delete(false_branch)

					quoted_cond := sql_quote(condition)
					quoted_true := sql_quote(true_branch)
					quoted_false := sql_quote(false_branch)
					defer delete(quoted_cond)
					defer delete(quoted_true)
					defer delete(quoted_false)

					fmt.sbprintf(
						&builder,
						"SELECT __run_if('SELECT %s', '%s', '%s');",
						quoted_cond,
						quoted_true,
						quoted_false,
					)
					idx = end_rel + 6
					if idx < len(sql) && sql[idx] == ';' do idx += 1
					continue
				}
			}
		}

		// FOR
		if !in_quote && find_keyword(sql, "FOR", idx) == idx {
			in_abs := find_keyword(sql, "IN", idx + 3)
			loop_abs := -1
			if in_abs != -1 {
				loop_abs = find_keyword(sql, "LOOP", in_abs + 2)
			}

			if in_abs != -1 && loop_abs != -1 {
				end_rel := find_matching_block(sql, loop_abs, "LOOP", "END LOOP")
				if end_rel != -1 {
					var_name := strings.trim_space(sql[idx + 3:in_abs])
					query := strings.trim_space(sql[in_abs + 2:loop_abs])
					if len(query) > 0 && query[0] == '(' && query[len(query) - 1] == ')' {
						query = query[1:len(query) - 1]
					}
					body := sql[loop_abs + 4:end_rel]
					transpiled_body := transpile_plsqlite_recursive(body, proc_name)
					defer delete(transpiled_body)

					quoted_query := sql_quote(query)
					quoted_body := sql_quote(transpiled_body)
					defer delete(quoted_query)
					defer delete(quoted_body)

					log_debug("Matched FOR loop: var=%s", var_name)
					fmt.sbprintf(
						&builder,
						"SELECT __proc_loop('%s', '%s', '%s', '%s');",
						quoted_query,
						quoted_body,
						var_name,
						proc_name,
					)
					idx = end_rel + 8
					if idx < len(sql) && sql[idx] == ';' do idx += 1
					continue
				}
			}
		}

		// RANGE i IN (start, end, step) LOOP
		if !in_quote && find_keyword(sql, "RANGE", idx) == idx {
			log_debug("Found potential RANGE at %d in proc %s", idx, proc_name)
			log_debug("Found potential RANGE at %d", idx)
			in_abs := find_keyword(sql, "IN", idx + 5)
			loop_abs := -1
			if in_abs != -1 {
				log_debug("Found potential IN at %d: %s", in_abs, sql[in_abs:in_abs + 2])
				loop_abs = find_keyword(sql, "LOOP", in_abs + 2)
			}
			if loop_abs != -1 {
				log_debug("Found potential LOOP at %d: %s", loop_abs, sql[loop_abs:loop_abs + 4])
			} else {
				log_debug("Failed to find LOOP after IN at %d", in_abs)
			}

			if in_abs != -1 && loop_abs != -1 {
				end_rel := find_matching_block(sql, loop_abs, "LOOP", "END LOOP")
				log_debug("find_matching_block returned end_rel=%d", end_rel)
				if end_rel != -1 {
					var_name := strings.trim_space(sql[idx + 5:in_abs])
					range_expr := strings.trim_space(sql[in_abs + 2:loop_abs])
					log_debug("RANGE loop: var=%s expr=%s", var_name, range_expr)

					// Parse range_expr: (start, end, step)
					if len(range_expr) > 0 &&
					   range_expr[0] == '(' &&
					   range_expr[len(range_expr) - 1] == ')' {
						trimmed_range := range_expr[1:len(range_expr) - 1]

						// Smart split by comma, respecting balanced parentheses
						parts := make([dynamic]string)
						defer {
							for p in parts do delete(p)
							delete(parts)
						}

						start := 0
						depth := 0
						for i := 0; i < len(trimmed_range); i += 1 {
							if trimmed_range[i] == '(' do depth += 1
							else if trimmed_range[i] == ')' do depth -= 1
							else if trimmed_range[i] == ',' && depth == 0 {
								append(&parts, strings.clone(strings.trim_space(trimmed_range[start:i])))
								start = i + 1
							}
						}
						append(&parts, strings.clone(strings.trim_space(trimmed_range[start:])))

						if len(parts) >= 2 {
							start_expr := parts[0]
							end_expr := parts[1]
							step_expr := len(parts) >= 3 ? parts[2] : "1"
							transpiled_start := transpile_plsqlite_recursive(start_expr, proc_name)
							transpiled_end := transpile_plsqlite_recursive(end_expr, proc_name)
							transpiled_step := transpile_plsqlite_recursive(step_expr, proc_name)
							defer delete(transpiled_start)
							defer delete(transpiled_end)
							defer delete(transpiled_step)

							body := sql[loop_abs + 4:end_rel]
							log_debug("RANGE loop body length: %d", len(body))
							transpiled_body := transpile_plsqlite_recursive(body, proc_name)
							defer delete(transpiled_body)

							quoted_body := sql_quote(transpiled_body)
							defer delete(quoted_body)

							fmt.sbprintf(
								&builder,
								"SELECT __range_loop('%s', %s, %s, %s, '%s', '%s');",
								var_name,
								transpiled_start,
								transpiled_end,
								transpiled_step,
								quoted_body,
								proc_name,
							)
							idx = end_rel + 8
							if idx < len(sql) && sql[idx] == ';' do idx += 1
							continue
						}
					}
				}
			}
		}

		strings.write_byte(&builder, sql[idx])
		idx += 1
	}

	return strings.to_string(builder)
}

// transpile_assignments converts variable declarations and assignments (DECLARE/SET)
// into `SELECT __env_set(...)` calls. It ensures variables are properly scoped.
transpile_assignments :: proc(sql: string, proc_name: string) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.allocator)
	idx := 0
	in_quote := false

	for idx < len(sql) {
		if sql[idx] == '\'' {
			in_quote = !in_quote
			strings.write_byte(&builder, sql[idx])
			idx += 1
			continue
		}

		if !in_quote {
			is_assign := false
			keyword_len := 0
			if has_prefix_insensitive(safe_slice(sql, idx, len(sql)), "DECLARE") &&
			   is_boundary(sql, idx) &&
			   is_boundary(sql, idx + 7) {
				is_assign = true
				keyword_len = 7
				for idx + keyword_len < len(sql) && unicode.is_space(rune(sql[idx + keyword_len])) do keyword_len += 1
			} else if has_prefix_insensitive(safe_slice(sql, idx, len(sql)), "SET") &&
			   is_boundary(sql, idx) &&
			   is_boundary(sql, idx + 3) {
				// Check standalone
				is_standalone := false
				if idx == 0 {
					is_standalone = true
				} else {
					for i := idx - 1; i >= 0; i -= 1 {
						if !unicode.is_space(rune(sql[i])) {
							if sql[i] == ';' do is_standalone = true
							break
						}
						if i == 0 do is_standalone = true
					}
				}
				if is_standalone {
					is_assign = true
					keyword_len = 3
					for idx + keyword_len < len(sql) && unicode.is_space(rune(sql[idx + keyword_len])) do keyword_len += 1
				}
			}

			if is_assign {
				eq_rel := strings.index(sql[idx:], "=")
				semi_rel := strings.index(sql[idx:], ";")
				if eq_rel != -1 && semi_rel != -1 && eq_rel < semi_rel {
					var_name := strings.trim_space(sql[idx + keyword_len:idx + eq_rel])
					val_expr := strings.trim_space(sql[idx + eq_rel + 1:idx + semi_rel])

					scope := proc_name
					name := var_name
					dot_idx := strings.index(var_name, ".")
					if dot_idx != -1 {
						scope = var_name[:dot_idx]
						name = var_name[dot_idx + 1:]
					}

					fmt.sbprintf(
						&builder,
						"SELECT __env_set('%s', '%s', %s);",
						scope,
						name,
						val_expr,
					)
					idx += semi_rel + 1
					continue
				}
			}
		}

		strings.write_byte(&builder, sql[idx])
		idx += 1
	}

	return strings.to_string(builder)
}

// transpile_raises converts `RAISE "msg";` into `SELECT __env_raise("msg");`
transpile_raises :: proc(sql: string) -> string {
	builder := strings.builder_make()
	idx := 0
	in_quote := false

	for idx < len(sql) {
		if sql[idx] == '\'' {
			in_quote = !in_quote
			strings.write_byte(&builder, sql[idx])
			idx += 1
			continue
		}

		if !in_quote &&
		   has_prefix_insensitive(sql[idx:], "RAISE") &&
		   is_boundary(sql, idx) &&
		   is_boundary(sql, idx + 5) {
			semi_idx := strings.index(sql[idx:], ";")
			if semi_idx != -1 {
				msg := strings.trim_space(sql[idx + 5:idx + semi_idx])
				if len(msg) == 0 {
					fmt.sbprintf(&builder, "SELECT __env_raise(NULL);")
				} else {
					fmt.sbprintf(&builder, "SELECT __env_raise(%s);", msg)
				}
				idx += semi_idx + 1
				continue
			}
		}
		strings.write_byte(&builder, sql[idx])
		idx += 1
	}

	return strings.to_string(builder)
}

transpile_plsqlite_recursive :: proc(source: string, proc_name: string) -> string {
	context = plsqlite_context()
	trimmed := strings.trim_space(source)
	if len(trimmed) == 0 do return strings.clone("")

	s1 := transpile_calls(trimmed)
	defer delete(s1)
	s2 := transpile_returns(s1)
	defer delete(s2)
	s3 := transpile_control_flow(s2, proc_name)
	defer delete(s3)
	s4 := transpile_assignments(s3, proc_name)
	defer delete(s4)
	s5 := transpile_raises(s4)
	return s5
}

// transpile_plsqlite coordinates the transpilation process.
// It takes the PL/SQL source code and the procedure name, and runs it through multiple passes:
// 1. `transpile_calls`: Converts `CALL proc(...)` to nested `run_plsql` calls.
// 2. `transpile_returns`: Converts `RETURN expr` to `__env_return` calls.
// 3. `transpile_control_flow`: Converts `IF/ELSE` and `FOR` loops to SQL logic using `__run_if` and `__proc_loop`.
// 4. `transpile_assignments`: Converts `DECLARE` and `SET` to `__env_set` calls.
// 5. `transpile_raises`: Converts `RAISE "msg"` to `__env_raise` calls.
transpile_plsqlite :: proc(source: string, proc_name: string) -> string {
	context = plsqlite_context()
	log_debug("Transpilation Start: proc=%s", proc_name)

	s1 := transpile_variables(source, proc_name)
	defer delete(s1)

	s2 := transpile_calls(s1)
	defer delete(s2)

	// Control flow (IF, FOR, RANGE) must happen before general assignments
	// to ensure keywords are matched correctly.
	s3 := transpile_control_flow(s2, proc_name)
	defer delete(s3)

	s4 := transpile_assignments(s3, proc_name)
	defer delete(s4)

	s5 := transpile_returns(s4)
	defer delete(s5)

	s6 := transpile_raises(s5)
	log_debug("Transpilation End: proc=%s", proc_name)

	return s6
}
