{{flutter_js}}
{{flutter_build_config}}

// Intentionally omit Flutter serviceWorkerSettings so the COI shim remains
// the only app-scope service worker on static hosts.
_flutter.loader.load();
