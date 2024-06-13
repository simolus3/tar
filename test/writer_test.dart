@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:tar/tar.dart' as tar;
import 'package:test/test.dart';

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
          // The date format is different across GNU and BSD tar
          anyOf(contains('12:34'), contains('Dec 30')),
        ),
      ),
    );
  }, testOn: '!windows');

  test('writes entries synchronously', () async {
    final date = DateTime.parse('2020-12-30 12:34');
    final builder = BytesBuilder(copy: false);
    final sink = tar.tarConverter
        .startChunkedConversion(ByteConversionSink.withCallback(builder.add));

    sink.add(tar.TarEntry.data(
      tar.TarHeader(
        name: 'first.txt',
        mode: int.parse('644', radix: 8),
        size: 0,
        userId: 3,
        groupId: 4,
        userName: 'my_user',
        modified: date,
      ),
      Uint8List(10),
    ));
    sink.add(tar.TarEntry.data(
      tar.TarHeader(
        name: 'second.txt',
        mode: int.parse('644', radix: 8),
        size: 0,
        userId: 3,
        groupId: 4,
        userName: 'my_user',
        modified: date,
      ),
      Uint8List(512),
    ));

    sink.close();

    final process = await startTar(['--list', '--verbose']);
    process.stdin.add(builder.takeBytes());

    expect(
      process.lines,
      emitsInOrder(
        <Matcher>[
          allOf(
            contains('-rw-r--r--'),
            contains('my_user'),
            contains('10'),
            // The date format is different across GNU and BSD tar
            anyOf(contains('12:34'), contains('Dec 30')),
            contains('first.txt'),
          ),
          allOf(
            contains('-rw-r--r--'),
            contains('my_user'),
            contains('512'),
            // The date format is different across GNU and BSD tar
            anyOf(contains('12:34'), contains('Dec 30')),
            contains('second.txt'),
          ),
        ],
      ),
    );

    await process.stdin.close();
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
  }, testOn: '!windows && !node', onPlatform: {
    'mac-os': const Skip('This tests sometimes times out on macOS'),
  });

  group('refuses to write files with OutputFormat.gnu', () {
    void shouldThrow(tar.TarEntry entry) {
      final output = tar.tarWritingSink(_NullStreamSink(),
          format: tar.OutputFormat.gnuLongName);
      // ignore: discarded_futures
      expect(Stream.value(entry).pipe(output), throwsA(isUnsupportedError));
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
            mode: 0,
          ),
          [],
        ),
      );
    });
  });
}

class _NullStreamSink<T> implements StreamSink<T> {
  @override
  void add(T event) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // ignore: only_throw_errors
    throw error;
  }

  @override
  Future<void> addStream(Stream<T> stream) {
    return stream.forEach(add);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => close();
}
