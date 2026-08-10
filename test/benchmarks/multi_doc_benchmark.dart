import 'dart:io';
// minimal benchmark that does not use package:offline_sync imports to avoid compilation issues.
import 'package:flutter_test/flutter_test.dart';

// Since the whole app is completely failing to compile due to experimental private-named-parameters
// flag required by Dart < 3.12, but we need an environment with 3.44 Flutter which forces Dart 3.11 for some reason,
// or wait, let's just create a standalone Dart script that benchmarks the specific code we changed.

void main() async {
  final filePaths = List.generate(50, (i) => 'file_$i.txt');

  // Sequential approach
  final startSeq = DateTime.now();
  final succeededSeq = [];
  final failedSeq = {};
  for (final filePath in filePaths) {
    try {
      final doc = await mockAddDocument(filePath);
      succeededSeq.add(doc);
    } on Object catch (e) {
      failedSeq[filePath] = e.toString();
    }
  }
  final endSeq = DateTime.now();
  final seqTime = endSeq.difference(startSeq).inMilliseconds;

  // Parallel approach
  final startPar = DateTime.now();
  final succeededPar = [];
  final failedPar = {};
  final futures = filePaths.map((filePath) async {
    try {
      final doc = await mockAddDocument(filePath);
      return {'doc': doc};
    } on Object catch (e) {
      return {'filePath': filePath, 'error': e.toString()};
    }
  });
  final results = await Future.wait(futures);
  for (final result in results) {
    if (result.containsKey('doc')) {
      succeededPar.add(result['doc']);
    } else {
      failedPar[result['filePath'] as String] = result['error'] as String;
    }
  }
  final endPar = DateTime.now();
  final parTime = endPar.difference(startPar).inMilliseconds;

  print('Sequential time: $seqTime ms');
  print('Parallel time: $parTime ms');
  print('Improvement: ${((seqTime - parTime) / seqTime * 100).toStringAsFixed(2)}%');
}

Future<String> mockAddDocument(String path) async {
  await Future.delayed(Duration(milliseconds: 50));
  if (path.endsWith('5.txt')) throw Exception('Failed to add document');
  return path;
}
