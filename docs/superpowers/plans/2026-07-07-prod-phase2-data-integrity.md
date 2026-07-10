# Phase 2 — Data Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.
> Master plan: [2026-07-07-production-readiness-remediation.md](2026-07-07-production-readiness-remediation.md).

**Goal:** Eliminate silent data corruption and make the SQLite schema migratable **before first ship** (retrofitting a migration path after release is much harder).

**Architecture:** `VectorStore` owns the SQLite schema; stamp `PRAGMA user_version` now so future changes are detectable. `DocumentParserService` owns byte→text decoding (the DOCX bug). `Document.fromJson` and the similarity isolate get defensive parsing. Model integrity and secure-storage hardening are config/decision tasks.

**Tech Stack:** sqlite3 (common API), Dart `utf8`/`convert`, `crypto` (already a dependency), mocktail tests.

## Global Constraints

See master plan. Phase-specific:
- **H-13 must land before any release** — stamping `user_version = 1` on an already-shipped install is indistinguishable from a fresh v1, so migrations can never be detected retroactively.
- Model checksum verification (M-1) must **fail closed**: a mismatch aborts activation, never loads the file.

---

## Task 1: Stamp and gate schema version with PRAGMA user_version (H-13)

**Shape:** Logic (real test against in-memory sqlite).

**Files:**
- Modify: `lib/services/vector_store.dart` (`initialize()` `:73-88`, `_onCreate()` `:90-170`)
- Test: `test/services/vector_store_test.dart`

**Why:** Schema is created via `CREATE TABLE IF NOT EXISTS` only; there is no `PRAGMA user_version` and no upgrade path anywhere in `lib/`. Any future schema change silently no-ops on existing installs → `no such column` crashes with no forward path.

**Interfaces:**
- Produces: `static const int schemaVersion = 1;` on `VectorStore`; a private `void _migrate(int from)` invoked from `initialize()`.

- [ ] **Step 1: Write the failing test**

Add to `test/services/vector_store_test.dart` inside `group('VectorStore Tests', …)`:
```dart
test('stamps user_version to current schemaVersion on init', () {
  final version = vectorStore.db!
      .select('PRAGMA user_version')
      .first
      .values
      .first as int;
  expect(version, VectorStore.schemaVersion);
  expect(VectorStore.schemaVersion, greaterThanOrEqualTo(1));
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/services/vector_store_test.dart`
Expected: FAIL — `user_version` is `0` (default) and `VectorStore.schemaVersion` is undefined (compile error until Step 3).

- [ ] **Step 3: Implement version stamping + migration hook**

In `lib/services/vector_store.dart`, add the constant to the `VectorStore` class (near `:66`):
```dart
  /// Current on-disk schema version. Bump when the schema changes and add a
  /// matching branch in [_migrate].
  static const int schemaVersion = 1;
```
In `initialize()` (`:79-80`), after `_onCreate();`, add:
```dart
    final currentVersion =
        _db!.select('PRAGMA user_version').first.values.first as int;
    if (currentVersion < schemaVersion) {
      _migrate(currentVersion);
      _db!.execute('PRAGMA user_version = $schemaVersion');
    }
```
Add the method near `_onCreate` (`:170`):
```dart
  /// Applies ordered, gated migrations from [fromVersion] to [schemaVersion].
  /// v0 → v1 is a no-op: v1 is the baseline stamped for the first release so
  /// that future upgrades are detectable. Add `if (fromVersion < N) { … }`
  /// blocks in ascending order for later schema changes.
  void _migrate(int fromVersion) {
    // v0 -> v1: baseline. Tables already created by _onCreate().
    // Future: if (fromVersion < 2) { _db!.execute('ALTER TABLE ...'); }
  }
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/services/vector_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/vector_store.dart test/services/vector_store_test.dart
git commit -m "feat(db): stamp PRAGMA user_version=1 and add gated migration hook"
```

---

## Task 2: Fix DOCX UTF-8 decoding (C-4)

**Shape:** Logic (real test with a hand-built DOCX zip).

**Files:**
- Modify: `lib/services/document_parser_service.dart:137`
- Test: `test/services/document_parser_service_test.dart`

**Why:** `String.fromCharCodes(documentEntry.content as List<int>)` treats UTF-8 bytes as raw code units; `word/document.xml` is UTF-8, so accented/CJK/emoji/smart-quote content is mangled before chunking and embedding. Markdown/plaintext already use `utf8.decode(..., allowMalformed: true)` (`:86`) — DOCX must too.

- [ ] **Step 1: Write the failing test**

Add to `test/services/document_parser_service_test.dart` inside `group('parseDocument -', …)` (imports `dart:convert`, `dart:typed_data`, `package:archive/archive.dart`):
```dart
test('parses non-ASCII DOCX text without corruption', () async {
  const text = 'Café — 日本語 — 😀 — “smart quotes”';
  final documentXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:body></w:document>';
  final archive = Archive()
    ..addFile(ArchiveFile(
      'word/document.xml',
      utf8.encode(documentXml).length,
      utf8.encode(documentXml),
    ));
  final docxBytes = Uint8List.fromList(ZipEncoder().encode(archive));

  final parsed = await service.parseDocumentFromBytes(docxBytes, 'sample.docx');

  expect(parsed.content, contains('Café'));
  expect(parsed.content, contains('日本語'));
  expect(parsed.content, contains('😀'));
  expect(parsed.content, contains('“smart quotes”'));
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/services/document_parser_service_test.dart`
Expected: FAIL — the accented/CJK/emoji assertions fail (mojibake) with the current `String.fromCharCodes`.

- [ ] **Step 3: Implement the fix**

In `lib/services/document_parser_service.dart:137`, replace:
```dart
      final content = String.fromCharCodes(documentEntry.content as List<int>);
```
with:
```dart
      final content = utf8.decode(
        documentEntry.content as List<int>,
        allowMalformed: true,
      );
```
(`dart:convert` is already imported at `:1`.)

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/services/document_parser_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/document_parser_service.dart test/services/document_parser_service_test.dart
git commit -m "fix(parser): decode DOCX document.xml as UTF-8"
```

---

## Task 3: Guard the similarity loop against mismatched embedding dimensions (M-9)

**Shape:** Logic (real test against in-memory sqlite).

**Files:**
- Modify: `lib/services/vector_store.dart` (`_calculateSimilarities` `:554-589`)
- Test: `test/services/vector_store_test.dart`

**Why:** `_calculateSimilarities` iterates `i < queryEmbedding.length` indexing `storedEmbedding[i]` with no length check (`:568-571`). Rows embedded by a different model (different dim) throw `RangeError` and break **all** search after a model switch.

- [ ] **Step 1: Write the failing test**

Add to `test/services/vector_store_test.dart`:
```dart
test('semantic search skips rows with mismatched embedding dimension', () async {
  vectorStore.insertEmbedding(
    id: 'ok', documentId: 'd', content: 'good row', embedding: [0.1, 0.2, 0.3]);
  vectorStore.insertEmbedding(
    id: 'bad', documentId: 'd', content: 'wrong dim', embedding: [0.1, 0.2]);

  // semanticWeight 1.0 forces the semantic path over all rows.
  final results = await vectorStore.hybridSearch(
    'query', [0.1, 0.2, 0.3], limit: 5, semanticWeight: 1);

  expect(results.map((r) => r.id), contains('ok'));
  expect(results.map((r) => r.id), isNot(contains('bad')));
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/services/vector_store_test.dart`
Expected: FAIL — a `RangeError` propagates out of the `compute` isolate (or the test errors), because `storedEmbedding[2]` is out of range for the 2-dim row.

- [ ] **Step 3: Implement the guard**

In `lib/services/vector_store.dart`, inside `_calculateSimilarities` (`:559`), change the `.map` body so it skips mismatched rows. Replace the `data.map((item) { … }).toList();` block (`:559-584`) with a length-checked version:
```dart
  final scored = <SearchResult>[];
  for (final item in data) {
    final storedEmbeddingJson = item['embedding'] as String;
    final storedEmbedding = (jsonDecode(storedEmbeddingJson) as List)
        .map((e) => (e as num).toDouble())
        .toList();

    // Skip rows embedded by a different model (dimension mismatch) rather
    // than throwing RangeError and breaking all search after a model switch.
    if (storedEmbedding.length != queryEmbedding.length) {
      continue;
    }

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < queryEmbedding.length; i++) {
      dotProduct += queryEmbedding[i] * storedEmbedding[i];
      normA += queryEmbedding[i] * queryEmbedding[i];
      normB += storedEmbedding[i] * storedEmbedding[i];
    }
    final divisor = sqrt(normA) * sqrt(normB);
    final score = divisor == 0 ? 0.0 : dotProduct / divisor;

    scored.add(SearchResult(
      id: item['id'] as String,
      content: item['content'] as String,
      score: score,
      metadata:
          jsonDecode(item['metadata'] as String? ?? '{}') as Map<String, dynamic>,
    ));
  }
```
(The trailing `return (scored..sort(...)).take(limit).toList();` at `:586-588` stays as-is.)

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/services/vector_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/vector_store.dart test/services/vector_store_test.dart
git commit -m "fix(search): skip embedding rows whose dimension != query dimension"
```

---

## Task 4: Null-safe Document.fromJson (L-23)

**Shape:** Logic (real unit test).

**Files:**
- Modify: `lib/models/document.dart:23-32`
- Test: `test/services/document_management_service_test.dart` (or a new `test/models/document_test.dart`)

**Why:** `Document.fromJson` hard-casts `id`/`title`/`file_path` as `String` and `chunk_count`/`total_characters` as `int` (`:23-32`). Current DDL declares those columns `NOT NULL`, so only legacy/schema-drift rows trigger it — but that becomes real the moment an H-13 migration adds a nullable column or an older row survives. Make the casts null-safe with defaults.

- [ ] **Step 1: Write the failing test**

Create `test/models/document_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/models/document.dart';

void main() {
  group('Document.fromJson -', () {
    test('tolerates missing/null numeric and string fields', () {
      final doc = Document.fromJson(<String, dynamic>{
        'id': 'abc',
        // title, file_path, chunk_count, total_characters, content_hash absent
        'format': 'pdf',
        'ingested_at': 0,
      });
      expect(doc.id, 'abc');
      expect(doc.title, isNotNull);
      expect(doc.chunkCount, 0);
      expect(doc.totalCharacters, 0);
      expect(doc.contentHash, isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/models/document_test.dart`
Expected: FAIL — `type 'Null' is not a subtype of type 'String'`/`int` on the hard casts.

- [ ] **Step 3: Implement null-safe casts**

In `lib/models/document.dart`, change the `fromJson` field reads (`:23-32`) to:
```dart
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      filePath: json['file_path'] as String? ?? '',
      format: DocumentFormat.values.firstWhere(
        (e) => e.name == json['format'],
        orElse: () => DocumentFormat.unknown,
      ),
      chunkCount: json['chunk_count'] as int? ?? 0,
      totalCharacters: json['total_characters'] as int? ?? 0,
      contentHash: json['content_hash'] as String? ?? '',
```
(Leave `ingested_at` reading as-is — it is central to ordering; if it can be null in drift scenarios, guard with `(json['ingested_at'] as int?) ?? 0`.)

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/models/document_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/document.dart test/models/document_test.dart
git commit -m "fix(model): null-safe Document.fromJson with sensible defaults"
```

---

## Task 5: Close the duplicate-document TOCTOU race with a UNIQUE constraint (M-22)

**Shape:** Logic (real test against in-memory sqlite).

**Files:**
- Modify: `lib/services/vector_store.dart` (`_onCreate()` documents-table DDL `:125-145`; add a versioned migration branch)
- Modify: `lib/services/document_management_service.dart` (`addDocument`/`addDocumentFromPlatformFile` insert path)
- Test: `test/services/vector_store_test.dart`

**Why:** `findByHash` → insert is not atomic (`document_management_service.dart:106-111,145-148`); two simultaneous adds of the same file both insert. `content_hash` has only a **non-UNIQUE** index (`vector_store.dart:143-145`). Add a UNIQUE index so the DB enforces dedup. **This bumps the schema — coordinate with Task 1's `schemaVersion`.**

**Interfaces:**
- Consumes: `VectorStore.schemaVersion` and `_migrate` from Task 1.

- [ ] **Step 1: Write the failing test**

Add to `test/services/vector_store_test.dart`:
```dart
test('content_hash has a UNIQUE index', () {
  final rows = vectorStore.db!.select(
    "SELECT sql FROM sqlite_master WHERE type='index' "
    "AND tbl_name='documents' AND sql LIKE '%content_hash%'",
  );
  final hasUnique = rows.any(
    (r) => (r['sql'] as String).toUpperCase().contains('UNIQUE'));
  expect(hasUnique, isTrue);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/services/vector_store_test.dart`
Expected: FAIL — the current index (`idx_documents_hash`) is not UNIQUE.

- [ ] **Step 3: Make the index UNIQUE and bump schema**

In `lib/services/vector_store.dart`, change the documents hash index (`:143-145`) to:
```dart
    _db!.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_documents_hash
      ON documents(content_hash)
    ''');
```
Bump `schemaVersion` to `2` and add the migration branch inside `_migrate` (from Task 1):
```dart
    if (fromVersion < 2) {
      // De-dupe any pre-existing duplicate hashes before adding the UNIQUE index.
      _db!.execute('''
        DELETE FROM documents WHERE rowid NOT IN (
          SELECT MIN(rowid) FROM documents GROUP BY content_hash
        )
      ''');
      _db!.execute('DROP INDEX IF EXISTS idx_documents_hash');
      _db!.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_documents_hash
        ON documents(content_hash)
      ''');
    }
```
Also update Task 1's `schemaVersion` test expectation if it pinned `1` (it asserts `>= 1`, so it stays green).

- [ ] **Step 4: Harden the service insert against the race**

In `lib/services/document_management_service.dart`, the insert now relies on DB enforcement, but keep the app responsive: in `_processIngestion` the initial `insertDocument` (`:187`) uses `INSERT OR REPLACE` (`vector_store.dart:404`) which would clobber on hash collision. Add an in-flight guard set to the service so concurrent same-hash ingestions coalesce. Add a field near `_activeJobs` (`:68`):
```dart
  final Set<String> _inFlightHashes = {};
```
In both `addDocument` (after the `findByHash` check, `:106-111`) and `addDocumentFromPlatformFile` (after its check, `:145-148`), add before creating `docId`:
```dart
    if (_inFlightHashes.contains(hash)) {
      throw Exception('This document is already being ingested');
    }
    _inFlightHashes.add(hash);
```
And in `_processIngestion`'s `finally` (`:331-333`), add:
```dart
      _inFlightHashes.remove(hash);
```
(Pass `hash` into `_processIngestion` — it is already a parameter at `:168`.)

- [ ] **Step 5: Run tests**

Run: `flutter test test/services/vector_store_test.dart test/services/document_management_service_test.dart`
Expected: PASS (all). If the document_management test mocks `VectorStore`, the in-flight guard is exercised via existing/added tests; add a targeted test only if the mock allows simulating concurrency.

- [ ] **Step 6: Commit**

```bash
git add lib/services/vector_store.dart lib/services/document_management_service.dart test/services/vector_store_test.dart
git commit -m "fix(ingest): enforce content_hash uniqueness + in-flight dedup guard"
```

---

## Task 6: Verify model download integrity with SHA-256 (M-1)

**Shape:** Logic + config. The digests are data; the verification logic is testable.

**Files:**
- Modify: `lib/services/model_config.dart` (populate `sha256` per model)
- Modify: `lib/services/model_management_service.dart` (verify before activation)
- Test: `test/services/model_management_service_test.dart`

**Why:** 110 MB–6.5 GB binaries download and execute with **zero** hash verification (`model_config.dart:183` `sha256` field is defined but never populated for any of the 8 models; `model_management_service.dart:214-320` never checks). A corrupted CDN response or tampered file loads undetected. `crypto` is already a dependency (documents are hashed at `document_management_service.dart:143`).

**Interfaces:**
- Produces: non-null `ModelDefinition.sha256` for each of the 8 models; a `Future<bool> _verifyModelDigest(ModelInfo, String expected)` helper (or inline verification) that **fails closed**.

- [ ] **Step 1: Obtain and record the digests**

For each of the 8 model URLs (`model_config.dart:20-154`), record the upstream SHA-256. HuggingFace exposes it via the LFS pointer / API (`GET https://huggingface.co/api/models/<repo>` → `siblings[].lfs.sha256`, or the `X-Linked-Etag`/`git lfs` sha). Do **not** invent hashes. Populate each `ModelDefinition` with e.g.:
```dart
    sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
```
Keep a note of the source of each hash in a `// verified 2026-07-07 from HF LFS` comment.

- [ ] **Step 2: Write the failing test (verification logic)**

Add to `test/services/model_management_service_test.dart`:
```dart
test('every model definition declares a sha256', () {
  for (final m in ModelConfig.allModels) {
    expect(m.sha256, isNotNull, reason: 'model ${m.id} missing sha256');
    expect(m.sha256!.length, 64, reason: 'model ${m.id} sha256 not 64 hex chars');
  }
});
```
(Requires `import 'package:offline_sync/services/model_config.dart';`.)

- [ ] **Step 3: Run it to confirm it fails**

Run: `flutter test test/services/model_management_service_test.dart`
Expected: FAIL until Step 1's digests are in place (was `null`).

- [ ] **Step 4: Verify digest before activation (fail closed)**

flutter_gemma downloads to its own managed path, so verification must hook where the file is accessible. If flutter_gemma exposes the installed file path, compute `sha256.convert(await file.readAsBytes())` (stream for large files via `sha256.bind(file.openRead())`) after `install()` completes in `_performDownload` (`:265-270`) and **before** marking `ModelStatus.downloaded`; on mismatch set `ModelStatus.error`, delete the file if reachable, and `addError`. If flutter_gemma does not expose the path, record this limitation in a `// M-1:` comment and gate verification behind a capability check — but still land Step 1–3 (the declared digests) so a future flutter_gemma version can enforce. Document the actual capability in the commit message.

- [ ] **Step 5: Run tests**

Run: `flutter test test/services/model_management_service_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/model_config.dart lib/services/model_management_service.dart test/services/model_management_service_test.dart
git commit -m "feat(models): declare per-model sha256 and verify downloads (fail closed)"
```

---

## Task 7: Harden flutter_secure_storage platform options (M-2)

**Shape:** Config. Verification = analyze + a test asserting options are set (via a constructor check is hard on a static const; verify by inspection + analyze).

**Files:**
- Modify: `lib/services/auth_token_service.dart:12`

**Why:** `const FlutterSecureStorage()` uses no platform options, though the project's own `docs/implementation_plan_v3.md:1218-1219` specifies `AndroidOptions(encryptedSharedPreferences: true)` and `IOSOptions(accessibility: KeychainAccessibility.first_unlock)`. Default iOS keychain accessibility can leak the HF token into device backups.

- [ ] **Step 1: Replace the storage instance with hardened options**

> **Version note:** the installed `flutter_secure_storage` is **10.3.1**, where `AndroidOptions(encryptedSharedPreferences: true)` is **deprecated and ignored** (v10 auto-migrates to custom ciphers; passing it emits a `deprecated_member_use` warning and does nothing). Do **not** pass it — that would violate the "analyze clean" constraint. The iOS `accessibility` option is the meaningful hardening on the shipped version.

In `lib/services/auth_token_service.dart`, replace `:12`:
```dart
  static const _storage = FlutterSecureStorage();
```
with:
```dart
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
```
(`FlutterSecureStorage`, `IOSOptions`, `KeychainAccessibility` come from the already-imported `package:flutter_secure_storage/flutter_secure_storage.dart` at `:1`. On v10, Android encryption is automatic; if the project later upgrades to v11 or downgrades to v9, revisit the Android options.)

- [ ] **Step 2: Verify it compiles and existing token tests pass**

Run: `flutter analyze lib/services/auth_token_service.dart && flutter test test/services/auth_token_service_test.dart`
Expected: analyze clean (0 warnings — the deprecated param is intentionally omitted); token tests green.

- [ ] **Step 3: Commit**

```bash
git add lib/services/auth_token_service.dart
git commit -m "fix(security): harden secure-storage options (encrypted prefs, first_unlock)"
```

---

## Task 8: Syncfusion license decision (M-26)

**Shape:** Decision (documented, no code). No test.

**Files:**
- Create/modify: `docs/licensing.md`
- Reference: `pubspec.yaml:37` (`syncfusion_flutter_pdf ^33.2.13`)

**Why:** Syncfusion is not free for general commercial distribution; no `registerLicense` call exists anywhere (audit grep: 0 hits). The non-UI PDF package runs without a key, so nothing fails at runtime — the exposure is **legal, not technical**.

- [ ] **Step 1: Determine eligibility and record the decision**

Assess against Syncfusion's Community License limits (revenue/headcount). Create `docs/licensing.md` recording one of:
  - **Community License eligible** → note the eligibility basis and that no key is required for the non-UI package, OR
  - **Commercial license required** → note the license key location and add `SyncfusionLicense.registerLicense(<key>)` in `bootstrap.dart` (behind an env/const), OR
  - **Replace Syncfusion** → open a follow-up task to migrate PDF parsing to a permissively-licensed package.

This is a maintainer decision — surface it and do not guess. Default action if unresolved: document the open risk explicitly in `docs/licensing.md` so it is tracked, and flag for the maintainer.

- [ ] **Step 2: Commit**

```bash
git add docs/licensing.md
git commit -m "docs: record Syncfusion licensing decision/risk"
```

---

## Phase 2 completion gate

- [ ] All 8 tasks committed.
- [ ] `flutter test` → all green (count increased by the new tests: Task 1, 2, 3, 4, 6 add tests).
- [ ] `flutter analyze` → 0 errors, 0 warnings.
- [ ] `PRAGMA user_version` is stamped and `schemaVersion` reflects the M-22 bump (`2`).
- [ ] Proceed to [Phase 3 — Stability](2026-07-07-prod-phase3-stability.md).
