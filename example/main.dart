import 'dart:convert';
import 'dart:io';

import 'package:tar/tar.dart' as tar;

Future<void> main() async {
  // Start reading a tar file
  final reader = tar.Reader(File('reference/gnu.tar').openRead());

  while (await reader.next()) {
    final header = reader.header;
    print('${header.name}: ');

    // Print the output if it's a regular file
    if (header.typeFlag == tar.TypeFlag.reg) {
      print(await reader.contents.transform(utf8.decoder).first);
    }
  }

  // We can write tar files to any stream sink like this:
  final output = File('test.tar').openWrite();

  await Stream<tar.Entry>.value(
    tar.Entry.data(
      tar.Header(
          name: 'hello_dart.txt',
          mode: int.parse('644', radix: 8),
          userName: 'Dart',
          groupName: 'Dartgroup'),
      utf8.encode('Hello world'),
    ),
  )
      // transform tar entries back to a byte stream
      .transform(tar.writer)
      // and then write that to the file
      .pipe(output);
}
