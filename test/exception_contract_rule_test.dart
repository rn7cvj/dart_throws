import 'package:dart_throws/src/exception_contract_rule.dart';
import 'package:test/test.dart';

import 'analysis_test_support.dart';

void main() {
  test('unannotated calls require a catch-all', () async {
    final reports = await _analyze('''
@NonThrows
void check(void Function() callback) {
  try {
    int.parse('invalid');
    callback();
  } on Exception {
    return;
  }
  try {
    int.parse('safe');
    callback();
  } on Object {
    return;
  }
}
''');
    expect(reports, ["int.parse('invalid')", 'callback()']);
  });

  test('typed contracts accept subtypes and propagate through calls', () async {
    final reports = await _analyze('''
@Throws(exceptions: [FormatException])
void parse() => throw const FormatException();

@Throws(exceptions: [Exception])
void forward() => parse();

@NonThrows
void safe() {
  try {
    forward();
  } on Exception {
    // Handled.
  }
}

@Throws(exceptions: [])
void invalid() => forward();

@Throws(exceptions: [FormatException])
void invalidThrow() => throw 'unexpected';
''');
    expect(reports, ['forward()', "throw 'unexpected'"]);
  });

  const configuredCalls = '''
@Throws(exceptions: [FormatException])
void annotated() => throw const FormatException();

@NonThrows
int check() {
  annotated();
  return int.parse('invalid');
}

@NonThrows
void explicitThrow() => throw 'unexpected';
''';

  test('non_throws assumes safety for unannotated calls only', () async {
    final reports = await _analyze(configuredCalls, unannotated: 'non_throws');
    expect(reports, ['annotated()', "throw 'unexpected'"]);
  });

  for (final mode in ['throws', 'invalid']) {
    test('$mode treats unannotated calls as potentially throwing', () async {
      final reports = await _analyze(configuredCalls, unannotated: mode);
      expect(reports, [
        'annotated()',
        "int.parse('invalid')",
        "throw 'unexpected'",
      ]);
    });
  }

  test(
    'catch and finally bodies are protected only by outer handlers',
    () async {
      final reports = await _analyze('''
@NonThrows
void check() {
  try {
    try {
      int.parse('invalid');
    } catch (_) {
      rethrow;
    }
  } catch (_) {
    // Handled.
  }

  try {
    int.parse('invalid');
  } catch (_) {
    rethrow;
  } finally {
    throw 'finally';
  }
}
''');
      expect(reports, ['rethrow', "throw 'finally'"]);
    },
  );

  test('a catch only handles future failures when awaited inside it', () async {
    final reports = await _analyze('''
@Throws(exceptions: [String])
Future<void> fail() async => throw 'failure';

@NonThrows
Future<void> safe() async {
  try {
    await (fail());
  } on String {
    // Handled.
  }
}

@NonThrows
Future<void> unsafe() async {
  try {
    return fail();
  } on String {
    // The future can fail after the try.
  }
}
''');
    expect(reports, ['fail()']);
  });

  test('checks methods and local functions in their own scopes', () async {
    final reports = await _analyze('''
class Reader {
  @NonThrows
  const Reader();

  @Throws(exceptions: [FormatException])
  void read() => throw const FormatException();

  @NonThrows
  void check() => read();
}

@NonThrows
void check() {
  @NonThrows
  void invalidLocal() => throw 'local';

  try {
    invalidLocal();
    const Reader().read();
  } on FormatException {
    // Handled.
  }
}
''');
    expect(reports, ['read()', "throw 'local'"]);
  });
}

Future<List<String>> _analyze(String source, {String? unannotated}) =>
    analyzeRule(ExceptionContractRule(), source, unannotated: unannotated);
