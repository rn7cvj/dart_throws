import 'dart:io';

import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/analysis_rule/rule_context.dart';
import 'package:analyzer/src/lint/linter_visitor.dart';
import 'package:dart_throws/src/exception_contract_rule.dart';
import 'package:test/test.dart';

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

Future<List<String>> _analyze(String source) async {
  final contents = "import 'package:dart_throws/dart_throws.dart';\n$source";
  final resources = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  final path = resources.pathContext.join(
    Directory.current.path,
    'test',
    'contract_fixture.dart',
  );
  resources.setOverlay(path, content: contents, modificationStamp: 0);
  final collection = AnalysisContextCollection(
    includedPaths: [path],
    resourceProvider: resources,
  );
  addTearDown(collection.dispose);

  final session = collection.contextFor(path).currentSession;
  final result = await session.getResolvedUnit(path) as ResolvedUnitResult;
  final listener = RecordingDiagnosticListener();
  final reporter = DiagnosticReporter(listener, result.libraryFragment.source);
  final unit = RuleContextUnit(
    file: resources.getFile(path),
    content: contents,
    diagnosticReporter: reporter,
    unit: result.unit,
  );
  final context = RuleContextWithResolvedResults(
    [unit],
    unit,
    result.typeProvider,
    result.typeSystem,
    null,
  )..currentUnit = unit;
  final rule = ExceptionContractRule()..reporter = reporter;
  final registry = RuleVisitorRegistryImpl(enableTiming: false);
  rule.registerNodeProcessors(registry, context);
  result.unit.accept(
    AnalysisRuleVisitor(registry, shouldPropagateExceptions: true),
  );
  return listener.diagnostics
      .map(
        (diagnostic) => contents.substring(
          diagnostic.offset,
          diagnostic.offset + diagnostic.length,
        ),
      )
      .toList();
}
