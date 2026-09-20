"""Unit tests for services/chunking.py.

Uses a fake tokenizer so these run instantly with no model download,
independent of the API-level integration tests.
"""

import pytest

from services.chunking import chunk_text


class WordTokenizer:
    """A tiny stand-in tokenizer: one token per whitespace-separated word.

    Real HuggingFace tokenizers behave the same way from chunk_text's point
    of view (encode -> list[int], decode -> str), so this is enough to test
    the windowing logic without loading a real model.
    """

    def encode(self, text: str, add_special_tokens: bool = False) -> list[int]:
        return list(range(len(text.split())))

    def decode(self, token_ids: list[int], skip_special_tokens: bool = True) -> str:
        words = self._words
        return " ".join(words[i] for i in token_ids)

    def bind(self, text: str) -> "WordTokenizer":
        self._words = text.split()
        return self


def tokenizer_for(text: str) -> WordTokenizer:
    return WordTokenizer().bind(text)


def test_short_text_returns_single_unmodified_chunk() -> None:
    text = "the quick brown fox"
    tok = tokenizer_for(text)
    assert chunk_text(text, tok, max_tokens=10) == [text]


def test_long_text_is_split_into_multiple_chunks() -> None:
    text = " ".join(f"word{i}" for i in range(25))
    tok = tokenizer_for(text)
    chunks = chunk_text(text, tok, max_tokens=10, overlap_tokens=2)
    assert len(chunks) > 1
    # Every word from the original text must survive somewhere.
    seen = set(" ".join(chunks).split())
    assert seen == set(text.split())


def test_consecutive_chunks_overlap() -> None:
    text = " ".join(f"w{i}" for i in range(20))
    tok = tokenizer_for(text)
    chunks = chunk_text(text, tok, max_tokens=8, overlap_tokens=3)

    first_words = chunks[0].split()
    second_words = chunks[1].split()
    # The last `overlap_tokens` words of chunk 1 should reappear at the
    # start of chunk 2, so a sentence spanning the boundary isn't lost.
    assert first_words[-3:] == second_words[:3]


def test_rejects_non_positive_max_tokens() -> None:
    with pytest.raises(ValueError):
        chunk_text("hello", tokenizer_for("hello"), max_tokens=0)


def test_rejects_overlap_not_smaller_than_max_tokens() -> None:
    text = " ".join(f"w{i}" for i in range(20))
    with pytest.raises(ValueError):
        chunk_text(text, tokenizer_for(text), max_tokens=5, overlap_tokens=5)


def test_no_chunk_exceeds_max_tokens() -> None:
    text = " ".join(f"w{i}" for i in range(100))
    tok = tokenizer_for(text)
    chunks = chunk_text(text, tok, max_tokens=10, overlap_tokens=2)
    for chunk in chunks:
        assert len(tok.encode(chunk)) <= 10
