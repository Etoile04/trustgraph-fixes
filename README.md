# trustgraph-fixes

This repository contains fixes and improvements for TrustGraph, specifically addressing the Pulsar serialization issue with `list[list[float]]` fields.

## Fix: Defensive Handling for None Vectors in Document Embeddings

### Problem
The store-doc-embeddings service was crashing with `TypeError: 'NoneType' object is not iterable` when processing chunks that exceeded the embedding model's context window (512 tokens for all-MiniLM-L6-v2).

### Root Cause
When Ollama encounters a chunk that exceeds its context window, it returns an error: `"the input length exceeds the context length (status code: 400)"`. The embeddings service then creates a response with `vectors=None`, which causes the store service to crash when attempting to iterate over the vectors.

### Solution
Added defensive handling in the store service to gracefully skip chunks with `None` or empty vectors:
- Check for `vectors=None` and log a warning before skipping
- Check for `vectors=[]` and log a warning before skipping
- Continue processing remaining valid chunks

### Files Modified
- `trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py` (lines 58-75)

### Documentation
- [TRUSTFLOW_PULSAR_FIX.md](TRUSTFLOW_PULSAR_FIX.md) - Complete fix documentation
- [TRUSTFLOW_MESSAGE_FORMAT_ROOT_CAUSE_ANALYSIS.md](TRUSTFLOW_MESSAGE_FORMAT_ROOT_CAUSE_ANALYSIS.md) - Root cause analysis

### Application

**Option 1: Apply to Running Container**
```bash
docker cp trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py \
  deploy-store-doc-embeddings-1:/usr/local/lib/python3.13/site-packages/trustgraph/storage/doc_embeddings/qdrant/write.py
docker restart deploy-store-doc-embeddings-1
```

**Option 2: Volume Mount (Development)**
```yaml
services:
  store-doc-embeddings:
    volumes:
      - ./trustgraph-flow/trustgraph:/usr/local/lib/python3.13/site-packages/trustgraph:ro
```

### Verification
After applying the fix:
```bash
# Monitor logs for warnings (instead of errors)
docker logs -f deploy-store-doc-embeddings-1 | grep WARNING

# Load a test document
tg-load-text -u http://localhost:8088/ -f default -C default \
  -U trustgraph --name "Test" /path/to/document.md

# Verify embeddings stored
curl -s "http://localhost:6333/collections/d_trustgraph_default_384" | jq '.result.points_count'
```

### Long-Term Recommendations
1. **Switch to nomic-embed-text** - Has 8192 token context vs 512 for all-MiniLM-L6-v2
2. **Reduce chunk size** - Configure chunks under 512 tokens for all-MiniLM-L6-v2
3. **Upstream contribution** - Submit this fix to the official TrustGraph repository

## License
This fix maintains compatibility with the original TrustGraph license.
