echo -e "@internal\nimport 'package:meta/meta.dart';\n" > lib/src/charcodes.dart
dart run charcode 'ustarxgASLK=\x20\x0a\d' >> lib/src/charcodes.dart
