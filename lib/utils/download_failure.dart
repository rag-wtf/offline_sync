import 'package:flutter_gemma/flutter_gemma.dart';

/// Whether [error] is Hugging Face refusing the request for auth reasons:
/// no token, a token without the gated-repo scope, or a licence the account
/// has not accepted on the repo being downloaded.
bool isGatedAccessError(Object error) {
  if (error is DownloadException) {
    switch (error.error) {
      case UnauthorizedError():
      case ForbiddenError():
        return true;
      case UnknownError(:final message):
        return _isGatedErrorMessage(message);
      default:
        return false;
    }
  }

  return _isGatedErrorMessage(error.toString());
}

bool _isGatedErrorMessage(String rawMessage) {
  final message = rawMessage.toLowerCase();
  if (message.contains('proxy')) {
    return false;
  }

  if (message.contains('ensure you have access to the repository')) {
    return true;
  }

  final hasAuthStatus =
      message.contains('401') ||
      message.contains('403') ||
      message.contains('unauthorized') ||
      message.contains('forbidden');
  if (!hasAuthStatus) {
    return false;
  }

  final looksGated =
      message.contains('gated') ||
      message.contains('restricted') ||
      message.contains('authentication required') ||
      message.contains('authentication failed') ||
      message.contains('authenticated') ||
      message.contains('access denied') ||
      message.contains('invalid or expired token') ||
      message.contains('token lacks required permissions') ||
      message.contains('failed to download public model') ||
      message.contains('failed to fetch file: unauthorized') ||
      (message.contains('jsinteropexception') &&
          message.contains('unauthorized')) ||
      // Actual Web error when no "Unauthorized" word — only numeric status code.
      // e.g. "JsInteropException: Failed to fetch file:  (Status: 401)"
      (message.contains('jsinteropexception') && message.contains('401'));

  return looksGated;
}

/// A message the user can act on.
String describeDownloadFailure(Object error, {required String repoPage}) {
  if (!isGatedAccessError(error)) return 'The download failed: $error';
  return 'Hugging Face refused the download. Check all three:\n'
      '1. You accepted the licence on $repoPage — accepting it on a different '
      'repository does not count.\n'
      '2. The token belongs to the same account that accepted it.\n'
      '3. A fine-grained token also needs "Read access to the contents of all '
      'public gated repos you can access".';
}
