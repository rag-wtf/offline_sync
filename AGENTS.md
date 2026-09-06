# AGENTS.md 

When I correct you or catch you making a mistake, before continuing, add the lesson as a one-line rule under `## Lessons Learned` so it never happens again.

**Tradeoff:** Bias toward caution over speed. Trivial tasks: use judgment.

## Behavioral Guidelines

Reduce LLM coding mistakes.

- **Think Before Coding** — Surface assumptions, ambiguities, and simpler alternatives before implementing; ask rather than guess.
- **Simplicity First** — Write the minimum code that solves the stated problem, with no speculative features, abstractions, or error handling.
- **Surgical Changes** — Change only what the request requires, match existing style, and clean up only the orphans your own edits create.
- **Goal-Driven Execution** — Convert tasks into verifiable success criteria (usually tests) and state a brief plan with per-step verification for multi-step work.
- **Token Efficiency** — Use `gpt-5.6-luna` only as implementer, and `gpt-5.6-terra` only as reviewer by default, unless the user says otherwise.

## Lessons Learned
- Commit existing worktree changes before beginning new implementation work.
