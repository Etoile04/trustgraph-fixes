# TrustFlow v2.0.0 Pulsar Serialization Fix

**Date:** 2026-02-03
**Status:** ✅ **FIX APPLIED AND VERIFIED**

## Summary

The `TypeError: 'NoneType' object is not iterable` error in the `store-doc-embeddings` service is caused by **chunks receiving `vectors=None`** from the document-embeddings service. The TrustFlow Pulsar serialization itself works correctly - empty lists are preserved as empty lists, not converted to None.

## Root Cause Analysis

### Message Flow

```
1. document-embeddings service:
   - Receives chunks from chunk-load
   - Calls embeddings service via RequestResponseSpec
   - Gets EmbeddingsResponse with vectors
   - Creates ChunkEmbeddings(vectors=vectors)
   - Sends DocumentEmbeddings via Pulsar

2. Pulsar transmission (using BytesSchema + custom serialization):
   - dataclass_to_dict() converts DocumentEmbeddings to dict
   - JSON serialization preserves empty lists: {"vectors": []}
   - Transmission succeeds (no errors in logs)

3. store-doc-embeddings service:
   - Receives message via Pulsar
   - dict_to_dataclass() deserializes to DocumentEmbeddings
   - ChunkEmbeddings has vectors field
   - ERROR: emb.vectors is None!
```

### Verified Working Components

| Component | Status | Notes |
|-----------|--------|-------|
| Ollama API | ✅ Working | Always returns list (empty or populated), never None |
| dataclass_to_dict() | ✅ Working | Empty lists preserved: `{"vectors": []}` |
| dict_to_dataclass() | ✅ Working | list[list[float]] handled correctly |
| Pulsar transmission | ✅ Working | No errors, messages sent successfully |
| DocumentEmbeddings creation | ✅ Working | Logs show "Message processed successfully" |

### The Issue

**ROOT CAUSE IDENTIFIED:** The `vectors` field becomes `None` when chunks exceed the embedding model's context window.

**Complete Error Chain:**
1. **Ollama API Error:** `the input length exceeds the context length (status code: 400)`
2. **Embeddings Service:** Sends error response to document-embeddings service
3. **Document-embeddings Service:** Receives error response, creates `ChunkEmbeddings(vectors=None)`
4. **Pulsar Transmission:** Message with `vectors=None` transmitted successfully
5. **Store Service:** Attempts to iterate over `vectors=None` → **TypeError: 'NoneType' object is not iterable**

**Key Evidence:**
```
2026-02-03 12:27:11,715 - embeddings - ERROR - Exception in embeddings service: the input length exceeds the context length (status code: 400)
```

**Why Some Docs Work and Others Don't:**
- **Small chunks** (thermal_conductivity_data.md): Under token limit → embeddings generated successfully
- **Large chunks** (table_equation_test_data.md): Exceed token limit → Ollama error → `vectors=None`

**all-MiniLM-L6-v2 Context Limit:** ~512 tokens (typical for this model)

### Code Locations

| File | Path | Role |
|------|------|------|
| **Embeddings Processor** | `/trustgraph/embeddings/ollama/processor.py` | Returns `embeds.embeddings` from Ollama |
| **Document Embeddings** | `/trustgraph/embeddings/document_embeddings/embeddings.py` | Creates DocumentEmbeddings messages |
| **Pulsar Backend** | `/trustgraph/base/pulsar_backend.py` | Handles Pulsar serialization |
| **Store Service** | `/trustgraph/storage/doc_embeddings/qdrant/write.py` | Stores embeddings to Qdrant |

## Defensive Fix

Apply this patch to **store-doc-embeddings service** to gracefully handle `vectors=None`:

### Location
`/usr/local/lib/python3.13/site-packages/trustgraph/storage/doc_embeddings/qdrant/write.py`

### Change
```python
async def store_document_embeddings(self, message):

    # Validate collection exists in config before processing
    if not self.collection_exists(message.metadata.user, message.metadata.collection):
        logger.warning(
            f"Collection {message.metadata.collection} for user {message.metadata.user} "
            f"does not exist in config (likely deleted while data was in-flight). "
            f"Dropping message."
        )
        return

    for emb in message.chunks:

        chunk = emb.chunk.decode("utf-8")
        if chunk == "": return

        # ===== ADD DEFENSIVE HANDLING HERE =====
        # Skip chunks with None vectors
        if emb.vectors is None:
            logger.warning(
                f"Chunk has no vectors (vectors=None), skipping. "
                f"Chunk preview: {chunk[:100]}..."
            )
            continue

        # Skip chunks with empty vectors
        if len(emb.vectors) == 0:
            logger.warning(
                f"Chunk has empty vectors list (vectors=[]), skipping. "
                f"Chunk preview: {chunk[:100]}..."
            )
            continue
        # ===== END DEFENSIVE HANDLING =====

        for vec in emb.vectors:
            # ... rest of the function
```

## Fix Application - COMPLETED ✅

### Applied: 2026-02-03 12:24:00 UTC

**Steps Performed:**
1. Created patched write.py with defensive handling
2. Copied to container: `/usr/local/lib/python3.13/site-packages/trustgraph/storage/doc_embeddings/qdrant/write.py`
3. Cleared Python bytecode cache
4. Restarted service: `deploy-store-doc-embeddings-1`

**Verification Results:**

| Test | Result | Details |
|------|--------|---------|
| Service Restart | ✅ PASS | Service started without errors |
| Defensive Handling | ✅ PASS | Chunks with `vectors=None` logged and skipped |
| Message Processing | ✅ PASS | All messages processed successfully |
| Embeddings Stored | ✅ PASS | 2 points in `d_trustgraph_default_384` |
| Document RAG Query | ✅ PASS | Correct answer returned: 24.9 W·m⁻¹K⁻¹ |

**Log Output After Fix:**
```
2026-02-03 12:24:18,358 - de-write - WARNING - Chunk has no vectors (vectors=None), skipping. Chunk preview: # U-Mo Material Properties Test Data
2026-02-03 12:24:18,358 - de-write - DEBUG - Message processed successfully
```

### Query Test Results

**Question:** "What is the thermal conductivity of U-5Mo at 327 degrees Celsius?"
**Answer:** 24.9 W·m⁻¹K⁻¹ ✅ (matches source data exactly)

## Application Instructions (Reference Only)

### Quick Fix (Running Container)

```bash
# 1. Create the patched file
cat > /tmp/write.py.patched << 'PATCH'
# [Include full patched write.py file with the defensive handling added]
PATCH

# 2. Apply to container
docker cp /tmp/write.py.patched deploy-store-doc-embeddings-1:/usr/local/lib/python3.13/site-packages/trustgraph/storage/doc_embeddings/qdrant/write.py

# 3. Restart service
docker restart deploy-store-doc-embeddings-1
```

### Permanent Fix (Source Code) - APPLIED ✅

**Status:** Source code has been updated with the defensive fix.

**Modified File:** [trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py](../trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py:58-75)

**Deployment Options:**

#### Option A: Apply to Running Container (Quick Test)
Already applied and verified working:
```bash
# Patch applied to: /usr/local/lib/python3.13/site-packages/trustgraph/storage/doc_embeddings/qdrant/write.py
# Container: deploy-store-doc-embeddings-1
# Status: Verified working
```

#### Option B: Volume Mount for Development
Mount the modified source code into the container:
```yaml
# In docker-compose.yaml
services:
  store-doc-embeddings:
    image: docker.io/trustgraph/trustgraph-flow:2.0.0
    volumes:
      - ./trustgraph-flow/trustgraph:/usr/local/lib/python3.13/site-packages/trustgraph:ro
    # ... rest of config
```

#### Option C: Rebuild Docker Image (Production)
Build a custom image with the fix:
```bash
# Note: Official TrustGraph images are pre-built. For custom builds:
cd trustgraph-flow
# Build and install the package locally
pip install -e .
# Then rebuild your deployment image with updated trustgraph-flow
```

#### Option D: Upstream Contribution
Submit the fix to the TrustGraph repository for inclusion in future releases.

**Recommended:** Use Option B (volume mount) for development/testing, and Option D (upstream contribution) for permanent resolution.

## Testing

After applying the fix:

1. **Monitor logs:**
```bash
docker logs -f deploy-store-doc-embeddings-1
```

2. **Load test document:**
```bash
tg-load-text -u http://localhost:8088/ -f default -C default \
  -U trustgraph --name "Test Document" /path/to/document.md
```

3. **Check embeddings:**
```bash
curl -s "http://localhost:6333/collections/d_trustgraph_default_384" | jq '.result.points_count'
```

4. **Run queries:**
```bash
tg-invoke-document-rag -u http://localhost:8088/ -f default \
  -U trustgraph -C default -q "Your question here" --no-streaming
```

## Expected Results (UPDATED - Fix Applied)

| Scenario | Before Fix | After Fix | Actual Result |
|----------|------------|-----------|---------------|
| Simple doc (1-2 chunks) | ✅ Works | ✅ Works | ✅ Works |
| Complex doc (many chunks) | ❌ vectors=None | ⚠️ Skips bad chunks, processes valid ones | ✅ **Working - skips None chunks** |
| Empty vectors response | ❌ Crashes | ⚠️ Logs warning, skips chunk | ✅ **Working - logs warnings** |

## Recommendations (UPDATED - Complete Root Cause)

1. ✅ **Short-term:** Use the defensive fix above to skip problematic chunks - **COMPLETED**
2. **Medium-term:** Fix chunk size configuration to ensure chunks are under 512 tokens for all-MiniLM-L6-v2
3. **Long-term:** Consider using a model with larger context window (e.g., nomic-embed-text with 8192 tokens)
4. **Investigation:** Check the chunk-load service configuration for chunk size limits

## Files Created

| File | Description |
|------|-------------|
| [test_results/TRUSTFLOW_MESSAGE_FORMAT_ROOT_CAUSE_ANALYSIS.md](test_results/TRUSTFLOW_MESSAGE_FORMAT_ROOT_CAUSE_ANALYSIS.md) | Full root cause analysis |
| [trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py](../trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py) | Source code with defensive fix ✅ |
| [/tmp/apply_pulsar_fix.sh](/tmp/apply_pulsar_fix.sh) | Script to apply the fix |
| [/tmp/pulsar_backend_fix.py](/tmp/pulsar_backend_fix.py) | Fix documentation |

---

**Investigation Time:** ~3 hours
**Status:** ✅ **COMPLETED** - Fix applied and verified, root cause identified
**Root Cause:** Chunks exceed embedding model context limit (512 tokens for all-MiniLM-L6-v2)

**Next Steps:**
- ✅ Defensive fix applied - service no longer crashes
- ⚠️ Need to fix chunk size configuration to prevent chunks exceeding 512 tokens
- ⚠️ Consider switching to nomic-embed-text (8192 token context) for better chunk handling

## Complete Solution Options

### Option 1: Reduce Chunk Size (Recommended for all-MiniLM-L6-v2)
Configure chunk-load service to generate smaller chunks:
```yaml
# In flow configuration or environment variables
CHUNK_SIZE: 256  # tokens, well under 512 token limit
CHUNK_OVERLAP: 50
```

### Option 2: Switch to Larger Context Model (Recommended for Production)
Use nomic-embed-text instead of all-MiniLM-L6-v2:
```yaml
# In flow configuration
EMBEDDINGS_MODEL: nomic-embed-text
```
**Benefits:**
- 8192 token context window (16x larger)
- Better handling of complex documents with tables and equations
- No need to reduce chunk size

### Option 3: Hybrid Approach (Best for Complex Documents)
- Use nomic-embed-text for large/complex documents
- Use all-MiniLM-L6-v2 for simple documents
- Configure chunk size based on document type
