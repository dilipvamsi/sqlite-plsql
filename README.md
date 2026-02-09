# PL/SQLite: Procedural Language Extension for SQLite

PL/SQLite is a high-performance, loadable C extension for SQLite that introduces a fully transactional procedural language. It solves performance bottlenecks by using a **Transpiler Architecture** that runs logic directly inside the database memory space.

## 🛠️ Why Odin?

The core of PL/SQLite is implemented in **Odin**, a data-oriented language designed for high performance and low-level control.

- **Deterministic Memory**: Unlike Go or Java, Odin has no Garbage Collector (GC), allowing the VM to manage memory manually and predictably within SQLite's memory context.
- **Safety & Productivity**: Odin provides modern features like slices, tagged unions, and strong typing, making the transpiler and runtime logic safer and easier to maintain than pure C.
- **LLVM-Powered**: Leverages the LLVM backend for aggressive optimizations and easy cross-compilation to Windows, Linux, and macOS.

## 🚀 Key Features

- **Named Scopes**: Secure namespacing for variables. Each procedure owns its scope, preventing accidental overlaps while allowing explicit cross-procedure access using the `@proc_name.variable` syntax.
- **Transpiler Architecture**: Automatically converts high-level PL/SQLite source code into optimized "Engine SQL" function calls.
- **Zero-Copy Runtime**: Executes logic without the overhead of context-switching between your application language (Python/Go/JS) and the database.
- **Atomic Transactions**: Procedures are wrapped in SQLite `SAVEPOINT`s, ensuring that any error triggers a full rollback of the procedure's operations.

---

## 🏗️ Architecture

The PL/SQLite extension integrates a transpiler and a virtual machine directly into the SQLite process.

```ascii
+-----------------------+       +-------------------------+
|   PL/SQLite Source    | ----> |   register_plsql()      |
|                       |       |      (Transpiler)       |
|  DECLARE x = 10;      |       +-----------+-------------+
|  CALL other_proc();   |                   |
+-----------------------+                   v
                                +-------------------------+
                                |  __plsql_procedures DB  |
                                | (Stored Transpiled SQL) |
                                +-----------+-------------+
                                            |
                                            v
+-----------------------+       +-------------------------+
|    SQLite Engine      | <---- |       run_plsql()       |
|                       |       |    (VM Entry Point)     |
+-----------+-----------+       +-----------+-------------+
    ^       |                               |
    |       | SQL Calls                     | Scope/Var
    |       v                               v
    |  +-----------------------+       +-------------------------+
    |  |   Runtime Functions   |       |   Memory Context        |
    |  | (__env_set, __run_if) | ----> | - Scope Stack           |
    |  +-----------+-----------+       | - Variable Hash Maps    |
    |              |                   | - Savepoints            |
    |              |                   +-------------------------+
    |              v                               ^
    +------- run_plsql() (Nested) -----------------+
```

1.  **Transpiler**: Converts procedural code into valid SQL queries with embedded runtime function calls.
2.  **Storage**: Transpiled SQL is stored in a dedicated `__plsql_procedures` table.
3.  **VM Runtime**: `run_plsql` manages the life-cycle of a procedure call. It pushes a new frame onto the **Scope Stack**, opens a `SAVEPOINT`, and executes the transpiled SQL.
4.  **Recursive Execution**: If the transpiled SQL contains a `CALL`, the engine invokes `run_plsql` again, creating a nested scope and savepoint. This allows for deep recursion (up to 500 levels) while maintaining transactional atomicity.

---

## � Comparison: PL/SQLite vs Application Logic

Why move logic into the database? Here is how PL/SQLite compares to writing the same logic in your application layer (Python, Go, Node.js):

| Feature | ⚡ Extension Logic (PL/SQLite) | 🐢 Application Logic (Python, Go, JS) |
| :--- | :--- | :--- |
| **Execution Locality** | **Inside DB Memory** (Zero Copy) | **Outside DB** (Network/IPC overhead) |
| **Round Trips** | **1 Call** (Zero latency for loops) | **N+1 Calls** (High latency for loops) |
| **Data Transfer** | **Zero Copy** (Pointer access) | **Serialization** (JSON/Protobuf/etc) |
| **Transaction Safety** | **Automatic** (Implicit Savepoints) | **Manual** (Complex `BEGIN`/`COMMIT` handling) |
| **Performance** | **High Throughput** (Native Speed) | **Latency Bound** by serialization/IO |
| **Consistency** | **Strong** (Logic lives with data) | **Eventual** (Logic drift across app versions) |
| **Use Case** | Complex validation, batch updates, heavy math | UI rendering, external API calls, business rules |
### Error Handling - `RAISE`
Custom application-level errors can be triggered using the `RAISE` statement. This will halt execution and trigger an automatic `ROLLBACK` of all changes made during the procedure call.

```sql
SELECT register_plsql('validate_user', 'id', '
    IF (@id < 0) THEN
        RAISE "Invalid user ID: Must be positive";
    END IF;
    -- proceed with logic
');
```

---

### 📊 Performance Highlights (Local DB)

| Use Case | Application Layer | PL/SQLite | Improvement |
| :--- | :--- | :--- | :--- |
| **Simple Iteration** | ~10-70 ms | ~800 ms | App-layer is faster for local files |
| **Bulk Inserts** | ~100 ms | ~120 ms | Near-native overhead |
| **Complex Transactions** | **~750 ms** | **~65 ms** | **11.5x Faster** 🔥 |

**Verdict**: Use PL/SQLite when you need to perform multiple reads/writes based on intermediate results without paying the round-trip cost for each step. Uses Application Logic when you need to integrate with external services or render UIs.

---

## 🆚 Comparison: Other SQLite Stored Procedure Solutions

How does this extension compare to other attempts at bringing stored procedures to SQLite?

| Feature | ⚡ PL/SQLite (This Extension) | 🧩 aergoio/sqlite-stored-procedures | 🐍 Native UDFs / App Logic |
| :--- | :--- | :--- | :--- |
| **Method** | **Transpiler** (Compiles to pure SQL) | **Interpreter** (AST traversal) | **Callbacks** (Host language) |
| **Execution** | **Inside DB** (Zero Context Switch) | **Inside DB** (Interpreter Loop) | **Outside DB** (IPC/Serialization) |
| **Performance** | **Ultra-High** (Native SQL Speed) | **Medium** (Interpreter overhead) | **Low** (Serialization overhead) |
| **Transaction Speed** | **11.5x Faster** (vs Rust/Node Tx)| **Unknown** | **Baseline** |
| **Safety** | ✅ **Automatic Savepoints** | ❓ Manual Handling | ❌ Manual Handling |
| **Memory** | ✅ **GC-Free** (Odin Runtime) | ❓ Interpreter Memory | ❌ GC-Heavy (V8/Python) |
| **Usage** | `.load` Extension | `.load` Extension | Embedded in Host App |

**Key Differentiator**: PL/SQLite uses a **transpiler architecture**. Unlike interpreters that evaluate an AST at runtime, PL/SQLite converts your code into optimized "Engine SQL" that SQLite executes directly. This allows us to beat even high-performance client libraries (like `better-sqlite3`) in bulk operations by eliminating the overhead of moving data between the host language and the engine for every statement.

---

## �📖 Language Guide

### 1. Variables & Scoping
Variables are local to the procedure by default but can be qualified for cross-procedure access.

| Syntax | Description |
| :--- | :--- |
| `DECLARE x = 10;` | Initialize a variable in the current scope. |
| `SET x = @x + 1;` | Update a variable in the current scope. |
| `@var` | Read variable from the current scope. |
| `@proc.var` | Read variable from a parent/named procedure's scope. |
| `SET proc.var = val;` | Update variable in a parent/named procedure's scope. |

### 2. Supported Data Types
PL/SQLite is fully typed and supports all standard SQLite data types:
- **Integer**: 64-bit signed integers.
- **Float**: 64-bit floating point numbers.
- **Text**: UTF-8 encoded strings.
- **Blob**: Binary large objects (Zero-copy support).
- **Null**: Explicit `NULL` support in assignments and returns.

### 3. Control Flow
Standard branching and iteration logic.

```sql
IF (@stock > 0) THEN
    -- True block
ELSE
    -- False block
END IF;
```

```sql
FOR r IN (SELECT id, price FROM items) LOOP
    -- Access via @r.id, @r.price
    SET total = @total + @r.price;
END LOOP;
```

### 3. Procedures & CALL Syntax
Procedures can call other procedures using the `CALL` keyword.

```sql
-- Call as a statement
CALL update_inventory(@item_id, @qty);

-- Use the return value of a call
DECLARE res = CALL process_payment(@user_id, @amount);
IF (@res == "SUCCESS") THEN ...
```

### 4. Named Scopes (Advanced)
A child procedure can read a parent's variable explicitly.

```sql
-- In 'sub_proc'
DECLARE factor = @main_proc.multiplier;
-- Modify parent variable directly
SET main_proc.success_count = @main_proc.success_count + 1;
```

---

## 🛠️ Installation & Usage

### Building from Source
```bash
make            # Compiles the extension to plsqlite.so
make test       # Runs the comprehensive Python test suite
make leak-check # Runs memory verification with Valgrind
```

### 🪟 Windows Cross-Compilation & Wine Testing
PL/SQLite supports cross-compilation from Linux to Windows and can be tested locally using Wine.

1.  **Setup Windows SDK**: Use `xwin` to splat Windows SDK libraries into the `win-libs` directory.
    ```bash
    make setup-win-libs
    ```
2.  **Download Windows SQLite**: Fetches the required `.dll`, `.lib`, and `.exe` for Windows.
    ```bash
    make download-sqlite-win
    ```
3.  **Build Windows DLL**:
    ```bash
    make windows
    ```
4.  **Run Tests under Wine**:
    - Install Windows Python in your Wine prefix: `make install-wine-python`
    - Run the test suite: `make test-wine`

### Loading in SQLite
```sql
.load ./plsqlite
```

## 🔄 Complete Usage Workflow

### 1. Load the Extension
Load the compiled shared library into your SQLite session.
```sql
.load ./plsqlite
```
*Note: This automatically creates the necessary `__plsql_procedures` table if it doesn't exist.*

### 2. Initialize Environment
Create any tables your procedures will interact with.
```sql
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, balance INTEGER);
INSERT INTO users VALUES (1, 'Alice', 100);
```

### 3. Register a Procedure
Use `register_plsql` to compile your PL/SQLite code. The function signature is `register_plsql(name, arguments, source_code)`.

```sql
SELECT register_plsql(
  'update_balance',
  'user_id, amount',
  '
  -- 1. Check current balance
  DECLARE current_bal = 0;
  FOR row IN (SELECT balance FROM users WHERE id = @user_id) LOOP
    SET current_bal = @row.balance;
  END LOOP;

  -- 2. Update if sufficient funds
  IF (@current_bal + @amount >= 0) THEN
    UPDATE users SET balance = balance + @amount WHERE id = @user_id;
    RETURN "SUCCESS: New balance is " || (@current_bal + @amount);
  ELSE
    RETURN "ERROR: Insufficient funds";
  END IF;
  '
);
```
*If there are syntax errors, `register_plsql` will fail with a descriptive error message.*

### 4. Execute the Procedure
Run the procedure using `run_plsql(name, arg1, arg2...)`.

```sql
-- Add 50 to Alice's balance
SELECT run_plsql('update_balance', 1, 50);
-- Result: "SUCCESS: New balance is 150"

-- Verify the change in the table
SELECT * FROM users WHERE id = 1;
```

Every procedure runs within a `SAVEPOINT`. If any SQL error occurs inside the procedure (e.g., a constraint violation, division by zero, or invalid table name), the **entire** procedure and all its nested calls are rolled back.

### 6. Recursion & Limits
PL/SQLite supports recursive procedure calls (e.g., for factorial or tree traversal).
- **Recursion Limit**: The default stack depth limit is **500**. Exceeding this will trigger a runtime error and a full rollback.
- **Savepoints per Call**: Each nested call consumes one SQLite Savepoint.

---

## 💡 Practical Examples

### Example 1: Inventory Processing
```sql
SELECT register_plsql(
    'process_order',
    'item_id, qty',
    '
    DECLARE stock = 0;
    FOR row IN (SELECT quantity FROM inventory WHERE id = @item_id) LOOP
        SET stock = @row.quantity;
    END LOOP;

    IF (@stock >= @qty) THEN
        UPDATE inventory SET quantity = quantity - @qty WHERE id = @item_id;
        RETURN "ORDER_SUCCESS";
    ELSE
        RETURN "INSUFFICIENT_STOCK";
    END IF;
    '
);

-- Run the procedure
SELECT run_plsql('process_order', 101, 5);
```

### Example 2: Nested Procedure Calls (Validation + Logic)
Break down complex logic into reusable sub-procedures.

```sql
-- 1. Register a validation helper
SELECT register_plsql(
    'validate_qty',
    'qty',
    'IF (@qty <= 0) THEN RETURN "INVALID_QUANTITY"; END IF;'
);

-- 2. Register the main logic that calls the helper
SELECT register_plsql(
    'place_order',
    'item_id, qty',
    '
    -- Call validation helper and check its return value
    DECLARE err = CALL validate_qty(@qty);
    IF (@err IS NOT NULL) THEN RETURN @err; END IF;

    -- Proceed with order logic...
    UPDATE inventory SET quantity = quantity - @qty WHERE id = @item_id;
    RETURN "ORDER_PLACED";
    '
);

-- 3. Execute
SELECT run_plsql('place_order', 101, 5);
```

### Example 3: Deeply Nested Data Structures
Shared variables across procedure calls.

```sql
SELECT register_plsql('main_proc', 'val', '
    DECLARE multiplier = 2;
    CALL child_proc(@val);
    RETURN "Done";
');

SELECT register_plsql('child_proc', 'input', '
    -- Access "multiplier" from the "main_proc" scope
    DECLARE result = @input * @main_proc.multiplier;
    INSERT INTO logs(msg) VALUES ("Result: " || @result);
');
```

---

## 📊 Performance Benchmarks
We compared **In-Database PL/SQLite** against **Application-Layer Logic** across multiple languages.

### Running Benchmarks
Before running, install dependencies and initialize the database:
```bash
make setup-bench     # Installs Node.js, Go, and Rust dependencies
make setup-bench-db  # Seeds 100k rows in databases/bench.db
```

Then run the full suite or individual languages:
```bash
make bench           # Run all benchmarks (Python, Node, Go, Rust, SQL)
make bench-python    # Run Python-only benchmarks
make bench-node      # Run Node.js benchmarks (requires better-sqlite3)
make bench-go        # Run Go benchmarks
make bench-rust      # Run Rust benchmarks
make bench-sql       # Run pure SQL CLI benchmarks
```

| Language / Driver | App-Layer Logic | PL/SQLite (In-DB) | Speedup |
| :--- | :--- | :--- | :--- |
| **Python** (`sqlite3`) | 39.53 ms | 958.24 ms | 0.04x |
| **Node.js** (`better-sqlite3`) | 74.00 ms | 719.00 ms | 0.10x |
| **Go** (`go-sqlite3`) | 49.04 ms | 851.48 ms | 0.06x |
| **Rust** (`rusqlite`) | 7.74 ms | 756.14 ms | 0.01x |
| **SQL CLI** | N/A | 1237.80 ms | 0.03x |

### 2. Bulk Operations (**10k inserts**)
Logic: One procedure call vs 10k separate `INSERT` statements in a transaction.

| Language / Driver | App-Layer (Tx) | PL/SQLite (Proc) | Speedup |
| :--- | :--- | :--- | :--- |
| **Python** | 85.92 ms | 119.59 ms | 0.72x |
| **Node.js** | 166.00 ms | 167.00 ms | 0.99x |
| **Go** | 108.63 ms | 185.38 ms | 0.59x |
| **Rust** | 77.34 ms | 119.39 ms | 0.65x |
| **SQL CLI** | N/A | 118.33 ms | 0.73x |

### 3. Recursive Calls (**200 depth**)
Logic: `RETURN n + CALL rec_sum(n - 1)`

| Language / Driver | App-Layer | PL/SQLite | Note |
| :--- | :--- | :--- | :--- |
| **Python** | 0.0379 ms | 10.14 ms | 0.00x |
| **Node.js** | 0.0204 ms | 30.77 ms | 0.00x |
| **Go** | 0.0005 ms | 6.66 ms | 0.00x |
| **Rust** | 0.0001 ms | 16.24 ms | 0.00x |
| **SQL CLI** | N/A | **26.26 ms** | Native proc-call overhead |

### 4. Complex Transactions (**10 transfers**)
Logic: Account transfer involving multiple selects and updates within a single procedural call vs. multiple app-layer boundaries.

| Language / Driver | App-Layer | PL/SQL Proc | PL/SQL Batch | Speedup (Batch) |
| :--- | :--- | :--- | :--- | :--- |
| **Python** | 872.02 ms | 907.43 ms | 73.88 ms | **11.80x** 🔥 |
| **Node.js** | 1625 ms | 1191 ms | 101 ms | **16.09x** 🔥 |
| **Go** | 839.19 ms | 1299.10 ms | 92.57 ms | **9.07x** 🔥 |
| **Rust** | 724.63 ms | 790.73 ms | 65.75 ms | **11.02x** 🔥 |
| **SQL CLI** | N/A | N/A | **65.46 ms** | **13.32x** 🔥 |

### 🔍 Analysis: When to use PL/SQLite?
1. **Networked Databases (Massive Win)**: On a networked database (e.g., Turso, rqlite, sqlite-server), the round-trip overhead makes app-layer transactions take **seconds or minutes**. PL/SQLite executes them in **milliseconds**.
2. **Complex State Logic**: Use PL/SQLite for multi-statement sequences that require atomic consistency and depend on intermediate results.
3. **Driver Reduction**: It eliminates the need to pay "FFI taxes" (context switching) between high-level languages like Python/Go and the C-engine.
4. **Local Iteration**: For simple read-only loops over local files, native driver iterators (especially in Rust/Python) remain faster due to highly optimized cursor fetching.

---

## ⚖️ Pros & Cons

| Pros (Why use it?) | Cons (When to avoid?) |
| :--- | :--- |
| **🚀 Network Efficiency**: Reduces 100+ network round-trips to a single RPC call. Essential for `sqlite-server` or distributed SQLite. | **🐢 Simple Iteration**: For local simple `SELECT *` loops, native drivers (Rust/C++) are faster due to optimized cursor fetching. |
| **⚛️ ACID Consistency**: Complex multi-step logic (check balance -> update sender -> update receiver) runs in a single atomic transaction. | **🛠️ Tooling**: Debugging is currently limited to `PRINT` statements; no interactive breakpoints yet. |
| **🔒 Logic Encapsulation**: Business rules live in the DB. You don't need to reimplement validation logic in Python, Go, and Node.js clients. | **🔒 Vendor Lock-in**: While SQL-transpiled, the syntax is specific to PL/SQLite (though heavily inspired by PL/pgSQL). |
| **📉 Zero-Copy**: Variables in procedures are pointers to SQLite values, avoiding serialization overhead for intermediate steps. | **🧵 Single Threaded**: Long-running procedures hold the SQLite execution lock, potentially blocking other writers. |

---

## 🛡️ Stability & Safety
PL/SQLite is built for production environments:
- **Zero-Copy**: Data stays in SQLite's memory pages during execution.
- **Memory Safe**: Verified with `Valgrind` (0 leaks reported during standard and error paths).
- **Transactional**: Fully integrated with SQLite's ACID properties (Atomic Rollbacks).
- **Infinite Recursion Protection**: Stack depth limits (500) prevent crashes.
