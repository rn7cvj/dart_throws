/// Declares the types of values that may escape this callable as exceptions.
final class Throws {
  final List<Type> exceptions;

  const Throws({required this.exceptions});
}

/// Declares that this callable handles all exceptions.
// ignore: constant_identifier_names
const NonThrows = _NonThrows();

final class _NonThrows {
  const _NonThrows();
}
