import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/bootstrap_mobile.dart';

void main() {
  test('initializeSqlite completes', () async {
    await expectLater(initializeSqlite(), completes);
  });
}
