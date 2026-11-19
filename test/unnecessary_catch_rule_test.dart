import 'package:dart_throws/src/exception_contract_rule.dart';
import 'package:test/test.dart';

import 'analysis_test_support.dart';

void main() {
  group('unnecessary catch', () {
    test('warns once when a try only calls non-throwing functions', () async {
      final reports = await _analyzeCatches('''
@NonThrows
void safe() {}

@Throws(exceptions: [])
void alsoSafe() {}

void check() {
  try {
    safe();
    alsoSafe();
  } on FormatException {
  } catch (_) {}

  try {
    safe();
  } finally {
    safe();
  }
}
''');
      expect(reports, ['on']);
    });

    test('uses the policy for calls with no annotation', () async {
      const source = '''
void check() {
  try {
    int.parse('invalid');
  } catch (_) {}
}
''';
      expect(await _analyzeCatches(source, unannotated: 'throws'), isEmpty);
      expect(await _analyzeCatches(source, unannotated: 'non_throws'), [
        'catch',
      ]);
    });

    test(
      'counts throws reaching the catch, including a nested rethrow',
      () async {
        final reports = await _analyzeCatches('''
@Throws(exceptions: [FormatException])
void fail() => throw const FormatException();

void check() {
  try {
    try {
      fail();
    } on FormatException {}
  } catch (_) {}

  try {
    try {
      throw 'failure';
    } on String {
      rethrow;
    }
  } catch (_) {}
}
''');
        expect(reports, ['catch']);
      },
    );

    test(
      'distinguishes an awaited future from a deferred function body',
      () async {
        final reports = await _analyzeCatches('''
Future<void> check(Future<void> future) async {
  try {
    await future;
  } catch (_) {}

  try {
    void deferred() => throw 'failure';
  } catch (_) {}
}
''');
        expect(reports, ['catch']);
      },
    );
  });
}

Future<List<String>> _analyzeCatches(String source, {String? unannotated}) =>
    analyzeRule(UnnecessaryCatchRule(), source, unannotated: unannotated);
