@TestOn('windows')
import 'dart:io';

import 'package:tar/tar.dart';
import 'package:test/test.dart';

import 'system_tar.dart';

void main() {
  test('emits long file names that are understood by 7zip', () async {
    final name = 'name' * 40;
    final entry = TarEntry.data(TarHeader(name: name), []);
    final file = File(Directory.systemTemp.path + '\\tar_test.tar');
    addTearDown(file.delete);

    await Stream<TarEntry>.value(entry)
        .transform(tarWriterWith(format: OutputFormat.gnuLongName))
        .pipe(file.openWrite());

    final proc = await Process.start('7za.exe', ['l', file.path]);
    expect(proc.lines, emitsThrough(contains(name)));
  });
}
