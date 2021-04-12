// Simple tests to ensure that we can parse weird tars found on pub.
//
// The test cases were found by running an earlier version of this package
// across all packages and versions found on pub.dev. This package needs to
// be able to read every package version ever uploaded to pub.
import 'dart:io';

import 'package:tar/tar.dart';
import 'package:test/test.dart';

void main() {
  const onceBroken = [
    'access_settings_menu-0.0.1',
    'pana-0.12.19',
    'RAL-1.28.0',
    'rikulo_commons-0.7.6',
  ];

  for (final package in onceBroken) {
    test('can read $package', () async {
      final file = File('reference/pub/$package.tar.gz');
      final tarStream = file.openRead().transform(gzip.decoder);

      final reader = TarReader(tarStream, disallowTrailingData: true);
      while (await reader.moveNext()) {}
    });
  }
}
