"""Tests for services/keyword_index.py, the BM25 side of hybrid search.

Uses an in-memory SQLite DB per test, so these run instantly with no disk
I/O or model dependency.
"""

from services.keyword_index import KeywordIndex, _build_match_expression


def make_index() -> KeywordIndex:
    return KeywordIndex(":memory:")


def test_exact_term_match_is_found() -> None:
    idx = make_index()
    idx.upsert("doc-1", "ns", "Error code E4402 occurred during checkout", {"source": "logs"})

    results = idx.search("E4402", "ns")

    assert [r["id"] for r in results] == ["doc-1"]
    assert results[0]["metadata"] == {"source": "logs"}


def test_no_match_returns_empty_list() -> None:
    idx = make_index()
    idx.upsert("doc-1", "ns", "completely unrelated content", {})

    assert idx.search("E4402", "ns") == []


def test_search_is_scoped_per_namespace() -> None:
    idx = make_index()
    idx.upsert("doc-1", "tenant-a", "product SKU-99123", {})

    assert idx.search("SKU-99123", "tenant-a") != []
    assert idx.search("SKU-99123", "tenant-b") == []


def test_upsert_replaces_prior_text_for_the_same_id() -> None:
    idx = make_index()
    idx.upsert("doc-1", "ns", "original wording about apples", {})
    idx.upsert("doc-1", "ns", "revised wording about oranges", {})

    assert idx.search("apples", "ns") == []
    assert [r["id"] for r in idx.search("oranges", "ns")] == ["doc-1"]


def test_bm25_ranks_more_relevant_document_first() -> None:
    idx = make_index()
    idx.upsert("mentions-once", "ns", "a short note that mentions widget one time", {})
    idx.upsert("mentions-repeatedly", "ns", "widget widget widget widget widget", {})

    results = idx.search("widget", "ns")

    assert [r["id"] for r in results] == ["mentions-repeatedly", "mentions-once"]


def test_empty_query_returns_no_results() -> None:
    idx = make_index()
    idx.upsert("doc-1", "ns", "some text", {})

    assert idx.search("", "ns") == []


def test_match_expression_handles_special_characters_without_raising() -> None:
    idx = make_index()
    idx.upsert("doc-1", "ns", "path is C:/data/file-01.csv", {})

    # Must not raise even though the query contains FTS5 syntax characters.
    results = idx.search('C:/data/file-01.csv AND "quoted"', "ns")
    assert isinstance(results, list)


def test_build_match_expression_ors_every_token() -> None:
    assert _build_match_expression("hello world") == '"hello" OR "world"'


def test_build_match_expression_on_empty_input() -> None:
    assert _build_match_expression("   ") == ""
