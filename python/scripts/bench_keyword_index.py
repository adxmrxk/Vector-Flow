"""Before/after benchmark for KeywordIndex commit batching.

Run: .venv/Scripts/python.exe scripts/bench_keyword_index.py
"""

import os
import sqlite3
import tempfile
import time

N_DOCS = 300


def bench_one_commit_per_row(db_path: str) -> float:
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(
        "CREATE VIRTUAL TABLE keyword_index USING fts5("
        "id UNINDEXED, namespace UNINDEXED, text, metadata_json UNINDEXED)"
    )
    conn.commit()

    start = time.perf_counter()
    for i in range(N_DOCS):
        conn.execute(
            "INSERT INTO keyword_index (id, namespace, text, metadata_json) VALUES (?, ?, ?, ?)",
            (f"doc-{i}", "ns", f"document body number {i}", "{}"),
        )
        conn.commit()
    elapsed = time.perf_counter() - start
    conn.close()
    return elapsed


def bench_one_commit_total(db_path: str) -> float:
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute(
        "CREATE VIRTUAL TABLE keyword_index USING fts5("
        "id UNINDEXED, namespace UNINDEXED, text, metadata_json UNINDEXED)"
    )
    conn.commit()

    start = time.perf_counter()
    conn.executemany(
        "INSERT INTO keyword_index (id, namespace, text, metadata_json) VALUES (?, ?, ?, ?)",
        [(f"doc-{i}", "ns", f"document body number {i}", "{}") for i in range(N_DOCS)],
    )
    conn.commit()
    elapsed = time.perf_counter() - start
    conn.close()
    return elapsed


with tempfile.TemporaryDirectory() as tmp:
    before = bench_one_commit_per_row(os.path.join(tmp, "before.db"))

with tempfile.TemporaryDirectory() as tmp:
    after = bench_one_commit_total(os.path.join(tmp, "after.db"))

print(f"Before (commit per row, synchronous=FULL default): {before:.3f}s  ({N_DOCS / before:.0f} docs/sec)")
print(f"After  (one commit for the batch, synchronous=NORMAL): {after:.3f}s  ({N_DOCS / after:.0f} docs/sec)")
print(f"Speedup: {before / after:.1f}x")
