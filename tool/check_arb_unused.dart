import 'dart:convert';
import 'dart:io';

void main() {
  final arbFile = File('lib/l10n/arb/app_en.arb');
  if (!arbFile.existsSync()) {
    stderr.writeln('Missing ${arbFile.path}');
    exitCode = 2;
    return;
  }

  final arb = jsonDecode(arbFile.readAsStringSync()) as Map<String, dynamic>;
  final keys = arb.keys.where((key) => !key.startsWith('@')).toList();
  final separator = Platform.pathSeparator;
  final generatedPath = ['lib', 'l10n', 'gen'].join(separator) + separator;
  final arbPath = ['lib', 'l10n', 'arb'].join(separator) + separator;
  final sourceFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.dart') &&
            !file.path.contains(generatedPath) &&
            !file.path.contains(arbPath),
      );
  final source = sourceFiles.map((file) => file.readAsStringSync()).join('\n');
  final unused = keys
      .where(
        (key) => !RegExp(r'\b' + RegExp.escape(key) + r'\b').hasMatch(source),
      )
      .toList();

  if (unused.isNotEmpty) {
    stderr.writeln('Unused English ARB keys:');
    for (final key in unused) {
      stderr.writeln('  $key');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'ARB validation passed: ${keys.length} English keys are referenced.',
  );
}
