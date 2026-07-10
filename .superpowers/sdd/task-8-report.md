# Task 8 Report: Fix macOS LiteRT-LM JAR discovery + pin web JS runtime (M-24)

## Scope worked

- `.github/workflows/release.yaml`
- `web/index.html`
- `docs/web-deployment.md`
- `web/` runtime asset files sourced from the installed `flutter_gemma 1.2.1` package build output

No unrelated repo files were edited. `.gitignore` was left untouched.

## What changed

### 1. macOS LiteRT-LM JAR discovery

Replaced the `Pre-build LiteRT-LM JAR` step body in `.github/workflows/release.yaml` with the exact task-brief logic:

- search `$HOME/.pub-cache/hosted/pub.dev` first
- fall back to `$HOME/.pub-cache/git`
- fail with `::error::` and `exit 1` when `macos/litertlm-server` is missing

This removes the previous hosted-cache miss plus warning-only behavior.

### 2. Web runtime reconciliation for `flutter_gemma 1.2.1`

Updated `web/index.html` to:

- preserve `coi-serviceworker.js` as the first script in `<head>`
- remove the obsolete `DenisovAV/flutter_gemma@0.12.0` CDN imports
- pin MediaPipe from `@mediapipe/tasks-genai@0.10.25` to `@mediapipe/tasks-genai@0.10.27`
- self-host the embedding runtime via:
  - `cache_api.js`
  - `litert_embeddings.js`

I did **not** add the LiteRT-LM web handshake (`window.litertLmReady` with `@litert-lm/core@0.12.1/+esm`) because this app's current web inference models are `.task` models, not web `.litertlm` models.

### 3. Self-hosted runtime assets

Directly practical self-hosting was completed by building the installed package's web RAG runtime and copying the generated browser-ready outputs into `web/`:

- `web/cache_api.js`
- `web/litert_embeddings.js`
- `web/litert.js`
- `web/sentencepiece.js`
- `web/tensorflow.js`
- `web/wasm/*`

`web/litert_embeddings.js` was adjusted to default its WASM path to `/wasm/` so it matches the vendored runtime layout in this app.

I did **not** keep `sqlite_vector_store.js` from the old CDN. The app uses its own SQLite bootstrap path through `lib/bootstrap_web.dart` and local `web/sqlite3.wasm`, so the stale package vector-store script was not justified.

### 4. Deployment docs

Updated `docs/web-deployment.md` to record:

- MediaPipe pin `@mediapipe/tasks-genai@0.10.27`
- removal of the old `0.12.0` GitHub CDN scripts
- the self-hosted `flutter_gemma 1.2.1` embedding runtime files now shipped under `web/`
- the remaining CDN risk for MediaPipe
- the future LiteRT-LM web handshake requirement if `.litertlm` web inference is adopted

## Package evidence used

From `/home/limcheekin/.pub-cache/hosted/pub.dev/flutter_gemma-1.2.1/README.md`:

- MediaPipe web import should use `@mediapipe/tasks-genai@0.10.27`
- LiteRT-LM web import should use `@litert-lm/core@0.12.1/+esm` via `window.litertLmReady`
- sqlite RAG uses a package web asset `web/rag/sqlite3.wasm` and no CDN script

From the installed package contents:

- `web/cache_api.js` exists directly
- `web/rag/litert_embeddings_api.js` and its Vite build config exist
- `web/rag/dist/*` was generated locally from the installed package and used as the source for vendored browser assets

## Verification run

### YAML parse

Command:

```bash
rtk python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yaml')); print('YAML OK')"
```

Result:

- `YAML OK`

### Web build

Command:

```bash
rtk flutter build web --release --target lib/main_production.dart
```

Result:

- build succeeded
- output: `✓ Built build/web`

Additional build observations:

- Flutter emitted wasm dry-run warnings about `sqlite3`/`ffi` packages and `dart:ffi` not being wasm-compatible without experimental support
- Flutter also emitted a warning about expected `CupertinoIcons` fonts not being found

These were warnings only; they did not block the release web build for this task.

### Built output spot-check

Confirmed `build/web/index.html` now contains:

- `coi-serviceworker.js`
- local `cache_api.js`
- local `litert_embeddings.js`
- MediaPipe pinned to `@mediapipe/tasks-genai@0.10.27`

Confirmed the old `DenisovAV/flutter_gemma@0.12.0` and `@mediapipe/tasks-genai@0.10.25` references are gone from the built output.

## Commands run that matter

```bash
rtk python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yaml')); print('YAML OK')"
rtk flutter build web --release --target lib/main_production.dart
```

Package-local asset preparation:

```bash
rtk npm install --include=dev
rtk npm install @rollup/pluginutils
rtk npm run build
```

Those npm commands were run in:

```text
/home/limcheekin/.pub-cache/hosted/pub.dev/flutter_gemma-1.2.1/web/rag
```

to generate the vendored browser assets copied into this repo's `web/` directory.

## Concerns

1. The remaining web inference CDN dependency is `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27`. If jsDelivr is blocked or unavailable, `.task` inference on web will fail.
2. The `flutter build web` command succeeded, but it surfaced pre-existing wasm dry-run and `CupertinoIcons` warnings that are outside this task's ownership.
