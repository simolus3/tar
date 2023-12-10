import 'dart:io';

import 'package:tar/tar.dart';

const verbose = bool.fromEnvironment('verbose');

/// Reads tar files from arguments and expects not to crash.
///
/// When something goes wrong, the name of the problematic tar file is printed.
/// By running with `-Dverbose=true`, a stack trace is printed as well.
void main(List<String> files) async {
  for (final file in files) {
    try {
      await TarReader.forEach(File(file).openRead(), (entry) {});
    } on TarException {
      // These are fine
    } on Object catch (e, s) {
      // Other exceptions indicate a bug in pkg:tar
      if (verbose) {
        print(e);
        print(s);
      } else {
        print(
            'failed for $file - run `dart -Dverbose=true tool/fuzz.dart $file`');
      }

      exit(128);
    }
  }
}
