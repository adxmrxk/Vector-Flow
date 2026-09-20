"""Unit tests for the chunk-vector-building and search dedup helpers in app.api.

These are pure functions with no model/network dependency, tested directly
so the chunking feature's edge cases (single chunk, multi-chunk, dedup) are
covered without needing a live Pinecone index.
"""

from app.api import _build_chunk_vectors, _dedupe_by_parent, _reciprocal_rank_fusion


def test_single_chunk_keeps_original_id_and_metadata() -> None:
    vectors = _build_chunk_vectors("doc-1", ["hello world"], [[0.1, 0.2]], {"source": "readme"})

    assert vectors == [{"id": "doc-1", "values": [0.1, 0.2], "metadata": {"source": "readme"}}]


def test_multi_chunk_tags_each_vector_with_parent_metadata() -> None:
    vectors = _build_chunk_vectors(
        "doc-2",
        ["part one", "part two"],
        [[0.1], [0.2]],
        {"source": "manual"},
    )

    assert [v["id"] for v in vectors] == ["doc-2#chunk0", "doc-2#chunk1"]
    for i, v in enumerate(vectors):
        assert v["metadata"]["parent_id"] == "doc-2"
        assert v["metadata"]["chunk_index"] == i
        assert v["metadata"]["chunk_count"] == 2
        assert v["metadata"]["source"] == "manual"


def test_multi_chunk_does_not_mutate_the_shared_metadata_dict() -> None:
    shared_metadata = {"source": "manual"}
    _build_chunk_vectors("doc-3", ["a", "b"], [[0.1], [0.2]], shared_metadata)

    assert shared_metadata == {"source": "manual"}


def test_dedupe_keeps_highest_scoring_chunk_per_parent() -> None:
    results = [
        {"id": "doc#chunk0", "score": 0.5, "metadata": {"parent_id": "doc"}},
        {"id": "doc#chunk1", "score": 0.9, "metadata": {"parent_id": "doc"}},
        {"id": "other", "score": 0.7, "metadata": {}},
    ]

    deduped = _dedupe_by_parent(results)

    ids = [r["id"] for r in deduped]
    assert "doc#chunk1" in ids
    assert "doc#chunk0" not in ids
    assert "other" in ids
    assert len(deduped) == 2


def test_dedupe_preserves_first_seen_order() -> None:
    results = [
        {"id": "b", "score": 0.5, "metadata": {}},
        {"id": "a", "score": 0.9, "metadata": {}},
    ]

    deduped = _dedupe_by_parent(results)

    assert [r["id"] for r in deduped] == ["b", "a"]


def test_dedupe_handles_missing_metadata() -> None:
    results = [{"id": "no-metadata-key", "score": 0.5}]

    deduped = _dedupe_by_parent(results)

    assert deduped == results


# ----- Reciprocal Rank Fusion (hybrid search) -----


def test_fusion_ranks_document_found_by_both_sides_first() -> None:
    dense = [
        {"id": "found-by-both", "score": 0.9, "metadata": {}},
        {"id": "dense-only", "score": 0.85, "metadata": {}},
    ]
    keyword = [
        {"id": "keyword-only", "metadata": {}},
        {"id": "found-by-both", "metadata": {}},
    ]

    fused = _reciprocal_rank_fusion(dense, keyword)

    assert fused[0]["id"] == "found-by-both"
    ids = {r["id"] for r in fused}
    assert ids == {"found-by-both", "dense-only", "keyword-only"}


def test_fusion_can_surface_a_keyword_only_hit_dense_search_missed() -> None:
    # This is the whole point of hybrid search: an exact-match document with
    # no semantic similarity to the query still needs to be findable.
    dense = [{"id": "semantically-similar", "score": 0.9, "metadata": {}}]
    keyword = [{"id": "exact-id-match", "metadata": {"sku": "SKU-99123"}}]

    fused = _reciprocal_rank_fusion(dense, keyword)

    ids = [r["id"] for r in fused]
    assert "exact-id-match" in ids


def test_fusion_replaces_score_with_a_ranking_signal() -> None:
    dense = [{"id": "a", "score": 0.9, "metadata": {}}]
    keyword = [{"id": "a", "metadata": {}}]

    fused = _reciprocal_rank_fusion(dense, keyword)

    # Two ranking hits at rank 1 each: 1/(60+1) + 1/(60+1).
    assert fused[0]["score"] == 2 / 61


def test_fusion_preserves_dense_metadata_for_shared_hits() -> None:
    dense = [{"id": "a", "score": 0.9, "metadata": {"text": "original"}}]
    keyword = [{"id": "a", "metadata": {}}]

    fused = _reciprocal_rank_fusion(dense, keyword)

    assert fused[0]["metadata"] == {"text": "original"}
