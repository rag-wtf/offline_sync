/// Platform-specific database path helper for web.
/// This stub is used on web platforms where IndexedDB handles persistence.
Future<String> getDatabasePath(String filename) async {
  // On web, use in-memory mode with IndexedDB persistence
  // The ':memory:' path tells sqlite3 WASM to use an in-memory database,
  // but the VFS registered in bootstrap_web.dart provides IndexedDB persistence
  return filename; // WASM sqlite3 with IndexedDB VFS uses the filename as key
}
