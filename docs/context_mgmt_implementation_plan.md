# Fix Token Limit Error - Final Implementation Plan

## Problem
`current_step(802) + input_size(406) > maxTokens(1024)` - prompt exceeds limit.

---

## Context Engineering Strategy

### Priority Order (Most → Least Important)
1. **Current query** - never truncate
2. **Most recent exchange** - critical for coherence  
3. **Most relevant RAG chunks** - sorted by score
4. **Older history** - compress/drop oldest first

### Smart Truncation Rules
- Truncate at sentence boundaries, not mid-word
- Keep oldest history message start (topic anchor)
- Summarize dropped context: `"[Previous: discussed X, Y]"`

---

## Implementation

### 1. Model Token Limits
#### [MODIFY] [model_config.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/model_config.dart)

| Model | maxTokens |
|-------|-----------|
| Gemma 270M | 1024 |
| Gemma 1B | 2048 |
| Gemma 3n E2B | 4096 |
| Gemma 3n E4B | 8192 |

---

### 2. Context Budget Allocation
#### [MODIFY] [rag_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/rag_service.dart)

```dart
/// Allocate token budget with smart prioritization
TokenBudget _allocateBudget(int maxTokens, int queryTokens) {
  final available = maxTokens - queryTokens - 256; // output reserve
  return TokenBudget(
    contextTokens: (available * 0.55).floor(),  // RAG context
    historyTokens: (available * 0.35).floor(),  // conversation
    systemTokens: (available * 0.10).floor(),   // prompt template
  );
}
```

---

### 3. Smart History Management
#### [MODIFY] [rag_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/rag_service.dart)

```dart
String _buildHistoryWithBudget(List<String> history, int tokenBudget) {
  if (history.isEmpty) return '';
  
  // Always keep most recent exchange
  final recent = history.reversed.take(2).toList().reversed;
  var tokens = _estimateTokens(recent.join('\n'));
  
  // Add older messages if budget allows (oldest dropped first)
  final older = history.reversed.skip(2).toList();
  final includedOlder = <String>[];
  
  for (final msg in older) {
    final msgTokens = _estimateTokens(msg);
    if (tokens + msgTokens <= tokenBudget) {
      includedOlder.add(msg);
      tokens += msgTokens;
    } else break; // Drop remaining oldest
  }
  
  // Build: [older...] + [recent]
  return [...includedOlder.reversed, ...recent].join('\n');
}
```

---

### 4. Relevance-Prioritized Context
#### [MODIFY] [rag_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/rag_service.dart)

```dart
String _buildContextWithBudget(List<SearchResult> results, int tokenBudget) {
  // Results already sorted by relevance score
  final chunks = <String>[];
  var tokens = 0;
  
  for (final result in results) {
    final chunkTokens = _estimateTokens(result.content);
    if (tokens + chunkTokens <= tokenBudget) {
      chunks.add('[Source ${chunks.length + 1}]: ${result.content}');
      tokens += chunkTokens;
    } else break; // Skip lower-relevance chunks
  }
  
  return chunks.isEmpty ? 'No relevant context.' : chunks.join('\n\n');
}
```

---

### 5. User Settings
#### [MODIFY] [rag_settings_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/rag_settings_service.dart)

- `searchTopK`: 1-5 (default: 2)
- `maxHistoryMessages`: 0-5 (default: 2)

---

### 6. Progressive Retry (Oldest First)
#### [MODIFY] [rag_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/rag_service.dart)

On `OUT_OF_RANGE`:
1. Drop oldest 50% of history (keep recent)
2. Drop lowest-scoring 50% of context
3. Retry with reduced prompt
4. If still fails: keep only last exchange + top context chunk

---

### 7. Session Recovery
On "create a new Session" error:
- Invalidate cached `_inferenceModel`
- Next call creates fresh session automatically

---

## Verification
```bash
cd "/media/limcheekin/My Passport/ws/rag.wtf/offline_sync"
flutter analyze && flutter test
```
