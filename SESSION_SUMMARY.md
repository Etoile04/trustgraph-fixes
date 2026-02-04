# TrustFlow Pulsar Serialization Fix - Session Summary

## Session Date
2026-02-04

## Problem Statement
TrustFlow v2.0.0 store-doc-embeddings service was crashing with:
```
TypeError: 'NoneType' object is not iterable
```
When trying to iterate over `emb.vectors` which was `None`.

## Root Cause Identified
**NOT a Pulsar serialization issue** - The actual root cause was:
1. Chunks exceed the embedding model's context window (512 tokens for all-MiniLM-L6-v2)
2. Ollama returns error: "the input length exceeds the context length (status code: 400)"
3. Embeddings service sends error response
4. Document-embeddings service creates `ChunkEmbeddings(vectors=None)`
5. Store service crashes when iterating over `None`

## Solution Implemented
Added defensive handling in [trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py](trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py:58-75):

```python
# Skip chunks with None vectors
if emb.vectors is None:
    logger.warning(f"Chunk has no vectors (vectors=None), skipping...")
    continue

# Skip chunks with empty vectors
if len(emb.vectors) == 0:
    logger.warning(f"Chunk has empty vectors list (vectors=[]), skipping...")
    continue
```

## Files Modified
1. `/usr/local/lib/python3.13/site-packages/trustgraph/storage/doc_embeddings/qdrant/write.py` (running container)
2. `trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py` (source code)

## GitHub Repository Created
- **URL:** https://github.com/Etoile04/trustgraph-fixes
- **Location:** ~/ZCodeProject/trustgraph-fixes
- **Visibility:** Public
- **Commits:**
  - 1e08f57: Fix: Add defensive handling for None vectors
  - b93b2bb: Update setup script paths
  - 5d6c680: Fix path expansion with $HOME variable

## Documentation Created
- [TRUSTFLOW_PULSAR_FIX.md](TRUSTFLOW_PULSAR_FIX.md) - Complete fix documentation
- [TRUSTFLOW_MESSAGE_FORMAT_ROOT_CAUSE_ANALYSIS.md](TRUSTFLOW_MESSAGE_FORMAT_ROOT_CAUSE_ANALYSIS.md) - Root cause analysis
- [README.md](README.md) - Repository documentation

## Verification
- ✅ Service no longer crashes
- ✅ Warnings logged for skipped chunks
- ✅ Valid chunks processed successfully
- ✅ Document RAG queries working

## Recommendations for Production
1. **Switch to nomic-embed-text** (8192 token context vs 512)
2. **Reduce chunk size** to stay under 512 tokens for all-MiniLM-L6-v2
3. **Upstream contribution** - Submit fix to official TrustGraph repository

## Quick Apply Command
```bash
docker cp ~/ZCodeProject/trustgraph-fixes/trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py \
  deploy-store-doc-embeddings-1:/usr/local/lib/python3.13/site-packages/trustgraph/storage/doc_embeddings/qdrant/write.py
docker restart deploy-store-doc-embeddings-1
```

## Session Completion Status
✅ Complete - Fix applied, tested, documented, and published to GitHub
