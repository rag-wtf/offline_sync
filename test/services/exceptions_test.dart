import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/exceptions.dart';

void main() {
  test(
    'AuthenticationRequiredException exposes default and custom messages',
    () {
      expect(
        AuthenticationRequiredException().toString(),
        'AuthenticationRequiredException: Authentication required',
      );
      expect(
        AuthenticationRequiredException('token missing').toString(),
        'AuthenticationRequiredException: token missing',
      );
    },
  );
}
