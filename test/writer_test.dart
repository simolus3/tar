import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:tar/tar.dart' as tar;
import 'system_tar.dart';

void main() {
  test('writes long file names', () async {
    final name = '${'very' * 30} long name.txt';
    final withLongName = tar.MemoryEntry(
      tar.Header(name: name, mode: 0, size: 0),
      Uint8List(0),
    );

    final proc = await writeToTar(['--list'], Stream.value(withLongName));
    expect(proc.lines, emits(name));
  });

  test('writes headers', () async {
    final date = DateTime.parse('2020-12-30 12:34');
    final entry = tar.MemoryEntry(
      tar.Header(
        name: 'hello_dart.txt',
        mode: int.parse('744', radix: 8),
        size: 0,
        uid: 3,
        gid: 4,
        userName: 'my_user',
        groupName: 'long group that exceeds 32 characters',
        lastModified: date,
      ),
      Uint8List(0),
    );

    final proc = await writeToTar(['--list', '--verbose'], Stream.value(entry));
    expect(
      proc.lines,
      emits(
        allOf(
          contains('-rwxr--r--'),
          contains('my_user/long group that exceeds 32 characters'),
          contains('2020-12-30 12:34'),
        ),
      ),
    );
  });
}
