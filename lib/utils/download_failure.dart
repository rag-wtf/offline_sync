import 'package:flutter_gemma/flutter_gemma.dart';

/// Whether [error] is Hugging Face refusing the request for auth reasons:
/// no token, a token without the gated-repo scope, or a licence the account
/// has not accepted on the repo being downloaded.
bool isGatedAccessError(Object error) {
  if (error is DownloadException) {
    return switch (error.error) {
      UnauthorizedError() || ForbiddenError() => true,
      _ => false,
    };
  }

  final message = error.toString().toLowerCase();
  final hasAuthStatus = message.contains('401') ||
      message.contains('403') ||
      message.contains('unauthorized') ||
      message.contains('forbidden');
  final looksGated = message.contains('gated') ||
      message.contains('restricted') ||
      message.contains('authentication required') ||
      message.contains('authenticated') ||
      message.contains('access denied');
  return hasAuthStatus && looksGated;
}

/// A message the user can act on.
String describeDownloadFailure(Object error, {required String repoPage}) {
  if (!isGatedAccessError(error)) return 'The download failed: $error';
  return 'Hugging Face refused the download. Check all three:\n'
      '1. You accepted the licence on $repoPage — accepting it on another '
      'Gemma repo does not count.\n'
      '2. The token belongs to the same account that accepted it.\n'
      '3. A fine-grained token also needs "Read access to the contents of all '
      'public gated repos you can access".';
}
