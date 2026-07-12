import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/embedding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmbeddingService -', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'surfaces a clear error when no active embedder is configured',
      () async {
        await FlutterGemma.clearActiveEmbeddingIdentity();
        final service = EmbeddingService();

        await expectLater(
          () => service.generateEmbedding('test query'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('No active embedding model set'),
            ),
          ),
        );
      },
    );
  });
}
