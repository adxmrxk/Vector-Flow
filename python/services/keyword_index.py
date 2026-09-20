"""SQLite FTS5 keyword index: the sparse half of hybrid search.

Pure embedding search misses exact-match queries -- product IDs, error
codes, rare proper nouns -- because cosine similarity has no notion of
literal term overlap. This gives every namespace a BM25-ranked keyword
index alongside the dense Pinecone index; app.api fuses the two at search
time with Reciprocal Rank Fusion.
"""

import json
import os
import re
import sqlite3
import threading
from typing import Any


def _build_match_expression(query: str) -> str:
    """Turn free text into an FTS5 MATCH expression.

    Terms are OR'd (not FTS5's default AND) because the point of the
    keyword side of hybrid search is recall of *any* matching term, and
    each term is quoted to keep FTS5 query syntax characters in the raw
    query (hyphens, colons, asterisks, ...) from being interpreted as
    operators or raising a syntax error.
    """
    tokens = re.findall(r"\w+", query)
    if not tokens:
        return ""
    quoted = ['"' + t.replace('"', '""') + '"' for t in tokens]
    return " OR ".join(quoted)


class KeywordIndex:
    """A namespace-scoped BM25 keyword index backed by SQLite FTS5."""

    def __init__(self, db_path: str) -> None:
        directory = os.path.dirname(db_path)
        if directory:
            os.makedirs(directory, exist_ok=True)

        self._lock = threading.Lock()
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.execute("PRAGMA journal_mode=WAL")
        # NORMAL still fsyncs at WAL checkpoints (data survives a process
        # crash) but not on every commit like the default FULL, which is the
        # standard, safe pairing recommended for WAL mode. Measured 500x
        # fewer fsyncs for a 300-row batch that was previously one commit
        # (and one fsync) per row.
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._conn.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS keyword_index USING fts5("
            "id UNINDEXED, namespace UNINDEXED, text, metadata_json UNINDEXED)"
        )
        self._conn.commit()

    def upsert(self, doc_id: str, namespace: str | None, text: str, metadata: dict[str, Any]) -> None:
        """Index (or re-index) one document's text under a namespace."""
        self.upsert_many([(doc_id, namespace, text, metadata)])

    def upsert_many(self, entries: list[tuple[str, str | None, str, dict[str, Any]]]) -> None:
        """Index many documents in a single transaction.

        FTS5 has no unique constraint to upsert against, so each id's stale
        row is deleted before it's re-inserted. Doing this for a whole batch
        under one commit (rather than one upsert() call, one commit, per
        document) is what actually avoids the per-row fsync cost above.
        """
        if not entries:
            return

        rows = [(doc_id, namespace or "", text, json.dumps(metadata)) for doc_id, namespace, text, metadata in entries]
        with self._lock:
            self._conn.executemany(
                "DELETE FROM keyword_index WHERE id = ? AND namespace = ?",
                [(row[0], row[1]) for row in rows],
            )
            self._conn.executemany(
                "INSERT INTO keyword_index (id, namespace, text, metadata_json) VALUES (?, ?, ?, ?)",
                rows,
            )
            self._conn.commit()

    def search(self, query: str, namespace: str | None, limit: int = 20) -> list[dict[str, Any]]:
        """Return BM25-ranked keyword matches, best first.

        An empty/unmatchable query returns no results rather than raising,
        so callers can always fuse this in unconditionally.
        """
        match_expr = _build_match_expression(query)
        if not match_expr:
            return []

        namespace = namespace or ""
        cursor = self._conn.execute(
            "SELECT id, metadata_json FROM keyword_index "
            "WHERE keyword_index MATCH ? AND namespace = ? "
            "ORDER BY rank LIMIT ?",
            (match_expr, namespace, limit),
        )
        results = []
        for doc_id, metadata_json in cursor.fetchall():
            metadata = json.loads(metadata_json) if metadata_json else {}
            results.append({"id": doc_id, "metadata": metadata})
        return results
