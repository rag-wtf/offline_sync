# Phase 3 — Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.
> Master plan: [2026-07-07-production-readiness-remediation.md](2026-07-07-production-readiness-remediation.md).

**Goal:** Eliminate listener leaks, submit races, unbounded hangs, resource leaks, and error dead-ends so the app degrades gracefully instead of stalling.

**Architecture:** Most fixes are in viewmodels (subscription lifecycle) and services (try/finally, timeouts). Stacked's `BaseViewModel.dispose()` and `notifyListeners()` (no-op after dispose) behavior is the backdrop. Where a viewmodel has no test today (chat, document_library, document_detail, settings), tasks add a first test using the mocktail helpers in `test/helpers/test_helpers.dart`.

**Tech Stack:** Stacked, mocktail, `StreamController.broadcast`, `Future.timeout`.

## Global Constraints

See master plan. Phase-specific:
- Every viewmodel that calls `.listen(...)` MUST store the `StreamSubscription` and cancel it in a `dispose()` override.
- Every post-`await` continuation in a disposable object MUST check a disposed flag (or hold a cancellable subscription) before mutating state or persisting.
- Timeouts (H-1) MUST be configurable and surface a **recoverable, user-facing** error — never swallow silently.

### Test conventions (applies to every new test in this phase)

The test sketches below show the **key assertion and stubs**, not every line. When implementing:
- **`registerFallbackValue` is required** for any `any()`/`captureAny()` matcher on a non-primitive type. In `setUpAll`, register fallbacks for the types you match — e.g. `registerFallbackValue(ChatMessage(content: '', isUser: true, timestamp: DateTime(0)))`, `registerFallbackValue(FakePlatformFile())` (a trivial `Fake` subclass), `registerFallbackValue(<a Document>)`. Omitting these makes the `when(...)` stub throw at registration.
- **Prefer the existing idiom** in `test/helpers/test_helpers.dart` — `getAndRegisterMock*()` and the shared `Mock*` classes — over bespoke local mocks, and call `unregisterTestHelpers()` in `tearDown`. Where a mock the file needs is missing from `test_helpers.dart` (e.g. `MockDocumentManagementService`, `MockChatRepository`, `MockDialogService`, `MockSnackbarService`), **add it there** so it is reusable, rather than declaring a one-off local mock.

---

## Task 1: Store and cancel the ingestion listener in DocumentLibraryViewModel (H-15)

**Shape:** Lifecycle (test with a fake broadcast stream via the mock service).

**Files:**
- Modify: `lib/ui/views/document_library/document_library_viewmodel.dart` (`initialize()` `:24-54`)
- Test: `test/ui/views/document_library/document_library_viewmodel_test.dart` (new)

**Why:** `ingestionProgressStream.listen(...)` (`:30`) is never stored; there is no `dispose()` override; the stream is broadcast (`document_management_service.dart:62`). Listeners accumulate on every navigation to DocumentLibraryView — disposed viewmodels keep mutating `_activeIngestions`, firing the 2-second `Future.delayed`, and each stacked listener fires its own error dialog / `_refreshDocuments`, so after N visits one event fires N handlers.

- [ ] **Step 1: Write the failing test**

Create `test/ui/views/document_library/document_library_viewmodel_test.dart`:
```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/ui/views/document_library/document_library_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

class _MockDocService extends Mock implements DocumentManagementService {}
class _MockNav extends Mock implements NavigationService {}
class _MockDialog extends Mock implements DialogService {}

void main() {
  late StreamController<IngestionProgress> controller;

  setUp(() {
    controller = StreamController<IngestionProgress>.broadcast();
    final docService = _MockDocService();
    when(() => docService.ingestionProgressStream)
        .thenAnswer((_) => controller.stream);
    when(docService.getAllDocuments).thenAnswer((_) async => []);
    locator
      ..registerSingleton<DocumentManagementService>(docService)
      ..registerSingleton<NavigationService>(_MockNav())
      ..registerSingleton<DialogService>(_MockDialog());
  });

  tearDown(() async {
    await controller.close();
    await locator.reset();
  });

  test('cancels ingestion subscription on dispose', () async {
    final vm = DocumentLibraryViewModel();
    await vm.initialize();
    expect(controller.hasListener, isTrue);
    vm.dispose();
    expect(controller.hasListener, isFalse);
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/ui/views/document_library/document_library_viewmodel_test.dart`
Expected: FAIL — after `dispose()`, `controller.hasListener` is still `true` (no dispose override, subscription not stored).

- [ ] **Step 3: Implement subscription storage + dispose + disposed guard**

In `lib/ui/views/document_library/document_library_viewmodel.dart`, add the import at top:
```dart
import 'dart:async';
```
Add a field near `_activeIngestions` (`:19`):
```dart
  StreamSubscription<IngestionProgress>? _progressSubscription;
```
Change the listen call (`:30`) to store it:
```dart
    _progressSubscription =
        _documentService.ingestionProgressStream.listen((event) async {
```
Guard the post-`await` continuation: immediately after `await Future<void>.delayed(const Duration(seconds: 2));` (`:38`), insert this line (`disposed` is Stacked's `BaseViewModel` flag):
```dart
        if (disposed) return;
```
Add a `dispose()` override at the end of the class (before the closing brace):
```dart
  @override
  void dispose() {
    unawaited(_progressSubscription?.cancel());
    super.dispose();
  }
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/ui/views/document_library/document_library_viewmodel_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/views/document_library/document_library_viewmodel.dart test/ui/views/document_library/document_library_viewmodel_test.dart
git commit -m "fix(ui): cancel ingestion listener on DocumentLibraryViewModel dispose"
```

---

## Task 2: Cancel the model-status subscription before re-subscribing in retry (H-5) + reset via service (L-15)

**Shape:** Lifecycle (extend existing startup_viewmodel test).

**Files:**
- Modify: `lib/ui/views/startup/startup_viewmodel.dart` (`runStartupLogic` `:44`, `retry` `:233-251`)
- Modify: `lib/services/model_management_service.dart` (add `resetErroredModels()`)
- Test: `test/ui/views/startup/startup_viewmodel_test.dart`

**Why:** Each `retry()` re-assigns `_subscription = _modelService.modelStatusStream.listen(...)` (`:44`) without cancelling the previous one; the stream is broadcast (`model_management_service.dart:51`) so the second listen duplicates. `dispose()` (`:263`) cancels only the last. Also (L-15) `retry()` directly mutates service-owned `ModelInfo` objects (`:241-248`) — move that into a service method.

**Interfaces:**
- Produces: `void ModelManagementService.resetErroredModels()`.

- [ ] **Step 1: Write the failing test**

Add to `test/ui/views/startup/startup_viewmodel_test.dart` a test that calls `runStartupLogic()` twice (or `retry()`) and asserts the model-status stream has exactly one listener. Using the existing mock, expose a broadcast controller for `modelStatusStream` and assert `controller.hasListener` stays single and that a prior subscription is cancelled. (Follow the existing file's setup idiom; add:)
```dart
test('retry does not stack model-status subscriptions', () async {
  // arrange: mock modelStatusStream backed by a broadcast controller,
  // models returning a downloaded state so runStartupLogic completes.
  // act:
  await viewModel.runStartupLogic();
  await viewModel.retry();
  // assert: the controller has at most one active listener at a time.
  // (Implementation detail: verify cancel() was invoked on the first sub.)
});
```
(Fill in arrange/act/assert using the file's existing mocks; the behavioral assertion is "no duplicate listeners after retry".)

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/ui/views/startup/startup_viewmodel_test.dart`
Expected: FAIL — two active listeners after retry.

- [ ] **Step 3: Cancel before re-subscribe**

In `lib/ui/views/startup/startup_viewmodel.dart`, at the start of `runStartupLogic()` (`:40`, before `:44`), add:
```dart
    await _subscription?.cancel();
```
(Make `runStartupLogic` still return `Future<void>`; it already does.)

- [ ] **Step 4: Add and use resetErroredModels (L-15)**

In `lib/services/model_management_service.dart`, add after `switchEmbeddingModel` (`:374`):
```dart
  /// Reset models in error state back to notDownloaded so they can be retried.
  void resetErroredModels() {
    for (final model in _models) {
      if (model.status == ModelStatus.error) {
        model
          ..status = ModelStatus.notDownloaded
          ..progress = 0.0
          ..errorMessage = null;
      }
    }
    _notify();
  }
```
In `startup_viewmodel.dart`, replace the inline mutation loop in `retry()` (`:241-248`) with:
```dart
    _modelService.resetErroredModels();
```

- [ ] **Step 4b: Update the existing retry test (it will otherwise break)**

The existing test `test/ui/views/startup/startup_viewmodel_test.dart:212-237` ("Should reset model error states on retry") asserts on the real `errorModel.status/progress/errorMessage` after `retry()`. Because `_modelService` is a `MockModelManagementService`, the new `resetErroredModels()` is an unstubbed no-op and those three assertions now fail. The reset logic has moved to (and should now be tested in) `ModelManagementService`, so change the viewmodel test to verify **delegation** instead of mutation:
```dart
      // was: expect(errorModel.status, ModelStatus.notDownloaded); etc.
      when(modelService.resetErroredModels).thenReturn(null);
      await viewModel.retry();
      verify(modelService.resetErroredModels).called(1);
```
Add a separate unit test in `test/services/model_management_service_test.dart` asserting `resetErroredModels()` actually flips an errored model to `notDownloaded` with cleared progress/message.

- [ ] **Step 5: Run tests**

Run: `flutter test test/ui/views/startup/startup_viewmodel_test.dart test/services/model_management_service_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/views/startup/startup_viewmodel.dart lib/services/model_management_service.dart test/ui/views/startup/startup_viewmodel_test.dart
git commit -m "fix(startup): cancel status sub before retry; reset errored models via service"
```

---

## Task 3: Fix double-submit race in chat sendMessage (H-6)

**Shape:** Logic (real test on ChatViewModel — first test for this file).

**Files:**
- Modify: `lib/ui/views/chat/chat_viewmodel.dart` (`sendMessage` `:135-149`)
- Test: `test/ui/views/chat/chat_viewmodel_test.dart` (new)

**Why:** The `_isProcessing` guard (`:136`) and `_isProcessing = true` (`:148`) are separated by `await _chatRepository.saveMessage(userMsg)` (`:144`). Two rapid taps both pass the guard → duplicate user messages and two concurrent RAG streams mutating shared `messages`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/views/chat/chat_viewmodel_test.dart`. Register mocks for `RagService`, `ChatRepository`, `SnackbarService`, `NavigationService`, `DialogService`, `DocumentManagementService`, `VectorStore` via helpers/local mocks. Make `saveMessage` slow (delayed) and `askWithRAGStream` return an empty stream, then fire two `sendMessage` calls without awaiting the first:
```dart
test('concurrent sendMessage calls do not double-submit', () async {
  when(() => chatRepo.saveMessage(any()))
      .thenAnswer((_) => Future.delayed(const Duration(milliseconds: 50)));
  when(() => ragService.askWithRAGStream(any(),
        includeMetrics: any(named: 'includeMetrics'),
        conversationHistory: any(named: 'conversationHistory'),
        documentIds: any(named: 'documentIds')))
      .thenAnswer((_) => const Stream.empty());

  final f1 = vm.sendMessage('hello');
  final f2 = vm.sendMessage('hello'); // fires before f1's await resolves
  await Future.wait([f1, f2]);

  final userMsgs = vm.messages.where((m) => m.isUser && m.content == 'hello');
  expect(userMsgs.length, 1); // only one accepted
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/ui/views/chat/chat_viewmodel_test.dart`
Expected: FAIL — two user messages recorded (both passed the guard before either set `_isProcessing`).

- [ ] **Step 3: Set the flag synchronously right after the guard**

In `lib/ui/views/chat/chat_viewmodel.dart`, `sendMessage` (`:135-149`), move `_isProcessing = true;` to immediately after the guard, before any `await`:
```dart
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isProcessing) return;
    _isProcessing = true;

    final userMsg = ChatMessage(
      content: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    messages.add(userMsg);
    await _chatRepository.saveMessage(userMsg); // Persist user message
    _shouldScroll = true;
    notifyListeners();
```
Delete the later `_isProcessing = true; notifyListeners();` pair at the old `:148-149` (keep a single `notifyListeners()` after adding the message).

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/ui/views/chat/chat_viewmodel_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/views/chat/chat_viewmodel.dart test/ui/views/chat/chat_viewmodel_test.dart
git commit -m "fix(chat): set processing flag synchronously to block double-submit"
```

---

## Task 4: Guard the RAG streaming loop against dispose (H-7)

**Shape:** Lifecycle (test on ChatViewModel).

**Files:**
- Modify: `lib/ui/views/chat/chat_viewmodel.dart` (`sendMessage` stream loop `:176-203`, `dispose` `:310-315`)
- Test: `test/ui/views/chat/chat_viewmodel_test.dart`

**Why:** The `await for` over `askWithRAGStream` is not held as a cancellable subscription and checks no disposed flag. Navigating away mid-stream leaves inference running, keeps mutating `messages`, and persists via `saveMessage` (`:201`) after teardown.

- [ ] **Step 1: Write the failing test**

Add to `test/ui/views/chat/chat_viewmodel_test.dart`: emit a stream that yields tokens with a small delay, dispose the viewmodel mid-stream, and assert `saveMessage` is NOT called with the AI message after dispose:
```dart
test('stops persisting/mutating after dispose mid-stream', () async {
  final ctrl = StreamController<RAGStreamEvent>();
  when(() => ragService.askWithRAGStream(any(),
        includeMetrics: any(named: 'includeMetrics'),
        conversationHistory: any(named: 'conversationHistory'),
        documentIds: any(named: 'documentIds')))
      .thenAnswer((_) => ctrl.stream);
  when(() => chatRepo.saveMessage(any())).thenAnswer((_) async {});

  final f = vm.sendMessage('q');
  ctrl.add(RAGTokenEvent('partial'));
  await Future<void>.delayed(Duration.zero);
  vm.dispose();
  ctrl..add(RAGCompleteEvent())..close();
  await f;

  // After dispose, the RAGCompleteEvent must not trigger a save.
  verifyNever(() => chatRepo.saveMessage(
      any(that: isA<ChatMessage>().having((m) => m.isUser, 'isUser', false))));
});
```
(Adjust the `verifyNever` matcher to the project's `ChatMessage`; the intent: no AI-message persistence after dispose.)

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/ui/views/chat/chat_viewmodel_test.dart`
Expected: FAIL — the completion handler still calls `saveMessage` after dispose.

- [ ] **Step 3: Track disposal and break the loop**

In `lib/ui/views/chat/chat_viewmodel.dart`, add a field near `_isProcessing` (`:71`):
```dart
  bool _disposed = false;
```
Set it in `dispose()` (`:311`), first line of the override:
```dart
  @override
  void dispose() {
    _disposed = true;
    unawaited(_progressSubscription?.cancel());
    scrollController.dispose();
    super.dispose();
  }
```
In the `await for` loop (`:183-203`), break early when disposed. At the top of the loop body (right after `await for (final event in …) {`), add:
```dart
        if (_disposed) break;
```
And guard the completion persistence (`:199-202`):
```dart
        } else if (event is RAGCompleteEvent) {
          if (_disposed) break;
          await _chatRepository.saveMessage(messages[aiMsgIndex]);
        }
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/ui/views/chat/chat_viewmodel_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/views/chat/chat_viewmodel.dart test/ui/views/chat/chat_viewmodel_test.dart
git commit -m "fix(chat): break RAG stream loop and skip persistence after dispose"
```

---

## Task 5: Add configurable timeouts to all model/inference calls (H-1)

**Shape:** Logic where testable (services), verification for the rest.

**Files:**
- Modify: `lib/services/rag_constants.dart` (add timeout constant)
- Modify: `lib/services/rag_service.dart:383,454`; `reranking_service.dart:86`; `query_expansion_service.dart:36`; `contextual_retrieval_service.dart:97`; `embedding_service.dart:14`
- Test: `test/services/reranking_service_test.dart` (timeout path is easiest to exercise here)

**Why:** All on-device LLM/embedding calls run unbounded. A hung native inference blocks the request forever with no cancellation path.

**Interfaces:**
- Produces: `RagConstants.inferenceTimeout` (a `Duration`).

- [ ] **Step 1: Add the constant**

In `lib/services/rag_constants.dart`, add:
```dart
  /// Maximum wall-clock time for a single on-device inference/embedding call
  /// before surfacing a recoverable timeout error.
  static const Duration inferenceTimeout = Duration(seconds: 60);
```

- [ ] **Step 2: Write the failing test (reranking timeout)**

Add to `test/services/reranking_service_test.dart`: make `generateChatResponseAsync` return a stream that never emits, and assert `rerank` completes within a bounded time returning original candidates (its existing error-fallback path) rather than hanging:
```dart
test('reranking falls back when inference exceeds timeout', () async {
  final candidates = [
    SearchResult(id: '1', content: 'c1', score: 0.5, metadata: {}),
  ];
  when(() => mockModelProvider.getModel())
      .thenAnswer((_) async => mockInferenceModel);
  final mockChat = MockInferenceChat();
  when(() => mockInferenceModel.createChat(temperature: any(named: 'temperature')))
      .thenAnswer((_) async => mockChat);
  when(mockChat.initSession).thenAnswer((_) async {});
  when(() => mockChat.addQuery(any())).thenAnswer((_) async {});
  // A controller whose stream never emits or closes simulates a hung inference.
  final never = StreamController<ModelResponse>();
  when(mockChat.generateChatResponseAsync).thenAnswer((_) => never.stream);

  // Pass a short timeout so the test is fast (see Step 3 — rerank gains an
  // optional `timeout` parameter defaulting to RagConstants.inferenceTimeout).
  final result = await service.rerank(
    'q', candidates, timeout: const Duration(milliseconds: 100));

  expect(result, candidates); // falls back to originals on timeout
  await never.close();
});
```
(The `.rerank(..., timeout:)` parameter is added in Step 3 specifically so this test runs in ~100ms rather than waiting the 60s production default.)

- [ ] **Step 3: Apply timeouts — where matters (inner vs outer catch)**

The correct placement depends on each service's existing catch structure. **Do not blindly wrap the innermost stream** — in reranking that would be swallowed by an inner catch and defeat the fallback.

**Reranking (`reranking_service.dart`) — apply at the `rerank` loop, NOT inside `_scoreRelevance`.** `_scoreRelevance` (`:63-109`) has its own `on Exception catch` (`:99`) that returns a neutral `5.0`; a `TimeoutException` (which *is* an `Exception`) wrapped inside it would be caught there and never reach `rerank`'s outer fallback (`return candidates`, `:58`). Instead, add an optional param and time out the **call to** `_scoreRelevance`:
```dart
  Future<List<SearchResult>> rerank(
    String query,
    List<SearchResult> candidates, {
    int topK = 5,
    Duration? timeout,
  }) async {
    if (candidates.isEmpty) return candidates;
    final effectiveTimeout = timeout ?? RagConstants.inferenceTimeout;
    try {
      final inferenceModel = await _inferenceModelProvider.getModel();
      final scoredResults = <_ScoredResult>[];
      for (var i = 0; i < candidates.length && i < topK; i++) {
        final candidate = candidates[i];
        final score = await _scoreRelevance(
          inferenceModel, query, candidate.content,
        ).timeout(effectiveTimeout);
        scoredResults.add(_ScoredResult(result: candidate, score: score));
      }
      // ... existing sort + map unchanged ...
```
Because the `.timeout` is applied to the `Future` returned by `_scoreRelevance` (outside its inner catch), a hang throws `TimeoutException` into `rerank`'s outer `on Exception catch` (`:50`), which `return candidates` — the **same list object**. That is what the Step 2 test asserts (`expect(result, candidates)` works by identity; note `SearchResult` has no `==` override, so identity is the only equality that holds). Import `RagConstants`.

**RagService generation (`rag_service.dart:382-387` and `:453-458`) — wrap the stream** (no inner swallow; must surface to the user):
```dart
    final stream = chat
        .generateChatResponseAsync()
        .timeout(RagConstants.inferenceTimeout);
```
`TimeoutException` propagates to `chat_viewmodel`'s `on Exception` handler (`:212`) → snackbar. Acceptable.

**Query expansion (`query_expansion_service.dart:35`) and contextual retrieval (`contextual_retrieval_service.dart:97`) — wrap the stream inside their existing try**, so a timeout degrades gracefully via their fallbacks (`[query]` / `''`). Note: `:97` iterates `chat.generateChatResponseAsync()` **inline** (no intermediate variable), so first extract a variable:
```dart
      final stream =
          chat.generateChatResponseAsync().timeout(RagConstants.inferenceTimeout);
      await for (final token in stream) { ... }
```

**Embedding (`embedding_service.dart:14`)** — a `Future`:
```dart
    final result = await embedder
        .generateEmbedding(text)
        .timeout(RagConstants.inferenceTimeout);
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/services/reranking_service_test.dart test/services/rag_service_test.dart`
Expected: PASS (no hang; timeout falls back).

- [ ] **Step 5: Commit**

```bash
git add lib/services/rag_constants.dart lib/services/rag_service.dart lib/services/reranking_service.dart lib/services/query_expansion_service.dart lib/services/contextual_retrieval_service.dart lib/services/embedding_service.dart test/services/reranking_service_test.dart
git commit -m "feat(rag): bound all inference/embedding calls with configurable timeout"
```

---

## Task 6: Dispose PdfDocument in a finally block (H-8)

**Shape:** Logic (verify via try/finally structure; a real test needs a valid PDF fixture — use structural verification if none exists).

**Files:**
- Modify: `lib/services/document_parser_service.dart` (`_parsePdf` `:116-125`)

**Why:** `document.dispose()` (`:120`) only runs on success; the catch (`:122`) rethrows without disposing — retained Dart memory per failed/corrupt PDF and a missing-try/finally defect.

- [ ] **Step 1: Restructure with try/finally**

In `lib/services/document_parser_service.dart`, replace `_parsePdf` (`:116-125`):
```dart
  Future<String> _parsePdf(Uint8List bytes) async {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      return PdfTextExtractor(document).extractText();
    } catch (e) {
      throw Exception('Failed to parse PDF: $e');
    } finally {
      document?.dispose();
    }
  }
```

- [ ] **Step 2: Verify existing parser tests still pass + analyze**

Run: `flutter test test/services/document_parser_service_test.dart && flutter analyze lib/services/document_parser_service.dart`
Expected: PASS; analyze clean. (If a corrupt-PDF fixture exists or can be a few random bytes with a `.pdf` name, add a test asserting `parseDocumentFromBytes(randomBytes, 'x.pdf')` throws and does not leak — but the primary fix is the try/finally structure.)

- [ ] **Step 3: Commit**

```bash
git add lib/services/document_parser_service.dart
git commit -m "fix(parser): dispose PdfDocument in finally on parse failure"
```

---

## Task 7: Recover the token dialog from save failure (H-9)

**Shape:** Lifecycle/error-handling (widget test).

**Files:**
- Modify: `lib/ui/dialogs/token_input_dialog.dart` (`_saveToken` `:25-56`)
- Test: `test/ui/dialogs/token_input_dialog_test.dart` (new; widget test)

**Why:** `AuthTokenService.saveToken` (`:51`) is not wrapped; on keystore/storage failure `_isSaving` (set `:48`) never resets, the button (`onPressed: _isSaving ? null : _saveToken`, `:115`) stays disabled, and no error shows — a dead-end auth flow.

- [ ] **Step 1: Wrap the save in try/catch/finally**

In `lib/ui/dialogs/token_input_dialog.dart`, replace the save call (`:51-55`):
```dart
    try {
      await AuthTokenService.saveToken(token);
      if (mounted) {
        Navigator.of(context).pop(true); // success
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save token: $e';
          _isSaving = false;
        });
      }
    }
```
(Remove the now-duplicated bare `Navigator.of(context).pop(true)` that followed. `_isSaving` is reset on the failure path so the button re-enables.)

- [ ] **Step 2: Add a widget test (optional but recommended)**

Create `test/ui/dialogs/token_input_dialog_test.dart` that pumps the dialog, enters a valid `hf_...` token, stubs `AuthTokenService.saveToken` to throw, taps Save, and asserts the button re-enables and an error is shown. If `AuthTokenService`'s static methods are hard to stub, verify manually via the driver and document it; the code fix stands on its own.

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/ui/dialogs/token_input_dialog.dart` (and the widget test if added).
Expected: clean / green.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/dialogs/token_input_dialog.dart
git commit -m "fix(auth): reset saving state and surface error on token save failure"
```

---

## Task 8: Add try/finally + error state to DocumentDetailViewModel (H-10)

**Shape:** Lifecycle/error-handling (unit test).

**Files:**
- Modify: `lib/ui/views/document_detail/document_detail_viewmodel.dart` (`initialize` `:17-22`)
- Test: `test/ui/views/document_detail/document_detail_viewmodel_test.dart` (new)

**Why:** `setBusy(true)` … `setBusy(false)` with no try/finally and no error state (`:17-22`). Any throw leaves "Loading chunks..." forever.

- [ ] **Step 1: Write the failing test**

Create `test/ui/views/document_detail/document_detail_viewmodel_test.dart`: register a mock `DocumentManagementService` whose `getDocumentChunks` throws, call `initialize(doc)`, and assert `isBusy` is `false` afterward and `hasError` is `true`:
```dart
test('clears busy and sets error when chunk load throws', () async {
  when(() => docService.getDocumentChunks(any()))
      .thenThrow(Exception('db error'));
  await vm.initialize(sampleDoc);
  expect(vm.isBusy, isFalse);
  expect(vm.hasError, isTrue);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/ui/views/document_detail/document_detail_viewmodel_test.dart`
Expected: FAIL — the throw escapes; `isBusy` stays true, `hasError` false.

- [ ] **Step 3: Implement try/catch/finally**

In `lib/ui/views/document_detail/document_detail_viewmodel.dart`, replace `initialize` (`:17-22`):
```dart
  Future<void> initialize(Document doc) async {
    _document = doc;
    setBusy(true);
    try {
      _chunks = await _documentService.getDocumentChunks(doc.id);
    } on Exception catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  }
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/ui/views/document_detail/document_detail_viewmodel_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/views/document_detail/document_detail_viewmodel.dart test/ui/views/document_detail/document_detail_viewmodel_test.dart
git commit -m "fix(ui): handle chunk-load errors in DocumentDetailViewModel"
```

---

## Task 9: Fix chat file-attach on web by delegating to the byte-aware flow (H-11)

**Shape:** Logic (unit test on ChatViewModel).

**Files:**
- Modify: `lib/ui/views/chat/chat_viewmodel.dart` (`pickAndIngestFiles` `:241-297`)
- Test: `test/ui/views/chat/chat_viewmodel_test.dart`

**Why:** The chat attach path filters `f.path != null` (`:262-264`) and re-reads from disk; on web `path` is always null → `paths` empty → silent return (`:266`). It ignores `file.bytes`, unlike DocumentLibrary's correct `addDocumentFromPlatformFile` flow.

- [ ] **Step 1: Write the failing test**

Add to `test/ui/views/chat/chat_viewmodel_test.dart`: stub `FilePicker` result with a `PlatformFile` that has `bytes` but null `path` (simulating web); assert `docService.addDocumentFromPlatformFile` is called once per file. Since `FilePicker.pickFiles` is static, either inject the picker or assert at the `DocumentManagementService` boundary. Simplest robust approach: refactor to call a seam method `ingestPlatformFiles(List<PlatformFile>)` and test that:
```dart
test('ingests byte-only (web) files via addDocumentFromPlatformFile', () async {
  final webFile = PlatformFile(name: 'a.pdf', size: 3, bytes: Uint8List.fromList([1,2,3]));
  when(() => docService.addDocumentFromPlatformFile(any()))
      .thenAnswer((_) async => sampleDoc);
  await vm.ingestPlatformFiles([webFile]);
  verify(() => docService.addDocumentFromPlatformFile(webFile)).called(1);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/ui/views/chat/chat_viewmodel_test.dart`
Expected: FAIL — `ingestPlatformFiles` does not exist / current path ignores bytes.

- [ ] **Step 3: Refactor to delegate per file**

In `lib/ui/views/chat/chat_viewmodel.dart`, replace the body of `pickAndIngestFiles` (`:256-296`, after the picker returns `result`) to delegate to a new seam method, and add the method:
```dart
    if (result == null || result.files.isEmpty) return;
    await ingestPlatformFiles(result.files);
  }

  /// Ingests picked files, using bytes when available (web) and paths otherwise.
  Future<void> ingestPlatformFiles(List<PlatformFile> files) async {
    setBusy(true);
    var success = 0;
    var failed = 0;
    try {
      for (final file in files) {
        try {
          await _documentService.addDocumentFromPlatformFile(file);
          success++;
        } on Exception catch (_) {
          failed++;
        }
      }
      if (failed == 0) {
        _snackbarService.showSnackbar(
            message: 'Successfully ingested $success file(s)');
      } else if (success == 0) {
        _snackbarService.showSnackbar(
            message: 'Failed to ingest $failed file(s)');
      } else {
        _snackbarService.showSnackbar(
            message: 'Ingested $success file(s). Failed to ingest $failed file(s).');
      }
    } finally {
      setBusy(false);
    }
  }
```
(`_documentService` is the existing `locator<DocumentManagementService>()` field at `:50`; drop the redundant local `docService` lookup at `:248`.)

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/ui/views/chat/chat_viewmodel_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/views/chat/chat_viewmodel.dart test/ui/views/chat/chat_viewmodel_test.dart
git commit -m "fix(chat): ingest attached files via byte-aware path (fixes web)"
```

---

## Task 10: Close prepared statements on error; fix batch rollback leak (M-8)

**Shape:** Logic (verify via structure + existing DB tests).

**Files:**
- Modify: `lib/services/vector_store.dart` (`insertEmbedding` `:346-367`, `insertDocument` `:402-425`, `insertEmbeddingsBatch` `:370-398`)

**Why:** `..execute(...)..close()` cascades skip `close()` on throw; `insertEmbeddingsBatch`'s rollback path (`:394-397`) never closes its statement.

- [ ] **Step 1: Wrap each prepared statement in try/finally**

`insertEmbedding` (`:353-366`) becomes:
```dart
    final stmt = _db!.prepare('''
INSERT OR REPLACE INTO vectors
         (id, document_id, content, embedding, metadata, created_at)
         VALUES (?, ?, ?, ?, ?, ?)
''');
    try {
      stmt.execute([
        id, documentId, content, jsonEncode(embedding),
        if (metadata != null) jsonEncode(metadata) else null,
        DateTime.now().millisecondsSinceEpoch,
      ]);
    } finally {
      stmt.close();
    }
```
`insertDocument` (`:403-424`): same pattern — assign `final stmt = _db!.prepare(...)`, wrap `stmt.execute([...])` in `try { … } finally { stmt.close(); }`.
`insertEmbeddingsBatch` (`:375-397`): move `stmt.close()` into a `finally` so it closes on both the commit and the rollback path:
```dart
    _db!.execute('BEGIN TRANSACTION');
    final stmt = _db!.prepare('''
        INSERT OR REPLACE INTO vectors
        (id, document_id, content, embedding, metadata, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
      ''');
    try {
      for (final item in items) {
        stmt.execute([
          item.id, item.documentId, item.content, jsonEncode(item.embedding),
          if (item.metadata != null) jsonEncode(item.metadata) else null,
          DateTime.now().millisecondsSinceEpoch,
        ]);
      }
      _db!.execute('COMMIT');
    } catch (e) {
      _db!.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.close();
    }
```

- [ ] **Step 2: Verify existing DB tests pass**

Run: `flutter test test/services/vector_store_test.dart`
Expected: PASS (insert/CRUD tests exercise these paths).

- [ ] **Step 3: Commit**

```bash
git add lib/services/vector_store.dart
git commit -m "fix(db): close prepared statements in finally on all paths"
```

---

## Task 11: Memoize in-flight model init; dispose old model on clearCache (M-7)

**Shape:** Logic (unit test on InferenceModelProvider — untested today).

**Files:**
- Modify: `lib/services/inference_model_provider.dart` (`getModel` `:21-60`, `clearCache` `:67-69`)
- Test: `test/services/inference_model_provider_test.dart` (new)

**Why:** Concurrent callers (RagService + QueryExpansion + Reranking within one query) can double-initialize; `clearCache` drops the old handle without disposing → leaked native sessions on model switch.

- [ ] **Step 1: Write the failing test**

Create `test/services/inference_model_provider_test.dart`. Because `getModel` calls the static `FlutterGemma.getActiveModel`, this is hard to fully unit-test without a seam. Add a seam: allow injecting the loader. Test that two concurrent `getModel()` calls trigger the loader exactly once:
```dart
test('concurrent getModel calls initialize the model once', () async {
  var loads = 0;
  final provider = InferenceModelProvider(
    loader: ({int? maxTokens}) async {
      loads++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return MockInferenceModel();
    },
  );
  await Future.wait([provider.getModel(), provider.getModel()]);
  expect(loads, 1);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/services/inference_model_provider_test.dart`
Expected: FAIL — no injectable loader; and current code can double-load under concurrency.

- [ ] **Step 3: Add a loader seam + memoize the in-flight future**

In `lib/services/inference_model_provider.dart`, add a typedef and optional constructor loader, memoize the `Future`, and dispose on `clearCache`:
```dart
typedef InferenceModelLoader = Future<InferenceModel> Function({int? maxTokens});

class InferenceModelProvider {
  InferenceModelProvider({InferenceModelLoader? loader})
      : _loader = loader ??
            (({int? maxTokens}) =>
                FlutterGemma.getActiveModel(maxTokens: maxTokens ?? 1024));

  final InferenceModelLoader _loader;
  InferenceModel? _model;
  Future<InferenceModel>? _inFlight;

  Future<InferenceModel> getModel() async {
    final current = _model;
    if (current != null) return current;
    return _inFlight ??= _load();
  }

  Future<InferenceModel> _load() async {
    try {
      final settings = locator<RagSettingsService>();
      final userMaxTokens = settings.maxTokens;
      final maxTokens = userMaxTokens ??
          ModelConfig.allModels
              .firstWhere((m) => m.type == AppModelType.inference,
                  orElse: () => InferenceModels.gemma3_270M)
              .maxTokens;
      final loaded = await _loader(maxTokens: maxTokens);
      _model = loaded;
      return loaded;
    } catch (e) {
      throw Exception(
        'Failed to get active inference model: $e. '
        'The model may still be downloading. Please wait and try again.',
      );
    } finally {
      _inFlight = null;
    }
  }

  void clearCache() {
    // Dispose the old native session before dropping the handle to avoid leaks.
    final old = _model;
    if (old is dynamic) {
      try {
        (old as dynamic)?.close();
      } catch (_) {}
    }
    _model = null;
    _inFlight = null;
  }
}
```
> Note: confirm the actual dispose method on `InferenceModel` in flutter_gemma 1.2.1 (it may be `close()`, `dispose()`, or none). Use the real one; if none exists, drop the dispose call and note it in a comment. Keep imports (`flutter_gemma`, `app.locator`, `model_config`, `rag_settings_service`).

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/services/inference_model_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/inference_model_provider.dart test/services/inference_model_provider_test.dart
git commit -m "fix(models): memoize in-flight init and dispose old model on clearCache"
```

---

## Task 12: Wrap VectorStore.initialize() DB open (M-10) + log contextualization failures (M-11)

**Shape:** Error-handling (M-10 verify via structure; M-11 verify via log call). Batched — both are small error-surfacing fixes in the search/ingest path.

**Files:**
- Modify: `lib/services/vector_store.dart` (`initialize` `:73-88`)
- Modify: `lib/services/contextual_retrieval_service.dart` (`generateChunkContext` catch `:103-106`)

**Why:** M-10: IO/permission failure on `sqlite3.open` crashes init opaquely. M-11: `on Exception catch (_) { return ''; }` silently loses context enrichment with no log.

- [ ] **Step 1: Surface a typed init error (M-10)**

In `lib/services/vector_store.dart`, wrap the open in `initialize()` (`:77-80`):
```dart
    final dbPath = await path_helper.getDatabasePath('vectors.db');
    try {
      _db = sqlite3.open(dbPath);
    } catch (e) {
      throw StateError('Failed to open vector database at $dbPath: $e');
    }
    _onCreate();
```
(This lets `RagService.initialize` / startup surface a degraded-mode error instead of an opaque crash.)

- [ ] **Step 2: Log contextualization failures (M-11)**

In `lib/services/contextual_retrieval_service.dart`, add the logging import and log in the catch (`:103-106`):
```dart
    } on Exception catch (e, stack) {
      LoggingService.error(
        'Failed to generate chunk context; falling back to no context',
        name: 'ContextualRetrievalService',
        error: e,
        stackTrace: stack,
      );
      return '';
    }
```
Add at top: `import 'package:offline_sync/services/logging_service.dart';`

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/services/vector_store.dart lib/services/contextual_retrieval_service.dart && flutter test test/services/vector_store_test.dart test/services/contextual_retrieval_service_test.dart`
Expected: analyze clean; tests green.

- [ ] **Step 4: Commit**

```bash
git add lib/services/vector_store.dart lib/services/contextual_retrieval_service.dart
git commit -m "fix: surface DB-open failure; log contextualization fallbacks"
```

---

## Task 13: Guard ModelManagementService.initialize() idempotency (M-28)

**Shape:** Lifecycle (unit test).

**Files:**
- Modify: `lib/services/model_management_service.dart` (`initialize` `:75-143`)
- Modify: `lib/ui/views/settings/settings_viewmodel.dart:74` (don't re-run full init)
- Test: `test/services/model_management_service_test.dart`

**Why:** `initialize()` has no idempotency/concurrency guard; `settings_viewmodel.dart:74` calls `unawaited(_modelService.initialize())` on **every** Settings navigation, re-running `_activate*Model` and re-invoking native `FlutterGemma.install*` concurrently with startup → wasted reloads and possible plugin-state races.

**Interfaces:**
- Produces: a memoized `Future<void>? _initialization` guarding `initialize()`.

- [ ] **Step 1: Write the failing test**

Add to `test/services/model_management_service_test.dart` a test that calls `initialize()` twice and asserts the expensive work runs once. Since `FlutterGemma` is static, assert idempotency behaviorally — e.g. the second call returns the same future / completes without re-notifying beyond the first. A pragmatic assertion:
```dart
test('initialize is idempotent (second call is a no-op await)', () async {
  final first = service.initialize();
  final second = service.initialize();
  expect(identical(first, second), isTrue);
  await Future.wait([first, second]);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/services/model_management_service_test.dart`
Expected: FAIL — two distinct futures.

- [ ] **Step 3: Memoize initialization**

In `lib/services/model_management_service.dart`, add a field near `_activeDownloads` (`:55`):
```dart
  Future<void>? _initialization;
```
Rename the existing body to `_doInitialize()` and make `initialize()` memoize:
```dart
  Future<void> initialize() => _initialization ??= _doInitialize();

  Future<void> _doInitialize() async {
    // ... existing body of initialize() (lines 76-142) ...
  }
```
(Keep the existing body verbatim inside `_doInitialize`.)

- [ ] **Step 4: Stop Settings from re-running full init**

In `lib/ui/views/settings/settings_viewmodel.dart`, `setup()` (`:70-77`) calls `unawaited(_modelService.initialize())`. With memoization this is now safe (returns the same future), but Settings only needs current model state, which the stream already provides. Leave the memoized call (it is now a no-op after startup) and add a clarifying comment:
```dart
    // Safe: initialize() is memoized; this no-ops after startup already ran it.
    unawaited(_modelService.initialize());
```

> **Interaction with retry (Task 2):** memoizing `initialize()` means `runStartupLogic()`'s `await _modelService.initialize()` (`startup_viewmodel.dart:129`) returns the **same cached future** on every `retry()` — it will not re-run the installed-model re-check. This is acceptable because retry's actual recovery is `resetErroredModels()` + the subsequent `downloadModel()` calls (which are **not** memoized), not re-running `initialize()`. If a future requirement needs `initialize()` to genuinely re-run on retry, expose a `reinitialize()` that clears `_initialization` first — but do **not** wire that now; the current retry path recovers without it. Note this in a comment on `retry()`.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `flutter test test/services/model_management_service_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/model_management_service.dart lib/ui/views/settings/settings_viewmodel.dart test/services/model_management_service_test.dart
git commit -m "fix(models): memoize initialize() to prevent re-init races from Settings"
```

---

## Task 14: Propagate typed AuthenticationRequiredException instead of substring matching (M-20) + orElse on model recommendation (M-21)

**Shape:** Logic (unit test on startup_viewmodel). Batched — both harden the startup error path.

**Files:**
- Modify: `lib/ui/views/startup/startup_viewmodel.dart` (`:64,83,175` 401 substring; `:139-142,194-198` firstWhere without orElse)
- Modify: `lib/services/model_management_service.dart` (emit typed exception where 401 is detected, `:309-317`)
- Reference: `lib/services/exceptions.dart` (`AuthenticationRequiredException`, already used in `chat_viewmodel.dart:204`)
- Test: `test/ui/views/startup/startup_viewmodel_test.dart`

**Why:** Auth-required is inferred from `errorMessage?.contains('401')` — fragile. A typed `AuthenticationRequiredException` already exists. And `firstWhere` without `orElse` (`:139-142,194-198`) throws `StateError` on catalog/recommendation drift → opaque startup failure.

- [ ] **Step 1: Add orElse fallbacks (M-21) — write failing test first**

Add to `test/ui/views/startup/startup_viewmodel_test.dart` a test where the recommended model id is not in `_modelService.models`; assert startup sets a user-facing error rather than throwing `StateError`. Then implement: in `startup_viewmodel.dart`, the two `firstWhere((m) => m.id == …)` on `_modelService.models` (`:139-142` and `:194-198`) get an `orElse`:
```dart
      final inferenceModel = _modelService.models.firstWhere(
        (m) => m.id == recommended.inferenceModel.id,
        orElse: () {
          throw StateError('Recommended inference model not in catalog');
        },
      );
```
Better: catch drift and surface a message. Wrap the lookups in the existing `try` and, on `StateError`, `setError('Model catalog mismatch — please update the app.')`. Implement whichever keeps startup non-crashing; the test asserts `hasError` is true and no unhandled exception.

- [ ] **Step 2: Emit typed exception on 401 (M-20)**

In `lib/services/model_management_service.dart`, where 401 is detected (`:309-313`), in addition to the error message, add the typed error so listeners can branch on type. Keep backward-compatible string but add:
```dart
      if (errorMsg.contains('401')) {
        model.status = ModelStatus.error;
        _statusController.addError(
          AuthenticationRequiredException('Unauthorized (401). Please check your HF Token.'),
        );
      }
```
Import `package:offline_sync/services/exceptions.dart`. **Do not** prefix with `const` — `AuthenticationRequiredException`'s constructor (`exceptions.dart:2-3`) is **not** `const` (`AuthenticationRequiredException([this.message = 'Authentication required']);`), so `const` is a compile error. (Alternatively, make that constructor `const` in `exceptions.dart` and keep `const` here — but the non-const form above is the smaller change.) In `startup_viewmodel.dart`, in the stream `onError` (`:81-89`) and status handler, branch on `e is AuthenticationRequiredException` instead of (or in addition to) `msg.contains('401')`:
```dart
      onError: (Object e) {
        if (e is AuthenticationRequiredException || e.toString().contains('401')) {
          _needsToken = true;
          setError('Authentication Failed (401)');
        } else {
          setError(e.toString());
        }
      },
```
(Confirm `AuthenticationRequiredException`'s constructor signature in `exceptions.dart` and match it.)

- [ ] **Step 3: Run tests**

Run: `flutter test test/ui/views/startup/startup_viewmodel_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/views/startup/startup_viewmodel.dart lib/services/model_management_service.dart test/ui/views/startup/startup_viewmodel_test.dart
git commit -m "fix(startup): typed auth exception + orElse fallbacks on model lookup"
```

---

## Phase 3 completion gate

- [ ] All 14 tasks committed.
- [ ] `flutter test` → all green; new test files exist for chat_viewmodel, document_library_viewmodel, document_detail_viewmodel, inference_model_provider.
- [ ] `flutter analyze` → 0 errors, 0 warnings.
- [ ] Manual driver check (superpowers:verification-before-completion): send a chat message, navigate away mid-stream, return — no duplicate messages, no runaway inference.
- [ ] Proceed to [Phase 4 — Scale & Quality](2026-07-07-prod-phase4-scale-quality.md).
