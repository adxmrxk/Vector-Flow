"""Token-aware text chunking.

The embedding model silently truncates anything past its max sequence length
(sentence-transformers just drops the tail, with no warning) so a document
longer than ~512 tokens was losing data on every upsert with no indication
anything was wrong. This splits long text into overlapping, token-bounded
windows using the model's own tokenizer, so nothing gets dropped.
"""


def chunk_text(
    text: str,
    tokenizer: object,
    max_tokens: int,
    overlap_tokens: int = 50,
) -> list[str]:
    """Split text into overlapping windows of at most max_tokens tokens.

    Args:
        text: The text to split.
        tokenizer: A HuggingFace-style tokenizer exposing encode()/decode().
        max_tokens: Maximum tokens per chunk.
        overlap_tokens: Tokens shared between consecutive chunks, so a
            sentence spanning a chunk boundary still appears intact in at
            least one chunk.

    Returns:
        A list of text chunks. A single-element list containing the
        original text when it already fits in one chunk.
    """
    if max_tokens <= 0:
        raise ValueError("max_tokens must be positive")
    if overlap_tokens < 0:
        raise ValueError("overlap_tokens must be non-negative")

    token_ids = tokenizer.encode(text, add_special_tokens=False)
    if len(token_ids) <= max_tokens:
        return [text]

    if overlap_tokens >= max_tokens:
        raise ValueError("overlap_tokens must be smaller than max_tokens")

    chunks = []
    step = max_tokens - overlap_tokens
    start = 0
    while start < len(token_ids):
        window = token_ids[start : start + max_tokens]
        chunks.append(tokenizer.decode(window, skip_special_tokens=True))
        if start + max_tokens >= len(token_ids):
            break
        start += step
    return chunks
