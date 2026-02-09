import subprocess
import re
import sys
import os
from collections import defaultdict

DEBUG = os.getenv("BENCH_DEBUG", "1") != "0"

def run_bench(cmd, cwd="."):
    print(f"Running {cmd}...")
    env = os.environ.copy()
    if "BENCH_TX_COUNT" not in env:
        env["BENCH_TX_COUNT"] = "10"

    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd, env=env, timeout=600)
        output = result.stdout + "\n" + result.stderr
        if DEBUG:
            print(f"--- DEBUG: Output for {cmd} ---")
            print(output)
            print(f"--- DEBUG: End Output ---")
        return output
    except Exception as e:
        return f"Error: {str(e)}\n"

def parse_results(output):
    # data[UseCase][Language][Key] = Val
    data = defaultdict(lambda: defaultdict(lambda: {"app": "N/A", "pl": "N/A", "batch": "N/A"}))
    current_lang = "Unknown"
    current_case = "Unknown"

    lines = output.split("\n")
    for line in lines:
        line = line.strip()
        if not line: continue

        # Detection for start of language block
        if "---" in line and "Benchmarks" in line:
            l = line.strip("- ").replace(" Benchmarks", "").split("(")[0].strip()
            if "Node.js" in l: current_lang = "Node.js"
            elif "Python" in l: current_lang = "Python"
            elif "Go" in l: current_lang = "Go"
            elif "Rust" in l: current_lang = "Rust"
            elif "SQL CLI" in l: current_lang = "SQL CLI"
            if DEBUG: print(f"DEBUG: Found language: {current_lang} in line: {line}")
            continue

        # Detection for SQL CLI case markers
        if line.startswith("CASE:"):
            current_case = line.replace("CASE:", "").strip()
            if DEBUG: print(f"DEBUG: Found SQL Case: {current_case}")
            continue

        # Parsing native SQLite .timer output: "Run Time: real 0.XXX"
        if current_lang == "SQL CLI":
            # Parsing native SQLite .timer output: "Run Time: real 0.XXX"
            sql_m = re.search(r"Run Time:.*real\s+([\d\.]+)", line)
            if sql_m:
                try:
                    seconds = float(sql_m.group(1))
                    ms = seconds * 1000.0
                    val = f"{ms:.2f}"

                    target_case = current_case
                    if "Iteration" in target_case: target_case = "Iteration"
                    elif "Bulk" in target_case: target_case = "Bulk"
                    elif "Recursion" in target_case: target_case = "Recursion"
                    elif "Transaction" in target_case: target_case = "Transactions"

                    if DEBUG: print(f"DEBUG: SQL Match - Case: {target_case}, Val: {val}ms (from {seconds}s)")

                    if target_case == "Transactions":
                        data[target_case][current_lang]["batch"] = val
                    else:
                        data[target_case][current_lang]["pl"] = val
                    continue
                except ValueError:
                    pass

        # Standard RESULT: Case: Key: Valms markers
        m = re.search(r"RESULT:\s*([\w\-/ ]+):\s*([\w\-/ ]+):\s*([\d\.]+)ms", line)
        if m:
            case_name = m.group(1).strip()
            key = m.group(2).strip()
            val = m.group(3).strip()

            target_case = "Unknown"
            if "Iteration" in case_name: target_case = "Iteration"
            elif "Bulk" in case_name: target_case = "Bulk"
            elif "Recursion" in case_name: target_case = "Recursion"
            elif "Transaction" in case_name: target_case = "Transactions"

            if DEBUG: print(f"DEBUG: Match - Case: {target_case}, Key: {key}, Val: {val}")

            if "Batch" in key:
                data[target_case][current_lang]["batch"] = val
            elif "App" in key:
                data[target_case][current_lang]["app"] = val
            elif "PL/SQLite" in key or "Proc" in key:
                data[target_case][current_lang]["pl"] = val

    return data

def print_report(data):
    use_cases = ["Iteration", "Bulk", "Recursion", "Transactions"]
    langs = ["Python", "Node.js", "Go", "Rust", "SQL CLI"]

    for case in use_cases:
        print(f"\n[ BENCHMARK: {case} ]")
        if case == "Transactions":
            sep = "+" + "-"*15 + "+" + "-"*15 + "+" + "-"*15 + "+" + "-"*15 + "+" + "-"*10 + "+"
            print(sep)
            print(f"| {'Language':<13} | {'App-Layer':<13} | {'PL/SQL Proc':<13} | {'PL/SQL Batch':<13} | {'Speedup':<8} |")
            print(sep)
        else:
            sep = "+" + "-"*15 + "+" + "-"*15 + "+" + "-"*15 + "+" + "-"*10 + "+"
            print(sep)
            print(f"| {'Language':<13} | {'App-Layer':<13} | {'PL/SQLite':<13} | {'Speedup':<8} |")
            print(sep)

        for lang in langs:
            res = data[case][lang]
            app = res["app"]
            pl = res["pl"]
            batch = res["batch"]

            # Baseline fallback for SQL CLI speedup: use Python's app-layer
            baseline_app = app
            if lang == "SQL CLI" and baseline_app == "N/A":
                baseline_app = data[case].get("Python", {}).get("app", "N/A")

            if case == "Transactions":
                speedup = "N/A"
                compare_val = batch if batch != "N/A" else pl
                if baseline_app != "N/A" and compare_val != "N/A" and float(compare_val) > 0:
                    speedup = f"{float(baseline_app)/float(compare_val):.2f}x"

                app_s = f"{app} ms" if app != "N/A" else "N/A"
                pl_s = f"{pl} ms" if pl != "N/A" else "N/A"
                batch_s = f"{batch} ms" if batch != "N/A" else "N/A"
                print(f"| {lang:<13} | {app_s:>13} | {pl_s:>13} | {batch_s:>13} | {speedup:>8} |")
            else:
                speedup = "N/A"
                if baseline_app != "N/A" and pl != "N/A" and float(pl) > 0:
                    speedup = f"{float(baseline_app)/float(pl):.2f}x"

                app_s = f"{app} ms" if app != "N/A" else "N/A"
                pl_s = f"{pl} ms" if pl != "N/A" else "N/A"
                print(f"| {lang:<13} | {app_s:>13} | {pl_s:>13} | {speedup:>8} |")

        print(sep)

if __name__ == "__main__":
    tx_count = os.getenv("BENCH_TX_COUNT", "10")
    print(f"Collecting benchmarks (Transactions: {tx_count})...")

    full_output = ""
    for target in ["python", "node", "go", "rust", "sql"]:
        full_output += run_bench(f"make bench-{target}")

    data = parse_results(full_output)
    print_report(data)
