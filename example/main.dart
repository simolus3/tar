import 'dart:convert';
import 'dart:io';

import 'package:tar/tar.dart' as tar;

Future<void> main() async {
  // Start reading a tar file
  final tarFile = File('reference/gnu.tar').openRead().transform(tar.reader);

  await for (final entry in tarFile) {
    print('${entry.name}: ');

    if (entry.type == tar.FileType.regular) {
      // Tar entries are streams emitting their content, so we can get their
      // string content like this:
      print(await entry.transform(utf8.decoder).first);
    }
  }

  // We can write tar files to any stream sink like this:
  final output = File('test.tar').openWrite();

  await Stream<tar.Entry>.value(
    tar.MemoryEntry(
      tar.Header(
        name: 'hello_dart.txt',
        mode: int.parse('644', radix: 8),
      ),
      utf8.encode('Hello world'),
    ),
  )
      // transform tar entries back to a byte stream
      .transform(tar.writer)
      // and then write that to the file
      .pipe(output);
}
