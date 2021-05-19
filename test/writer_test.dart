import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:tar/tar.dart' as tar;
import 'system_tar.dart';

const oneMbSize = 1024 * 1024;
const tenGbSize = oneMbSize * 1024 * 10;

void main() {
  group('writes long file names', () {
    for (final style in tar.OutputFormat.values) {
      test(style.toString(), () async {
        final name = '${'very' * 30} long name.txt';
        final withLongName = tar.TarEntry.data(
          tar.TarHeader(name: name, mode: 0, size: 0),
          Uint8List(0),
        );

        final proc = await writeToTar(['--list'], Stream.value(withLongName),
            format: style);
        expect(proc.lines, emits(contains(name)));
      });
    }
  }, testOn: '!windows');

  test('writes headers', () async {
    final date = DateTime.parse('2020-12-30 12:34');
    final entry = tar.TarEntry.data(
      tar.TarHeader(
        name: 'hello_dart.txt',
        mode: int.parse('744', radix: 8),
        size: 0,
        userId: 3,
        groupId: 4,
        userName: 'my_user',
        groupName: 'long group that exceeds 32 characters',
        modified: date,
      ),
      Uint8List(0),
    );

    final proc = await writeToTar(['--list', '--verbose'], Stream.value(entry));
    expect(
      proc.lines,
      emits(
        allOf(
          contains('-rwxr--r--'),
          contains('my_user'),
          contains('long group that exceeds 32 characters'),
          contains('12:34'),
        ),
      ),
    );
  }, testOn: '!windows');

  test('writes huge files', () async {
    final oneMb = Uint8List(oneMbSize);
    const count = tenGbSize ~/ oneMbSize;

    final entry = tar.TarEntry(
      tar.TarHeader(
        name: 'file.blob',
        mode: 0,
        size: tenGbSize,
      ),
      Stream<List<int>>.fromIterable(Iterable.generate(count, (i) => oneMb)),
    );

    final proc = await writeToTar(['--list', '--verbose'], Stream.value(entry));
    expect(proc.lines, emits(contains(tenGbSize.toString())));
  }, testOn: '!windows');

  group('refuses to write files with OutputFormat.gnu', () {
    void shouldThrow(tar.TarEntry entry) {
      final output = File('/dev/null').openWrite();
      expect(
          Stream.value(entry).pipe(
              tar.tarWritingSink(output, format: tar.OutputFormat.gnuLongName)),
          throwsA(isA<tar.TarException>()));
    }

    test('when they are too large', () {
      final oneMb = Uint8List(oneMbSize);
      const count = tenGbSize ~/ oneMbSize;

      final entry = tar.TarEntry(
        tar.TarHeader(
          name: 'file.blob',
          mode: 0,
          size: tenGbSize,
        ),
        Stream<List<int>>.fromIterable(Iterable.generate(count, (i) => oneMb)),
      );
      shouldThrow(entry);
    });

    test('when they use long user names', () {
      shouldThrow(
        tar.TarEntry.data(
          tar.TarHeader(
            name: 'file.txt',
            userName: 'this name is longer than 32 chars, which is not allowed',
          ),
          [],
        ),
      );
    });
  });
}
