/// Exception thrown when authentication is required for model operations
class AuthenticationRequiredException implements Exception {
  AuthenticationRequiredException([this.message = 'Authentication required']);

  final String message;

  @override
  String toString() => 'AuthenticationRequiredException: $message';
}
