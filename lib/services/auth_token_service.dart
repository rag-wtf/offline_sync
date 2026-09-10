import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized authentication token management service.
/// Uses secure storage (Keychain on iOS, KeyStore on Android)
/// for token encryption, with fallback to SharedPreferences if
/// the platform secure storage service is unavailable.
class AuthTokenService {
  // Private constructor to prevent instantiation
  AuthTokenService._(); // coverage:ignore-line

  static const String _authTokenKey = 'auth_token';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Load the stored HuggingFace authentication token.
  ///
  /// Returns the token string if found, or null if no token is saved.
  /// Priority: 1) FlutterSecureStorage,
  ///           2) SharedPreferences (legacy/fallback),
  ///           3) Environment Variable (HUGGINGFACE_TOKEN)
  static Future<String?> loadToken() async {
    // Try secure storage first
    String? token;
    try {
      token = await _storage.read(key: _authTokenKey);
    } on Object catch (e) {
      LoggingService.warning(
        'Failed to read auth token from secure storage: $e',
      );
    }

    if (token == null || token.isEmpty) {
      // Check SharedPreferences and migrate if found
      final prefs = await SharedPreferences.getInstance();
      final legacyToken = prefs.getString(_authTokenKey);

      if (legacyToken != null && legacyToken.isNotEmpty) {
        // Migrate to secure storage if available
        try {
          await _storage.write(key: _authTokenKey, value: legacyToken);
          await prefs.remove(_authTokenKey); // Remove from insecure storage
        } on Object catch (e) {
          LoggingService.warning(
            'Failed to migrate auth token to secure storage: $e',
          );
        }
        token = legacyToken;
      }
    }

    // Fallback to environment variable if not in storage
    if (kDebugMode && (token == null || token.isEmpty)) {
      const envToken = String.fromEnvironment('HUGGINGFACE_TOKEN');
      if (envToken.isNotEmpty) {
        // Auto-save environment token for persistence
        // coverage:ignore-start
        try {
          await _storage.write(key: _authTokenKey, value: envToken);
        } on Object catch (_) {}
        return envToken;
        // coverage:ignore-end
      }
    }

    return token;
  }

  /// Save a HuggingFace authentication token securely, or fall back to
  /// SharedPreferences if secure storage is unavailable.
  static Future<void> saveToken(String token) async {
    try {
      await _storage.write(key: _authTokenKey, value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_authTokenKey);
    } on Object catch (e) {
      LoggingService.warning(
        'Failed to save auth token to secure storage, '
        'falling back to SharedPreferences: $e',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_authTokenKey, token);
    }
  }

  /// Clear the stored authentication token.
  static Future<void> clearToken() async {
    try {
      await _storage.delete(key: _authTokenKey);
    } on Object catch (e) {
      LoggingService.warning(
        'Failed to delete auth token from secure storage: $e',
      );
    }

    // Also clear from SharedPreferences if present
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
  }

  /// Check if a token exists.
  static Future<bool> hasToken() async {
    try {
      final token = await _storage.read(key: _authTokenKey);
      if (token != null && token.isNotEmpty) return true;
    } on Object catch (e) {
      LoggingService.warning(
        'Failed to check auth token in secure storage: $e',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final fallbackToken = prefs.getString(_authTokenKey);
    return fallbackToken != null && fallbackToken.isNotEmpty;
  }
}
