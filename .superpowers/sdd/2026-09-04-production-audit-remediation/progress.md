# SDD ledger — plan: docs/superpowers/plans/2026-09-04-production-audit-remediation.md

Setup: isolated worktree `production-audit-fixes` at `C:\dev\ws\flutter\offline_sync\.worktrees\production-audit-fixes`.

Preflight: generated l10n artifacts were required for the clean checkout; `flutter analyze` passed and `flutter test --coverage` passed 368/368 after generation. `flutter pub get` regenerated tracked platform registrants; those generated-only deltas were restored.

Ruling: The audit is the binding requirements source and the new plan is its execution decomposition — the audit contains concrete fixes but no task plan; cost if wrong: task boundaries may require review-loop rework.

Ruling: Desktop inference is restricted to `.litertlm`, web/mobile inference uses `.task` only where the registered engine supports it, and desktop recommendations pin to the compatible Litert model where no same-tier catalog variant exists — this preserves the release matrix while avoiding non-runnable downloads; cost if wrong: desktop tier choice may be less capable than intended.

Ruling: Adopt the audit's recommended no-backup posture for the database and model files, with Android manifest exclusion and iOS/macOS native exclusion markers — this matches the privacy promise; cost if wrong: users will not receive automatic backup/restore of local corpus and models.

Preflight task/interface scan is recorded in the plan under `Pre-flight task/interface scan`; no contradictory task pair or self-inconsistent task was found.

Task 1: fix round 1/5 (5 addressed, 0 open; prior review findings all approved; commits 49320f3..5f8d95e)
Task 1: complete (commits 337888c..5f8d95e, review clean)
Task 2: fix round 1/5 (7 addressed, 0 open; prior review findings all approved after required report artifact was added; commits c0efeab..74103c1)
Task 2: complete (commits 5f8d95e..74103c1, review clean)
Task 3: fix round 1/5 (5 addressed, 0 open after re-review except L-7; commits 804d310..924f6c5)
Task 3: fix round 2/5 (1 addressed, 0 open; commit 924f6c5..dc69595)
Task 3: complete (commits 74103c1..dc69595, review clean)
Task 4: fix round 1/5 (initial remediation reviewed with compile and correctness gaps; commits 7e174e1..6aaa2d9)
Task 4: fix round 2/5 (duplicate declaration compile blockers addressed; commit 978e07d)
Task 4: fix round 3/5 (remaining lifecycle, filtering, atomicity, rollback, disposal, redaction, and report gaps addressed; commit 89963c5)
Task 4: fix round 4/5 (7 findings open: clean-checkout l10n generation, analyzer gate, coverage gate, no-prior-model rollback, serialized deletion/disposal, refresh serialization, and fixture cleanup)
Task 4: fix round 5/5 (Terra review left 3 findings: coverage below 95%, inference deletion/load race, and root-relative failure fixtures)
Task 4: Terra final review NOT READY solely for coverage (4496/4770 = 94.26%); carry the required meaningful coverage tests into Task 6, then re-review Task 4 before completion.
Task 5: fix round 1/5 (Terra found bootstrap retry re-registration and flavor-insensitive macOS identity gate; commit f0a16b9)
Task 5: fix round 2/5 (retry reset and flavor-aware identity gate addressed; commit b2d8d04)
Task 5: fix round 3/5 (L-8 PWA title mismatch addressed in follow-up)
Task 5: complete (commits f0a16b9..a273524, Terra review READY)
Task 6: implementation complete (commit 9aaf6a9; coverage 4660/4918 = 94.754%, awaiting Terra review and carry-over coverage fix)
Task 6: fix round 1/5 (Terra found 13-line coverage shortfall and unreachable AuthenticationRequiredException catch in active chat flow; commit 9aaf6a9)
Task 6: implementation complete; addressed L-1, L-2, L-15, L-18, and added meaningful coverage tests. Full suite passed 495/495; exact LCOV is 4660/4918 (94.754%), below the unchanged 95% CI gate by 13 covered lines. Report: `task-6-report.md`.
Task 6: fix round 2/5 (removed the unreachable streamed-RAG authentication catch and fabricated tests; added meaningful model/chat/settings coverage; commit 165a150)
Task 6: complete (commits 9aaf6a9..165a150; local verification clean: 496 tests, LCOV 4668/4911 = 95.052%, analyzer/ARB/cspell/config/web/Android/diff checks passed; Terra re-review connector unavailable for this resumed pass)
