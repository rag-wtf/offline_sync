import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized authentication token management service.
/// Uses secure storage (Keychain on iOS, KeyStore on Android)
/// for token encryption.
class AuthTokenService {
  // Private constructor to prevent instantiation
  AuthTokenService._();

  static const String _authTokenKey = 'auth_token';
  static const _storage = FlutterSecureStorage();

  /// Load the stored HuggingFace authentication token.
  ///
  /// Returns the token string if found, or null if no token is saved.
  /// Priority: 1) FlutterSecureStorage,
  ///           2) SharedPreferences (legacy, will migrate),
  ///           3) Environment Variable (HUGGINGFACE_TOKEN)
  static Future<String?> loadToken() async {
    // Try secure storage first
    var token = await _storage.read(key: _authTokenKey);

    if (token == null || token.isEmpty) {
      // Check legacy SharedPreferences and migrate if found
      final prefs = await SharedPreferences.getInstance();
      final legacyToken = prefs.getString(_authTokenKey);

      if (legacyToken != null && legacyToken.isNotEmpty) {
        // Migrate to secure storage
        await _storage.write(key: _authTokenKey, value: legacyToken);
        await prefs.remove(_authTokenKey); // Remove from insecure storage
        token = legacyToken;
      }
    }

    // Fallback to environment variable if not in storage
    if (token == null || token.isEmpty) {
      const envToken = String.fromEnvironment('HUGGINGFACE_TOKEN');
      if (envToken.isNotEmpty) {
        // Auto-save environment token for persistence
        await _storage.write(key: _authTokenKey, value: envToken);
        return envToken;
      }
    }

    return token;
  }

  /// Save a HuggingFace authentication token securely.
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _authTokenKey, value: token);
  }

  /// Clear the stored authentication token.
  static Future<void> clearToken() async {
    await _storage.delete(key: _authTokenKey);

    // Also clear from legacy SharedPreferences if present
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
  }

  /// Check if a token exists.
  static Future<bool> hasToken() async {
    final token = await _storage.read(key: _authTokenKey);
    return token != null && token.isNotEmpty;
  }
}
