import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:yaml/yaml.dart';

class ExceptionContractRule extends AnalysisRule {
  static const code = LintCode(
    'unhandled_exception',
    'An exception of type {0} can escape this callable outside its contract.',
    correctionMessage: 'Catch the exception or declare its type in @Throws.',
    severity: DiagnosticSeverity.WARNING,
  );

  ExceptionContractRule()
    : super(
        name: code.lowerCaseName,
        description: 'Checks @Throws and @NonThrows.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _DeclarationVisitor(this, context);
    registry.addFunctionDeclaration(this, visitor);
    registry.addMethodDeclaration(this, visitor);
    registry.addConstructorDeclaration(this, visitor);
  }
}

class _DeclarationVisitor extends SimpleAstVisitor<void> {
  final ExceptionContractRule rule;
  final RuleContext context;
  late final _UnannotatedPolicy _unannotatedPolicy = _readUnannotatedPolicy(
    context.definingUnit.file,
  );

  _DeclarationVisitor(this.rule, this.context);

  _BodyVisitor? _checker(ExecutableFragment? fragment) {
    final allowed = _declaredExceptions(fragment?.element);
    if (allowed == null) return null;
    return _BodyVisitor(rule, context, allowed, _unannotatedPolicy);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final checker = _checker(node.declaredFragment);
    if (checker != null) node.functionExpression.body.accept(checker);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final checker = _checker(node.declaredFragment);
    if (checker != null) node.body.accept(checker);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final checker = _checker(node.declaredFragment);
    if (checker == null) return;
    node.initializers.accept(checker);
    node.body.accept(checker);
    final redirect = node.redirectedConstructor;
    if (redirect != null) checker.checkCall(redirect, redirect.element);
  }
}

class _BodyVisitor extends RecursiveAstVisitor<void> {
  final ExceptionContractRule rule;
  final RuleContext context;
  final List<DartType> allowed;
  final _UnannotatedPolicy unannotatedPolicy;

  _BodyVisitor(this.rule, this.context, this.allowed, this.unannotatedPolicy);

  DartType get _objectType => context.typeProvider.objectType;

  bool _isCoveredBy(DartType thrown, DartType handler) =>
      context.typeSystem.isSubtypeOf(thrown, handler);

  bool _isCaught(AstNode node, DartType thrown) {
    for (var child = node; child.parent != null; child = child.parent!) {
      final parent = child.parent;
      if (parent is FunctionBody || parent is ConstructorDeclaration) break;
      if (parent is! TryStatement || child != parent.body) continue;
      for (final clause in parent.catchClauses) {
        if (clause.exceptionType == null) return true;
        final type = clause.exceptionType?.type;
        if (type != null && _isCoveredBy(thrown, type)) return true;
      }
    }
    return false;
  }

  void _check(AstNode node, Iterable<DartType> thrown, {bool canCatch = true}) {
    for (final type in thrown) {
      if (allowed.any((handler) => _isCoveredBy(type, handler))) continue;
      if (canCatch && _isCaught(node, type)) continue;
      rule.reportAtNode(node, arguments: [type.getDisplayString()]);
    }
  }

  void checkCall(AstNode node, Element? element) {
    final declared = _declaredExceptions(element);
    final thrown =
        declared ??
        switch (unannotatedPolicy) {
          _UnannotatedPolicy.throws => [_objectType],
          _UnannotatedPolicy.nonThrows => const <DartType>[],
        };
    if (thrown.isEmpty) return;
    // A catch around a Future-producing call only sees its asynchronous
    // failure when the Future is awaited before leaving the try block.
    final type = node is Expression ? node.staticType : null;
    final canCompleteLater =
        type?.asInstanceOf(context.typeProvider.futureElement) != null ||
        type?.isDartAsyncFutureOr == true;
    var result = node;
    while (result.parent is ParenthesizedExpression) {
      result = result.parent!;
    }
    _check(
      node,
      thrown,
      canCatch: !canCompleteLater || result.parent is AwaitExpression,
    );
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {}

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitMethodInvocation(MethodInvocation node) {
    checkCall(node, node.methodName.element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    checkCall(node, node.element);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!node.isConst) checkCall(node, node.constructorName.element);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    checkCall(node, node.memberName.element);
    super.visitDotShorthandInvocation(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    if (!node.isConst) checkCall(node, node.constructorName.element);
    super.visitDotShorthandConstructorInvocation(node);
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    checkCall(node, node.element);
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitRedirectingConstructorInvocation(
    RedirectingConstructorInvocation node,
  ) {
    checkCall(node, node.element);
    super.visitRedirectingConstructorInvocation(node);
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    final type = node.expression.staticType;
    if (type is! NeverType) {
      _check(node, [type == null || type is DynamicType ? _objectType : type]);
    }
    super.visitThrowExpression(node);
  }

  @override
  void visitRethrowExpression(RethrowExpression node) {
    final clause = node.thisOrAncestorOfType<CatchClause>();
    _check(node, [clause?.exceptionType?.type ?? _objectType]);
  }
}

enum _UnannotatedPolicy {
  throws('throws'),
  nonThrows('non_throws');

  const _UnannotatedPolicy(this.yamlValue);

  final String yamlValue;
}

// The plugin protocol has no field for custom options. Read our top-level
// section through the analyzer's resource provider.
_UnannotatedPolicy _readUnannotatedPolicy(File source) {
  var folder = source.parent;
  while (true) {
    final options = folder.getFile('analysis_options.yaml');
    try {
      if (options.exists) {
        final yaml = loadYaml(options.readAsStringSync());
        if (yaml case {'dart_throws': {'unannotated': final mode}}) {
          return _UnannotatedPolicy.values.firstWhere(
            (policy) => policy.yamlValue == mode,
            orElse: () => _UnannotatedPolicy.throws,
          );
        }
      }
    } on YamlException {
      return _UnannotatedPolicy.throws;
    } on FileSystemException {
      return _UnannotatedPolicy.throws;
    }
    if (folder.isRoot) return _UnannotatedPolicy.throws;
    folder = folder.parent;
  }
}

List<DartType>? _declaredExceptions(Element? element) {
  if (element is! ExecutableElement) return null;
  const annotationLibrary = 'package:dart_throws/src/dart_throws_base.dart';
  List<DartType>? declared;
  for (final annotation in element.metadata.annotations) {
    final value = annotation.computeConstantValue();
    final type = value?.type;
    if (type is! InterfaceType ||
        type.element.library.uri.toString() != annotationLibrary) {
      continue;
    }
    if (type.element.name == '_NonThrows') return const [];
    if (type.element.name != 'Throws') continue;
    final entries = value?.getField('exceptions')?.toListValue();
    if (entries == null) continue;
    final types = entries.map((entry) => entry.toTypeValue()).nonNulls.toList();
    if (types.length == entries.length) declared = types;
  }
  return declared;
}
