# Production Readiness Remediation — Master Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve all 75 findings from `docs/production-audit.md` (2026-07-07) so the app is release-ready across Android, iOS, and web, with a scalable, robust RAG core.

**Architecture:** The work is split into four phase files, matching the audit's own "Suggested Remediation Order." Each phase produces working, testable software on its own and is gated by its own review. Execute them **in order** — later phases assume earlier fixes are in place (e.g. Phase 4's scale work assumes Phase 1's CI test-gate exists to catch regressions).

**Tech Stack:** Flutter ^3.35 / Dart ^3.9 · Stacked MVVM + get_it · sqlite3 (FTS5) · flutter_gemma 1.2.1 · mocktail tests · GitHub Actions CI.

---

## How task shapes differ (READ FIRST)

Not every task uses the same test cycle. The audit's findings fall into four shapes; each task is tagged with its shape. **Do not fake a `flutter test` for a config/legal task.**

| Shape | Verification step is… | Applies to |
|---|---|---|
| **Logic** | A real failing→passing `flutter test` | C-4, H-4, H-6, M-3, M-5, M-6, M-9, M-13, M-22, L-10, L-11, L-22, L-23, L-24 |
| **Lifecycle** | A test with a fake broadcast stream/subscription where feasible; otherwise a documented manual-driver check | H-5, H-7, H-8, H-9, H-10, H-11, H-15, M-7, M-8, M-10, M-11, M-28 |
| **Config/CI/platform** | A build / inspect / `apksigner verify` / `flutter analyze` command — **never** a unit test | C-1, C-2, H-12, H-14, H-16, H-17, M-2, M-16, M-17, M-23, M-24, M-27, M-29, L-1, L-2, L-5, L-6, L-21, L-25, L-27, L-28, L-29, L-26 |
| **Decision** | A written, committed decision in `docs/` — no code | M-26 (Syncfusion license), plus the policy calls embedded in M-2/M-29/L-1 |

Remaining findings (C-3, H-1, H-2, H-3, H-13, M-1, M-12, M-14, M-15, M-25, L-3, L-4, L-7, L-8, L-9, L-14, L-15, L-16, L-17, L-18, L-19, L-20, M-20, M-21) are refactors/perf; each states its own verification.

## Global Constraints

Copied verbatim from the audit and stack; every task's requirements implicitly include these.

- **Framework floors:** Flutter `^3.35.0`, Dart SDK `^3.9.0` (`pubspec.yaml:6-8`). Do not raise these without a task that says so.
- **Public API unchanged** unless a task explicitly changes it (the audit was audit-only; this plan may change internals freely but keep service constructor signatures stable where tests depend on them).
- **Analyzer clean:** `flutter analyze` must end at **0 errors, 0 warnings**. The 8 pre-existing infos may only shrink, never grow.
- **Tests stay green:** the suite is **124 passing** today. Every task ends with the full suite (or the task's targeted tests) green. Never commit red.
- **SQL stays parameterized:** all dynamic SQL uses `?` placeholders (a verified positive finding). Never interpolate user input into SQL.
- **Offline-first:** no new network dependency beyond model downloads (HTTPS-only) and the already-present web CDN runtimes (which Phase 1 hardens).
- **Commit style:** Conventional Commits. One commit per task (or per step where the plan says commit). End commit messages with the Co-Authored-By line the harness requires.
- **Delete `test_output.txt`** at repo root during Phase 1 housekeeping — it is a stale pre-refactor artifact (audit Verification Status).

## Working-tree note (reconciled 2026-07-07)

The branch `no-sync` has uncommitted edits. Reconciled against current source before writing:
- `document_parser_service.dart` — only `p.basename` import added; **C-4 defect at line 137 (`String.fromCharCodes`) is intact.**
- `chat_viewmodel.dart` / `document_library_viewmodel.dart` — only a `FilePicker.pickFiles` API migration; **H-6, H-7, H-11, H-15 defects are intact.**
- `pubspec.yaml` — `file_picker ^12.0.0-beta.7` (M-27), `syncfusion_flutter_pdf ^33.2.13` (M-26), `logger: any` / `stacked_shared: any` / `path_provider_platform_interface: any` (L-6), `sqlite3_flutter_libs ^0.6.0+eol` (L-29) all present. Version `1.0.0+1` (H-12).

Line numbers in the phase files were re-verified against the current working tree, not the audit snapshot.

---

## Phases

1. **[Release Blockers](2026-07-07-prod-phase1-release-blockers.md)** — *hours.* C-1, C-2, H-12, H-14, H-16, H-17, M-23, M-24, plus config housekeeping (L-6, L-21, L-25, L-27, L-28, L-29) and deleting `test_output.txt`. **Outcome:** Android/iOS artifacts install; CI gates every release on analyze+test; web SAB requirement resolved.
2. **[Data Integrity](2026-07-07-prod-phase2-data-integrity.md)** — *≈1 day.* H-13 (stamp `PRAGMA user_version` **before first ship**), C-4 (DOCX encoding), M-9 (embedding-dim guard), L-23 (null-safe `Document.fromJson`), M-22 (dedup race), M-1 (model checksums), M-2 (secure-storage hardening), M-26 (Syncfusion license decision). **Outcome:** no silent data corruption; upgrades are migratable.
3. **[Stability](2026-07-07-prod-phase3-stability.md)** — *days.* Listener leaks + races (H-15, H-5, H-6, H-7), timeouts (H-1), error-handling dead-ends (H-8, H-9, H-10, H-11, M-10, M-11), resource leaks (M-7, M-8), init guard (M-28), typed-exception cleanup (M-20, M-21, L-15). **Outcome:** no hangs, no permanent spinners, no accumulating listeners.
4. **[Scale & Quality](2026-07-07-prod-phase4-scale-quality.md)** — *next iteration.* Vector-scan fix (C-3), serial-LLM fixes (H-2, H-3), ranking bugs (H-4, M-5), token-budget correctness (M-3, M-6, M-12, M-13), ingestion memory (M-14, M-15, M-16), settings wiring + dead-code deletion (M-25, M-17), platform privacy (M-29), l10n + remaining Lows, and the critical-path test coverage the audit flagged. **Outcome:** scales to real corpora; retrieval ranking correct.

## Coverage checklist (all 75 findings mapped)

- **Phase 1:** C-1, C-2, H-12, H-14, H-16, H-17, M-23, M-24, L-6, L-21, L-25, L-27, L-28, L-29
- **Phase 2:** H-13, C-4, M-9, L-23, M-22, M-1, M-2, M-26
- **Phase 3:** H-15, H-5, H-6, H-7, H-1, H-8, H-9, H-10, H-11, M-7, M-8, M-10, M-11, M-28, M-20, M-21, L-15
- **Phase 4:** C-3, H-2, H-3, H-4, M-3, M-5, M-6, M-12, M-13, M-14, M-15, M-16, M-17, M-19, M-25, M-27, M-29, L-1, L-2, L-3, L-4, L-5, L-7, L-8, L-9, L-14, L-16, L-17, L-18, L-19, L-20, L-24, L-10, L-11, L-22, L-26 + test coverage

Every audit ID appears in exactly one phase. (M-27 and M-29 are cross-referenced from Phase 1/2 but their fixes live in Phase 4 alongside related dependency/privacy work. **M-19** — deprecated `PlatformFile.bytes` — is resolved inside Phase 4 Task 11 as part of the stable `file_picker` migration.)

> Audit ID note: the audit skips M-4 and M-18 (downgraded to L-22 and L-23 during verification) and L-12/L-13 (never assigned). The 75 live IDs are C-1..C-4, H-1..H-17, the 27 M-* listed above, and the 27 L-* listed above — all mapped here.
