"""Before/after benchmark for batch_upsert's embedding call pattern.

Run: .venv/Scripts/python.exe scripts/bench_batch_embedding.py
"""

import time

from app.config import Settings
from services.embedding import EmbeddingService

N_DOCS = 100

settings = Settings(model_cache_dir="./test_models")
svc = EmbeddingService(settings)
svc.load_model()

texts = [f"Document number {i} describing product SKU-{1000 + i} and its features." for i in range(N_DOCS)]

# "Before": one embed() call per document, as batch_upsert used to do.
start = time.perf_counter()
for t in texts:
    svc.embed([t])
before = time.perf_counter() - start

# "After": one embed() call for the whole batch, as the fix does.
start = time.perf_counter()
svc.embed(texts)
after = time.perf_counter() - start

print(f"Before (per-document embed calls): {before:.3f}s  ({N_DOCS / before:.1f} docs/sec)")
print(f"After  (single batched embed call): {after:.3f}s  ({N_DOCS / after:.1f} docs/sec)")
print(f"Speedup: {before / after:.2f}x")
