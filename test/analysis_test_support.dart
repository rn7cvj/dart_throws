import 'dart:io';

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/analysis_rule/rule_context.dart'
    show RuleContextWithResolvedResults;
import 'package:analyzer/src/lint/linter_visitor.dart';
import 'package:test/test.dart';

Future<List<String>> analyzeRule(
  AnalysisRule rule,
  String source, {
  String? unannotated,
}) async {
  final contents = "import 'package:dart_throws/dart_throws.dart';\n$source";
  final resources = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  final path = resources.pathContext.join(
    Directory.current.path,
    'test',
    'contract_fixture.dart',
  );
  resources.setOverlay(path, content: contents, modificationStamp: 0);
  if (unannotated != null) {
    resources.setOverlay(
      resources.pathContext.join(
        resources.pathContext.dirname(path),
        'analysis_options.yaml',
      ),
      content: 'dart_throws:\n  unannotated: $unannotated\n',
      modificationStamp: 0,
    );
  }
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
  rule.reporter = reporter;
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
