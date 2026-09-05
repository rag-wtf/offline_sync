import 'package:sqlite3/wasm.dart';

// Make the WASM sqlite3 instance globally accessible
late WasmSqlite3 _wasmSqlite3;
IndexedDbFileSystem? _fileSystem;

/// Gets the global sqlite3 instance for web
WasmSqlite3 get sqlite3 => _wasmSqlite3;

Future<void> initializeSqlite() async {
  // Initialize WASM SQLite for web
  _wasmSqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));

  // Use IndexedDB for persistent storage on web
  _fileSystem = await IndexedDbFileSystem.open(dbName: 'offline_sync_db');
  _wasmSqlite3.registerVirtualFileSystem(_fileSystem!, makeDefault: true);
}

Future<void> flushSqlite() async {
  await _fileSystem?.flush();
}
