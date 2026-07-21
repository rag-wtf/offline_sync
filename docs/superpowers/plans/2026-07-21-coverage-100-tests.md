# 100% Coverage Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `very_good test -j 4 --optimization --coverage --min-coverage 100 --report-on "lib" --show-uncovered --test-randomize-ordering-seed random` pass without adding top-of-file coverage exclusions.

**Architecture:** Increase coverage with behavior-focused tests across services, models, app shell, routing, bootstrap, plugin seams, viewmodels, and widgets. Add minimal testability seams only after a failing test proves a hardwired plugin/static/platform dependency prevents coverage.

**Tech Stack:** Flutter test, mocktail, stacked/get_it locator, Very Good CLI coverage.

## Global Constraints

- Do not add `// coverage:ignore-file` to any `lib/` file.
- Preserve the pre-existing user-owned change in `lib/services/model_management_service.dart`.
- Use `rtk` as the prefix for shell commands.
- Prefer codebase-memory MCP tools for code discovery; use file search for tests/config/coverage artifacts.
- Follow TDD: add failing tests first, then production-code seams only if required.
- Verification command is exactly `very_good test -j 4 --optimization --coverage --min-coverage 100 --report-on "lib" --show-uncovered --test-randomize-ordering-seed random`.

---

### Task 1: Pure models and service branch coverage

**Files:**
- Modify tests under `test/models/` and `test/services/`.
- Modify `lib/services/*` only for minimal injectable seams proven necessary by failing tests.

**Interfaces:**
- Consumes existing public service/model APIs.
- Produces increased line coverage for pure Dart files before UI/plugin work.

- [ ] Add focused tests for uncovered branches in `document.dart`, `model_config.dart`, `rag_token_manager.dart`, `auth_token_service.dart`, `reranking_service.dart`, `contextual_retrieval_service.dart`, `logging_service.dart`, `smart_chunker.dart`, `document_parser_service.dart`, `chat_repository.dart`, `vector_store.dart`, `rag_service.dart`, `document_management_service.dart`, and `model_recommendation_service.dart`.
- [ ] Run targeted test files and confirm new tests fail when asserting previously uncovered behavior, then pass after any required seam.
- [ ] Run the full coverage command and record remaining uncovered lines.

### Task 2: Plugin integration and bootstrap seams

**Files:**
- Modify `test/bootstrap_test.dart`, service tests for FlutterGemma/device/platform boundaries, and minimal `lib/` seams if required.

**Interfaces:**
- Consumes bootstrap functions and service constructors.
- Produces deterministic tests for platform/plugin-dependent paths.

- [ ] Cover `bootstrap.dart`, `bootstrap_mobile.dart`, `embedding_service.dart`, `inference_model_provider.dart`, `device_capability_service.dart`, and `model_management_service.dart` branches.
- [ ] Use MethodChannel mocks, constructor injection, or small adapter seams where direct plugin calls cannot run in widget tests.
- [ ] Run targeted tests, then the full coverage command.

### Task 3: App shell, router, viewmodel, and widget coverage

**Files:**
- Modify tests under `test/app/` and `test/ui/`.
- Modify UI/viewmodel code only when a failing widget/viewmodel test exposes a hardwired dependency that prevents deterministic coverage.

**Interfaces:**
- Consumes `MainApp`, generated router, views, widgets, and viewmodels through public widget APIs and locator registrations.
- Produces coverage for app shell, routing branches, settings/chat/document/startup UI, dialog, and viewmodels.

- [ ] Add widget tests for `main_app.dart`, `app_theme.dart`, `app.router.dart`, chat widgets/views, document detail/library views, settings view, startup view, token input dialog, and viewmodels.
- [ ] Pump widgets under `MaterialApp`/router with mock locator services and assert visible behavior for every state branch.
- [ ] Run targeted widget tests, then the full coverage command.

### Task 4: Close remaining uncovered lines

**Files:**
- Modify only tests and minimal proven seams needed for the current lcov remainder.

**Interfaces:**
- Consumes `coverage/lcov.info` from the latest full command.
- Produces an exact 100% passing coverage gate.

- [ ] Parse `coverage/lcov.info` after each full run.
- [ ] Add the smallest behavior-focused test for each remaining uncovered line.
- [ ] Stop only when the exact requested command exits 0.
