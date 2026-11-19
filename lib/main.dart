import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/exception_contract_rule.dart';

final plugin = _DartThrowsPlugin();

class _DartThrowsPlugin extends Plugin {
  @override
  String get name => 'dart_throws';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(ExceptionContractRule());
    registry.registerWarningRule(UnnecessaryCatchRule());
  }
}
