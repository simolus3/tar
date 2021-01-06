import 'dart:io';
import 'dart:typed_data';

import 'package:tar/tar.dart' as tar;

Future<void> main() async {
  // Generate tar file claiming to have a 7 GB header
  await Stream<tar.Entry>.fromIterable([
    tar.Entry.data(
      tar.Header(
        name: 'PaxHeader',
        mode: 0,
        typeFlag: tar.TypeFlag.xHeader,
        size: 1024 * 1024 * 1024 * 7,
      ),
      Uint8List(0),
    ),
    tar.Entry.data(
      tar.Header(
        name: 'test.txt',
        mode: 0,
      ),
      Uint8List(0),
    ),
  ])
      .transform(tar.writer)
      .pipe(File('reference/evil_large_header.tar').openWrite());
}
