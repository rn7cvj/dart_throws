import 'package:dart_throws/dart_throws.dart';

@Throws(exceptions: [FormatException])
int readPort(String text) {
  if (text == 'http') return 80;
  throw const FormatException('Unknown port');
}

@NonThrows
int portOrDefault(String text) {
  try {
    return readPort(text);
  } on FormatException {
    return 80;
  }
}

@NonThrows
int parsePortOrDefault(String text) {
  try {
    return int.parse(text);
  } on Object {
    return 80;
  }
}

void main() {
  print(portOrDefault('http'));
  print(parsePortOrDefault('443'));
}
