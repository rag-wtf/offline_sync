# Web deployment

- Treat `@mediapipe/tasks-genai@0.10.25` as requiring `SharedArrayBuffer` for this app's web inference path; the pinned MediaPipe GenAI `LlmInference` runtime should be deployed behind cross-origin isolation, and the local `web/coi-serviceworker.js` shim is included for static hosts that cannot set `COOP`/`COEP` headers directly.

## Deployment notes

- `web/coi-serviceworker.js` must be served from the same origin as `index.html` and loaded as the first script in `<head>`.
- The shim is for static hosting scenarios such as GitHub Pages. HTTPS or `localhost` is still required for service worker registration.
- Prefer real `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers when the host can set them. Keep the shim for static-host fallback unless the deployment path guarantees those headers.

## Manual browser verification

1. Build the production web app:
   ```bash
   rtk flutter build web --release --target lib/main_production.dart
   ```
2. Serve the generated site from `build/web` on `localhost` or deploy it to the target HTTPS host.
3. Open the app in a browser, wait for the first service-worker-controlled reload, then run this in DevTools:
   ```js
   crossOriginIsolated === true && typeof SharedArrayBuffer !== 'undefined'
   ```
4. Expected result: `true`.
