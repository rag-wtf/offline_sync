import 'package:shared_preferences/shared_preferences.dart';

/// Centralized authentication token management service.
class AuthTokenService {
  // Private constructor to prevent instantiation
  AuthTokenService._();

  static const String _authTokenKey = 'auth_token';

  /// Load the stored HuggingFace authentication token.
  ///
  /// Returns the token string if found, or null if no token is saved.
  /// Priority: 1) SharedPreferences,
  ///           2) Environment Variable (HUGGINGFACE_TOKEN)
  static Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authTokenKey);

    // Fallback to environment variable if not in SharedPreferences
    if (token == null || token.isEmpty) {
      const envToken = String.fromEnvironment('HUGGINGFACE_TOKEN');
      if (envToken.isNotEmpty) {
        // Auto-save environment token for persistence
        await prefs.setString(_authTokenKey, envToken);
        return envToken;
      }
    }

    return token;
  }

  /// Save a HuggingFace authentication token.
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authTokenKey, token);
  }

  /// Clear the stored authentication token.
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
  }

  /// Check if a token exists.
  static Future<bool> hasToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_authTokenKey);
  }
}
