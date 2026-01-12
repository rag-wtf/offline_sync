# Production-Grade On-Device RAG with Flutter Gemma
## Complete Implementation Guide v3.0

---

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Setup & Configuration](#setup--configuration)
3. [Core Components](#core-components)
4. [Implementation Guide](#implementation-guide)
5. [Advanced Features](#advanced-features)
6. [Performance Optimization](#performance-optimization)
7. [Security Best Practices](#security-best-practices)
8. [Testing Strategy](#testing-strategy)
9. [Troubleshooting](#troubleshooting)
10. [Production Checklist](#production-checklist)
11. [Future Enhancements (Phase 2)](#future-enhancements-phase-2)

---

## 🏗️ Architecture Overview

### The Dual-Model Challenge

On-device RAG requires two distinct AI operations:
- **Embedding Model**: Converts text to vectors
- **Generation Model**: Generates responses

**Critical Problem**: Loading both simultaneously requires 3-4GB GPU memory, causing crashes on standard devices.

### Embedding Strategy

This implementation uses **flutter_gemma's built-in embedding capabilities**:
- **Package**: `flutter_gemma` includes dedicated embedding model support
- **Models**: 
  - **EmbeddingGemma-300M**: 300M parameters, 768D embeddings, supports 256-2048 token sequences
  - **Gecko-110M**: 110M parameters, 768D embeddings, supports 64-512 token sequences
- **API**: Uses `FlutterGemma.installEmbedder()` and `FlutterGemma.getActiveEmbedder()`
- **Benefits**: 
  - Single package dependency
  - Dedicated embedding models optimized for RAG
  - CPU or GPU backend support
  - Native MediaPipe integration
  - Batch embedding generation

> **Note**: Embedding models are separate from generation models. You'll install both: one for embeddings (EmbeddingGemma/Gecko) and one for text generation (Gemma 2B-IT).

### Solution Architecture

```
┌─────────────────────────────────────────┐
│  Model Download Manager                 │
│  - Progressive download with resume     │
│  - Integrity verification (SHA-256)     │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Flutter Gemma Embedder                 │
│  - EmbeddingGemma-300M or Gecko-110M    │
│  - CPU/GPU backend support              │
│  - generateEmbedding() API              │
│  - 768-dimensional output               │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Vector Store (SQLite + FTS5)           │
│  - Binary BLOB format (70% smaller)     │
│  - Hybrid search (semantic + keyword)   │
│  - FTS5 fallback for unsupported devices│
│  - Sub-10ms retrieval                   │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Gemma 2B-IT (GPU)                      │
│  - Temperature: 0.0 (factual)           │
│  - Context window: 2048 tokens          │
│  - GPU-accelerated inference            │
│  - Lifecycle-aware management           │
└─────────────────────────────────────────┘

---

## 🚀 Setup & Configuration

### 1. Dependencies

**pubspec.yaml**
```yaml
name: offline_sync
description: On-device RAG with Flutter Gemma
version: 1.0.0+1
publish_to: none

environment:
  sdk: ^3.9.0
  flutter: ^3.35.0

dependencies:
  flutter:
    sdk: flutter
  # Core AI - handles both embeddings and generation
  flutter_gemma: ^0.12.0
  # Database
  sqflite: ^2.4.1
  # State management
  get_it: ^8.0.3
  injectable: ^2.5.0
  # Secure storage for encryption keys
  flutter_secure_storage: ^9.2.4
  # Localization
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2

dev_dependencies:
  build_runner: ^2.4.14
  flutter_test:
    sdk: flutter
  injectable_generator: ^2.6.3
  mocktail: ^1.0.4
  very_good_analysis: ^7.0.0

flutter:
  generate: true
  uses-material-design: true
  assets:
    - assets/models/
```

### 2. Android Configuration

**android/app/src/main/AndroidManifest.xml**
```xml
<manifest>
  <!-- GPU Delegate Support -->
  <uses-native-library 
    android:name="libOpenCL.so" 
    android:required="false" />
  <uses-native-library 
    android:name="libGLES_mali.so" 
    android:required="false" />
  <uses-native-library 
    android:name="libGLESv2.so" 
    android:required="false" />
  
  <!-- Permissions -->
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
  
  <application
    android:largeHeap="true"
    android:hardwareAccelerated="true"
    android:enableOnBackInvokedCallback="true">
  </application>
</manifest>
```

### 3. Embedding Model Setup

**Recommended Model: EmbeddingGemma-300M**

Download the required files:
- **Model**: [embeddinggemma-300M_seq1024_mixed-precision.tflite](https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq1024_mixed-precision.tflite) (~300MB)
- **Tokenizer**: [sentencepiece.model](https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model)

Alternative: **Gecko-110M** (lighter but less performant):
- **Model**: [gecko-embeddings-110m-fp32.tflite](https://huggingface.co/psuggate/gecko-embeddings/resolve/main/gecko-embeddings-110m-fp32.tflite) (~110MB)
- **Tokenizer**: Same sentencepiece.model

Place files in:
```
assets/
├── models/
│   ├── embeddinggemma-300m.tflite         # Embedding model
│   ├── sentencepiece.model                # Tokenizer (shared)
│   └── gemma-2b-it-gpu-int4.bin          # Generation model
```

### 4. Model Download Manager

```dart
class ModelDownloadManager {
  static const _chunkSize = 1024 * 1024; // 1MB chunks
  
  Future<void> downloadModel({
    required String url,
    required String targetPath,
    required String expectedHash,
    Function(double progress)? onProgress,
  }) async {
    final file = File(targetPath);
    final tempFile = File('$targetPath.tmp');
    
    // Resume support: check existing partial download
    var startByte = 0;
    if (await tempFile.exists()) {
      startByte = await tempFile.length();
    }
    
    final request = http.Request('GET', Uri.parse(url));
    if (startByte > 0) {
      request.headers['Range'] = 'bytes=$startByte-';
    }
    
    final response = await http.Client().send(request);
    final totalBytes = int.parse(
      response.headers['content-length'] ?? '0'
    ) + startByte;
    
    final sink = tempFile.openWrite(mode: FileMode.append);
    var receivedBytes = startByte;
    
    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      onProgress?.call(receivedBytes / totalBytes);
    }
    
    await sink.close();
    
    // Verify integrity
    final hash = await _computeSha256(tempFile);
    if (hash != expectedHash) {
      await tempFile.delete();
      throw ModelIntegrityException('Hash mismatch');
    }
    
    // Atomically move to final location
    await tempFile.rename(targetPath);
  }
  
  Future<String> _computeSha256(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
```

---

## 🔧 Core Components

### Component 1: Vector Store with FTS5 Fallback

```dart
class VectorStore {
  late Database _db;
  bool _hasFts5 = true;
  
  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vectors.db');
    
    _db = await openDatabase(path, version: 2, onCreate: _onCreate);
    
    // Check FTS5 support
    try {
      await _db.rawQuery("SELECT fts5(?)", ['test']);
    } catch (e) {
      _hasFts5 = false;
      debugPrint('FTS5 not available, using fallback search');
    }
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // Main vectors table
    await db.execute('''
      CREATE TABLE vectors (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        content TEXT NOT NULL,
        embedding BLOB NOT NULL,
        metadata TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (document_id) REFERENCES documents(id)
      )
    ''');
    
    // FTS5 virtual table for keyword search
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS vectors_fts 
      USING fts5(content, content=vectors, content_rowid=rowid)
    ''');
    
    // Triggers to keep FTS in sync
    await db.execute('''
      CREATE TRIGGER vectors_ai AFTER INSERT ON vectors BEGIN
        INSERT INTO vectors_fts(rowid, content) VALUES (new.rowid, new.content);
      END
    ''');
    
    await db.execute('''
      CREATE TRIGGER vectors_ad AFTER DELETE ON vectors BEGIN
        INSERT INTO vectors_fts(vectors_fts, rowid, content) 
        VALUES ('delete', old.rowid, old.content);
      END
    ''');
  }
  
  /// Hybrid search: semantic + keyword
  Future<List<SearchResult>> hybridSearch(
    String query,
    List<double> queryEmbedding, {
    int limit = 5,
    double semanticWeight = 0.7,
  }) async {
    // Semantic search
    final semanticResults = await _semanticSearch(queryEmbedding, limit: limit * 2);
    
    // Keyword search
    final keywordResults = _hasFts5
        ? await _fts5Search(query, limit: limit * 2)
        : await _fallbackKeywordSearch(query, limit: limit * 2);
    
    // Merge and re-rank
    return _mergeResults(
      semanticResults,
      keywordResults,
      semanticWeight: semanticWeight,
      limit: limit,
    );
  }
  
  Future<List<SearchResult>> _semanticSearch(
    List<double> embedding, {
    required int limit,
  }) async {
    final rows = await _db.query('vectors');
    
    final scored = rows.map((row) {
      final storedEmbedding = _decodeEmbedding(row['embedding'] as Uint8List);
      final score = _cosineSimilarity(embedding, storedEmbedding);
      return SearchResult(
        id: row['id'] as String,
        content: row['content'] as String,
        score: score,
        metadata: jsonDecode(row['metadata'] as String? ?? '{}'),
      );
    }).toList();
    
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }
  
  Future<List<SearchResult>> _fts5Search(String query, {required int limit}) async {
    final results = await _db.rawQuery('''
      SELECT v.*, bm25(vectors_fts) as score
      FROM vectors_fts
      JOIN vectors v ON vectors_fts.rowid = v.rowid
      WHERE vectors_fts MATCH ?
      ORDER BY score
      LIMIT ?
    ''', [_sanitizeFtsQuery(query), limit]);
    
    return results.map((row) => SearchResult(
      id: row['id'] as String,
      content: row['content'] as String,
      score: -(row['score'] as double), // BM25 returns negative scores
      metadata: jsonDecode(row['metadata'] as String? ?? '{}'),
    )).toList();
  }
  
  Future<List<SearchResult>> _fallbackKeywordSearch(
    String query, {
    required int limit,
  }) async {
    // Simple LIKE-based fallback for devices without FTS5
    final words = query.toLowerCase().split(RegExp(r'\s+'));
    final conditions = words.map((w) => "LOWER(content) LIKE '%$w%'").join(' OR ');
    
    final results = await _db.rawQuery('''
      SELECT * FROM vectors WHERE $conditions LIMIT ?
    ''', [limit]);
    
    return results.map((row) => SearchResult(
      id: row['id'] as String,
      content: row['content'] as String,
      score: 0.5, // Fixed score for fallback
      metadata: jsonDecode(row['metadata'] as String? ?? '{}'),
    )).toList();
  }
  
  double _cosineSimilarity(List<double> a, List<double> b) {
    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
  
  String _sanitizeFtsQuery(String query) {
    // Escape special FTS5 characters
    return query
        .replaceAll('"', '""')
        .replaceAll('*', '')
        .replaceAll('-', ' ');
  }
}
```

### Component 2: Secure RAG Manager

```dart
class SecureRAGManager with WidgetsBindingObserver {
  static final instance = SecureRAGManager._();
  SecureRAGManager._();
  
  final _mutex = Mutex();
  final _vectorStore = VectorStore();
  EmbeddingModel? _embeddingModel;
  InferenceModel? _generationModel;
  final _queryCache = SmartQueryCache();
  final _auditLog = AuditLogger();
  RAGState _state = RAGState.uninitialized;
  
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    
    await _vectorStore.initialize();
    
    // Initialize embedding model
    await FlutterGemma.installEmbedder()
      .modelFromAsset('assets/models/embeddinggemma-300m.tflite')
      .tokenizerFromAsset('assets/models/sentencepiece.model')
      .install();
    
    _embeddingModel = await FlutterGemma.getActiveEmbedder(
      preferredBackend: PreferredBackend.cpu, // Use CPU to avoid GPU contention
    );
    
    _state = RAGState.ready;
  }
  
  Future<RAGResult> askWithRAG(
    String query, {
    bool includeMetrics = false,
    bool bypassCache = false,
  }) async {
    // Input validation & prompt injection defense
    final sanitizedQuery = _sanitizeInput(query);
    if (!_isValidQuery(sanitizedQuery)) {
      throw RAGException('Invalid query detected');
    }
    
    // Check cache
    if (!bypassCache) {
      final cached = _queryCache.get(sanitizedQuery);
      if (cached != null) return cached;
    }
    
    final stopwatch = Stopwatch()..start();
    
    // Generate embedding using flutter_gemma
    final embedding = await _generateEmbedding(sanitizedQuery);
    final embeddingTime = stopwatch.elapsed;
    
    // Search
    final results = await _vectorStore.hybridSearch(
      sanitizedQuery,
      embedding,
      limit: 3,
    );
    final searchTime = stopwatch.elapsed - embeddingTime;
    
    // Build context
    final context = _buildContext(results);
    
    // Generate response
    await _ensureGenerationModel();
    final response = await _generate(sanitizedQuery, context);
    final generationTime = stopwatch.elapsed - searchTime - embeddingTime;
    
    // Audit log
    await _auditLog.logQuery(sanitizedQuery, results.length);
    
    final result = RAGResult(
      response: response,
      sources: results,
      metrics: includeMetrics ? RAGMetrics(
        embeddingTime: embeddingTime,
        searchTime: searchTime,
        generationTime: generationTime,
        chunksRetrieved: results.length,
      ) : null,
    );
    
    _queryCache.set(sanitizedQuery, result);
    return result;
  }
  
  /// Generate embedding using flutter_gemma's EmbeddingModel
  Future<List<double>> _generateEmbedding(String text) async {
    if (_embeddingModel == null) {
      throw RAGException('Embedding model not initialized');
    }
    
    // Use the generateEmbedding method from EmbeddingModel
    final embedding = await _embeddingModel!.generateEmbedding(text);
    return embedding;
  }
  
  String _sanitizeInput(String input) {
    // Remove potential prompt injection patterns
    var sanitized = input;
    
    final injectionPatterns = [
      RegExp(r'<\s*start_of_turn\s*>', caseSensitive: false),
      RegExp(r'<\s*end_of_turn\s*>', caseSensitive: false),
      RegExp(r'ignore\s+previous\s+instructions?', caseSensitive: false),
      RegExp(r'system\s*:', caseSensitive: false),
    ];
    
    for (final pattern in injectionPatterns) {
      sanitized = sanitized.replaceAll(pattern, '');
    }
    
    return sanitized.trim();
  }
  
  bool _isValidQuery(String query) {
    if (query.isEmpty || query.length > 2000) return false;
    if (query.split(RegExp(r'\s+')).length > 200) return false;
    return true;
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _disposeGenerationModel();
    }
  }
  
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeGenerationModel();
    _vectorStore.close();
  }
}
```

---

## 🔒 Security Best Practices

### 1. Secure Key Management

```dart
class SecureKeyManager {
  static final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  
  static Future<String> getOrCreateEncryptionKey() async {
    const keyName = 'vector_db_encryption_key';
    
    var key = await _storage.read(key: keyName);
    if (key == null) {
      // Generate cryptographically secure key
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      key = base64Encode(bytes);
      await _storage.write(key: keyName, value: key);
    }
    
    return key;
  }
  
  static Future<void> rotateKey() async {
    // Implement key rotation logic
  }
}

// Usage with encrypted database
Future<Database> openSecureVectorStore() async {
  final key = await SecureKeyManager.getOrCreateEncryptionKey();
  final dbPath = await getDatabasesPath();
  
  return await openDatabase(
    join(dbPath, 'secure_vectors.db'),
    password: key,
    version: 1,
  );
}
```

### 2. Enhanced PII Detection

```dart
class EnhancedPIIDetector {
  static final patterns = {
    'email': RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
    'ssn': RegExp(r'\b\d{3}-\d{2}-\d{4}\b'),
    'phone': RegExp(r'\b\d{3}[-.]?\d{3}[-.]?\d{4}\b'),
    'creditCard': RegExp(r'\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b'),
    'ipAddress': RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
    // Additional patterns
    'passport': RegExp(r'\b[A-Z]{1,2}\d{6,9}\b'),
    'bankAccount': RegExp(r'\b\d{8,17}\b'),
    'apiKey': RegExp(r'\b(sk|pk|api)[_-][a-zA-Z0-9]{20,}\b'),
    'jwt': RegExp(r'\beyJ[A-Za-z0-9-_]+\.eyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\b'),
    'awsKey': RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
  };
  
  static String redact(String text, {bool logDetections = true}) {
    var sanitized = text;
    final detections = <String, int>{};
    
    patterns.forEach((type, pattern) {
      final matches = pattern.allMatches(sanitized);
      if (matches.isNotEmpty) {
        detections[type] = matches.length;
        sanitized = sanitized.replaceAll(
          pattern, 
          '[${type.toUpperCase()}_REDACTED]'
        );
      }
    });
    
    if (logDetections && detections.isNotEmpty) {
      debugPrint('PII detected and redacted: $detections');
    }
    
    return sanitized;
  }
}
```

### 3. Audit Logging

```dart
class AuditLogger {
  late Database _db;
  
  Future<void> initialize(Database db) async {
    _db = db;
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        action TEXT NOT NULL,
        details TEXT,
        user_id TEXT
      )
    ''');
  }
  
  Future<void> logQuery(String query, int resultsCount) async {
    await _db.insert('audit_log', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'action': 'rag_query',
      'details': jsonEncode({
        'query_length': query.length,
        'results_count': resultsCount,
      }),
    });
  }
  
  Future<void> logSensitiveAccess(String operation, String entityId) async {
    await _db.insert('audit_log', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'action': 'sensitive_access',
      'details': jsonEncode({
        'operation': operation,
        'entity_id': entityId,
      }),
    });
  }
}
```

---

## 🧪 Testing Strategy

### 1. Unit Tests

```dart
// test/core/chunker_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/core/content_chunker.dart';

void main() {
  group('ContentChunker', () {
    test('respects sentence boundaries', () {
      const text = 'First sentence. Second sentence. Third sentence.';
      final chunks = ContentChunker.split(text, chunkSize: 20);
      
      expect(chunks, isNotEmpty);
      expect(chunks.first, endsWith('.'));
    });
    
    test('preserves code blocks', () {
      const text = '''
Some text before.
```dart
void main() {
  print('Hello');
}
```
Some text after.
''';
      final chunks = ContentChunker.split(text, chunkSize: 50);
      
      // Code block should not be split
      final codeChunk = chunks.firstWhere((c) => c.contains('```dart'));
      expect(codeChunk, contains("print('Hello')"));
    });
    
    test('handles empty input', () {
      final chunks = ContentChunker.split('', chunkSize: 100);
      expect(chunks, isEmpty);
    });
  });
}

// test/security/pii_detector_test.dart
void main() {
  group('EnhancedPIIDetector', () {
    test('detects and redacts email addresses', () {
      const text = 'Contact me at john.doe@example.com for info.';
      final redacted = EnhancedPIIDetector.redact(text);
      
      expect(redacted, contains('[EMAIL_REDACTED]'));
      expect(redacted, isNot(contains('john.doe@example.com')));
    });
    
    test('detects API keys', () {
      const text = 'Use key';
      final redacted = EnhancedPIIDetector.redact(text);
      
      expect(redacted, contains('[APIKEY_REDACTED]'));
    });
    
    test('handles text without PII', () {
      const text = 'This is a normal sentence.';
      final redacted = EnhancedPIIDetector.redact(text);
      
      expect(redacted, equals(text));
    });
  });
}
```

### 2. Integration Tests

```dart
// integration_test/rag_pipeline_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('RAG Pipeline E2E', () {
    late SecureRAGManager ragManager;
    
    setUpAll(() async {
      ragManager = SecureRAGManager.instance;
      await ragManager.initialize();
    });
    
    tearDownAll(() {
      ragManager.dispose();
    });
    
    testWidgets('ingests document and retrieves relevant chunks', 
      (tester) async {
      // Ingest test document
      await ragManager.ingestDocument(
        'test_doc_1',
        'Flutter is a UI toolkit for building natively compiled apps.',
      );
      
      // Query
      final result = await ragManager.askWithRAG('What is Flutter?');
      
      expect(result.response, isNotEmpty);
      expect(result.sources, isNotEmpty);
      expect(result.sources.first.content, contains('Flutter'));
    });
    
    testWidgets('handles empty results gracefully', (tester) async {
      final result = await ragManager.askWithRAG(
        'xyzzy_nonexistent_topic_12345'
      );
      
      expect(result.response, isNotEmpty);
      // Should indicate no relevant information found
    });
  });
}
```

### 3. Golden Response Tests

```dart
// test/golden/hallucination_test.dart
void main() {
  group('Hallucination Detection', () {
    test('does not hallucinate beyond context', () async {
      const context = 'The app supports iOS and Android.';
      const query = 'Does the app support Windows?';
      
      final result = await ragManager.askWithRAG(query);
      
      // Should NOT claim Windows support
      expect(
        result.response.toLowerCase(), 
        isNot(contains('yes')),
      );
      expect(
        result.response.toLowerCase(),
        anyOf([
          contains("don't have"),
          contains('not mentioned'),
          contains('no information'),
        ]),
      );
    });
  });
}
```

### 4. Performance Benchmarks

```dart
// test/performance/benchmark_test.dart
void main() {
  group('Performance Benchmarks', () {
    test('embedding generation < 100ms', () async {
      final stopwatch = Stopwatch()..start();
      
      for (var i = 0; i < 10; i++) {
        await embedder.embed('Sample query text for benchmarking');
      }
      
      final avgMs = stopwatch.elapsedMilliseconds / 10;
      expect(avgMs, lessThan(100));
    });
    
    test('vector search < 50ms for 1000 documents', () async {
      // Setup: Insert 1000 test vectors
      await _insertTestVectors(1000);
      
      final stopwatch = Stopwatch()..start();
      await vectorStore.hybridSearch(
        'test query',
        testEmbedding,
        limit: 5,
      );
      
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });
}
```

---

## ⚡ Performance Optimization

### Smart Query Cache

```dart
class SmartQueryCache {
  final _cache = <String, ({RAGResult result, DateTime timestamp})>{};
  static const _maxSize = 100;
  static const _ttl = Duration(hours: 1);
  
  RAGResult? get(String query) {
    final normalized = _normalize(query);
    final entry = _cache[normalized];
    
    if (entry == null) return null;
    
    // Check TTL
    if (DateTime.now().difference(entry.timestamp) > _ttl) {
      _cache.remove(normalized);
      return null;
    }
    
    return entry.result;
  }
  
  void set(String query, RAGResult result) {
    final normalized = _normalize(query);
    
    // Evict oldest if at capacity
    if (_cache.length >= _maxSize) {
      final oldest = _cache.entries
          .reduce((a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b);
      _cache.remove(oldest.key);
    }
    
    _cache[normalized] = (result: result, timestamp: DateTime.now());
  }
  
  /// Fuzzy cache lookup using semantic similarity
  Future<RAGResult?> getSimilar(
    String query, 
    List<double> queryEmbedding, {
    double threshold = 0.95,
  }) async {
    for (final entry in _cache.entries) {
      // This requires storing embeddings with cache entries
      // Simplified version - implement as needed
    }
    return null;
  }
  
  String _normalize(String query) {
    return query.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}
```

### Battery & Thermal Awareness

```dart
class ResourceAwareLoader {
  Future<bool> shouldPreloadModel() async {
    // Check battery level
    final battery = Battery();
    final level = await battery.batteryLevel;
    if (level < 20) return false;
    
    // Check battery state
    final state = await battery.batteryState;
    if (state == BatteryState.discharging && level < 50) return false;
    
    // Check thermal state (Android only)
    if (Platform.isAndroid) {
      final thermalStatus = await _getThermalStatus();
      if (thermalStatus >= ThermalStatus.moderate) return false;
    }
    
    return true;
  }
}
```

---

## ✅ Production Checklist

### Pre-Launch

- [ ] Test on minimum 3 physical devices (low/mid/high end)
- [ ] Test on devices with 4GB, 6GB, 8GB RAM
- [ ] Verify GPU delegate works on target devices
- [ ] Test CPU fallback on unsupported devices
- [ ] Measure cold start time (<3s recommended)
- [ ] Measure query response time (<2s recommended)
- [ ] Test background/foreground transitions
- [ ] Verify memory cleanup on app kill
- [ ] Test with 1000+ document corpus
- [ ] Validate PII detection accuracy
- [ ] Test prompt injection defense
- [ ] Implement analytics/error reporting
- [ ] Run all unit and integration tests
- [ ] Audit security configurations

### Performance Targets

| Metric | Target | Critical |
|--------|--------|----------|
| Cold Start | <3s | <5s |
| Query Response | <2s | <5s |
| Ingestion (per 1000 words) | <5s | <10s |
| Memory Usage (Peak) | <2.5GB | <3.5GB |
| Embedding Generation | <150ms | <300ms |

---

## 🚀 Future Enhancements (Phase 2)

> **Note**: The following features are planned for Phase 2 implementation and are not part of the current release.

### Offline Sync Strategy

#### Overview

Implement multi-device synchronization with conflict resolution for enterprise and collaborative use cases.

#### Key Components

##### 1. Sync Queue Architecture

```dart
/// Sync queue entry for offline operations
class SyncQueueEntry {
  final String id;
  final String operation; // 'create', 'update', 'delete'
  final String entityType;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int retryCount;
  final SyncStatus status;
  
  SyncQueueEntry({
    required this.id,
    required this.operation,
    required this.entityType,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
    this.status = SyncStatus.pending,
  });
}

enum SyncStatus { pending, inProgress, failed, completed }
```

##### 2. Conflict Resolution

**Last-Write-Wins (LWW):**
```dart
class ConflictResolver {
  static Map<String, dynamic> resolve(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final localTime = DateTime.parse(local['updatedAt'] as String);
    final remoteTime = DateTime.parse(remote['updatedAt'] as String);
    
    return remoteTime.isAfter(localTime) ? remote : local;
  }
}
```

**CRDT-based** (for advanced scenarios):
- Operational transformation for text documents
- Vector clock for causality tracking
- Field-level merge strategies

##### 3. Retry Logic with Exponential Backoff

```dart
class SyncEngine {
  static const _maxRetries = 5;
  static const _baseDelay = Duration(seconds: 1);
  
  Future<void> processQueue() async {
    for (final entry in pendingEntries) {
      try {
        await _syncEntry(entry);
      } catch (e) {
        if (entry.retryCount >= _maxRetries) {
          await _handlePermanentFailure(entry);
        } else {
          final delay = _baseDelay * pow(2, entry.retryCount);
          await Future.delayed(delay);
        }
      }
    }
  }
}
```

##### 4. Delta Sync for Large Corpora

```dart
class DeltaSyncManager {
  Future<void> syncDocuments() async {
    final lastSyncTime = await _getLastSyncTimestamp();
    final changes = await _fetchChanges(since: lastSyncTime);
    
    for (final change in changes) {
      switch (change.type) {
        case ChangeType.created:
        case ChangeType.updated:
          await _upsertDocument(change.document);
        case ChangeType.deleted:
          await _deleteDocument(change.documentId);
      }
    }
  }
}
```

#### Additional Dependencies for Phase 2

```yaml
dependencies:
  # Network connectivity monitoring
  connectivity_plus: ^6.1.3
  # Encrypted database (optional)
  sqflite_sqlcipher: ^3.1.0
  # HTTP client for sync
  dio: ^5.7.0
```

#### Implementation Considerations

- **Backend API**: RESTful or GraphQL endpoint for sync operations
- **Authentication**: OAuth 2.0 / JWT token management
- **Offline Queue Persistence**: SQLite-based queue storage
- **Network Monitoring**: Automatic sync trigger on connectivity restoration
- **Conflict UI**: User-facing conflict resolution dialog

---

*Last Updated: January 2026*  
*Version: 3.0*  
*License: MIT*
