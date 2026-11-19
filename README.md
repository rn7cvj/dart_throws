# dart_throws

`dart_throws` adds checked exception contracts to Dart through an analyzer plugin.

## Setup

Add `dart_throws` as a dependency in `pubspec.yaml`. For a local checkout, point both configuration files at it.

```yaml
# pubspec.yaml
dependencies:
  dart_throws:
    path: ../dart_throws
```

```yaml
# analysis_options.yaml
plugins:
  dart_throws:
    path: ../dart_throws

dart_throws:
  unannotated: throws
```

Run `dart pub get`, then `dart analyze`. The plugin reports `dart_throws/unhandled_exception` as a warning. Restart the Dart Analysis Server to load the plugin in an already open IDE.

## Unannotated calls

- `throws` (default) treats an unannotated call as able to throw any `Object`. Use `on Object` or `catch (e)` to handle it. `on Exception` leaves `Error` and other thrown objects uncovered.
- `non_throws` assumes unannotated calls do not throw. Explicit annotations, `throw`, and `rethrow` are still checked in annotated bodies.

The analysis server plugin API exposes diagnostic configuration. The plugin reads `dart_throws.unannotated` directly from the closest enclosing `analysis_options.yaml` that defines it. Set it directly in that file, since `include:` applies to Dart Analyzer options. An unrecognized value falls back to `throws`.

## Contracts

```dart
import 'package:dart_throws/dart_throws.dart';

@Throws(exceptions: [FormatException])
int readFlag(String text) {
  if (text == 'on') return 1;
  throw const FormatException('Expected on');
}

@NonThrows
int readFlagOrDefault(String text) {
  try {
    return readFlag(text);
  } on FormatException {
    return 0;
  }
}

@NonThrows
int parseOrDefault(String text) {
  try {
    return int.parse(text);
  } on Object {
    return 0;
  }
}
```

- `@Throws(exceptions: [...])` allows only the listed types and their subtypes to escape. `@Throws(exceptions: [])` is equivalent to `@NonThrows`.
- The rule checks explicit `throw`, `rethrow`, and calls in annotated bodies. Only the `try` body is protected by its own handlers. A throw from `catch` or `finally` can be caught by an enclosing `try`.
- For a call whose static return type is `Future` or `FutureOr`, use `await` directly on the call within the `try` block. The rule does not track futures saved in variables or error handlers installed through `catchError`.

The rule uses the statically resolved declaration for each call. It does not follow function aliases, verify override contracts, or model implicit Dart runtime failures.
