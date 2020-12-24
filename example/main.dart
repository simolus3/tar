import 'dart:convert';
import 'dart:io';

import 'package:tar/tar.dart' as tar;

Future<void> main() async {
  // Use this to read tar files
  final tarFile = File('reference/gnu.tar').openRead().transform(tar.reader);

  await for (final entry in tarFile) {
    print('${entry.name}: ${entry.header.type}');
  }

  // Or, to write tar files
  final output = File('test.tar').openWrite();

  await Stream<tar.Entry>.value(
    tar.MemoryEntry(
      tar.Header(
        name: 'hello_dart.txt',
        mode: int.parse('644', radix: 8),
      ),
      utf8.encode('Hello world'),
    ),
  ).pipe(tar.WritingSink(output));
}
