# Web deployment

- Treat `@mediapipe/tasks-genai@0.10.27` as requiring `SharedArrayBuffer` for this app's web inference path; the pinned MediaPipe GenAI `LlmInference` runtime should be deployed behind cross-origin isolation, and the local `web/coi-serviceworker.js` shim is included for static hosts that cannot set `COOP`/`COEP` headers directly.

## Deployment notes

- `web/coi-serviceworker.js` must be served from the same origin as `index.html` and loaded as the first script in `<head>`.
- `web/flutter_bootstrap.js` intentionally omits Flutter `serviceWorkerSettings`, which prevents Flutter from registering `flutter_service_worker.js` and leaves `coi-serviceworker.js` as the sole app-scope service worker.
- The shim is for static hosting scenarios such as GitHub Pages. HTTPS or `localhost` is still required for service worker registration.
- Prefer real `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers when the host can set them. Keep the shim for static-host fallback unless the deployment path guarantees those headers.
- The old `DenisovAV/flutter_gemma@0.12.0` GitHub CDN scripts were removed. This app now self-hosts the `flutter_gemma 1.2.1` embedding runtime under `web/` (`cache_api.js`, `litert_embeddings.js`, `litert.js`, `sentencepiece.js`, `tensorflow.js`, and `web/wasm/*`), plus the package-provided `web/sqlite3.wasm` asset already used by `lib/bootstrap_web.dart`.
- The remaining pinned CDN runtime is `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27` for `.task` model inference. If that CDN is blocked, web inference will fail even though the rest of the app is self-hosted. Self-hosting the MediaPipe bundle was not sourced directly from the installed Dart package, so it remains an explicit deployment risk.
- This app's current web inference models are `.task` files, so the LiteRT-LM web handshake from the `flutter_gemma 1.2.1` docs (`window.litertLmReady` with `@litert-lm/core@0.12.1/+esm`) is not wired into `web/index.html`. If web `.litertlm` inference is added later, pin that import exactly as documented and treat it as another CDN dependency unless you vendor it separately.

## Manual browser verification

1. Build the production web app:
   ```bash
   rtk flutter build web --release --target lib/main_production.dart
   ```
2. Serve the generated site from `build/web` on `localhost` or deploy it to the target HTTPS host.
3. Open the app in a browser and wait for the first service-worker-controlled reload triggered by `coi-serviceworker.js`.
4. In DevTools, confirm the controlling worker is the COI shim:
   ```js
   navigator.serviceWorker.controller?.scriptURL
   ```
5. Expected result: the returned URL contains `coi-serviceworker.js`.
6. Run this in DevTools:
   ```js
   crossOriginIsolated === true && typeof SharedArrayBuffer !== 'undefined'
   ```
7. Expected result: `true`.
8. Reload the page one more time and rerun both checks:
   ```js
   navigator.serviceWorker.controller?.scriptURL
   crossOriginIsolated === true && typeof SharedArrayBuffer !== 'undefined'
   ```
9. Expected result after the extra reload: the controller still points to `coi-serviceworker.js`, and the isolation check still returns `true`.
