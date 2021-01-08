import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tar/src/reader.dart';
import 'package:test/test.dart';

import 'package:tar/tar.dart';

void main() {
  group('POSIX.1-2001', () {
    test('reads files', () => _testWith('reference/posix.tar'));

    test('reads large files',
        () => _testLargeFile('reference/headers/large_posix.tar'));
  });

  test('(new) GNU Tar format', () => _testWith('reference/gnu.tar'));
  test('ustar', () => _testWith('reference/ustar.tar'));
  test('v7', () => _testWith('reference/v7.tar', ignoreLongFileName: true));

  test('can skip tar files', () async {
    final input = File('reference/posix.tar').openRead();
    final reader = TarReader(input);

    expect(await reader.moveNext(), isTrue);
    expect(await reader.moveNext(), isTrue);
    expect(reader.header.name, 'reference/res/subdirectory_with_a_long_name/');
  });

  test('getters throw before moveNext() is called', () {
    final reader = TarReader(const Stream<Never>.empty());

    expect(() => reader.contents, throwsStateError);
    expect(() => reader.header, throwsStateError);
    expect(() => reader.current, throwsStateError);
  });

  test("can't use next() concurrently", () {
    final reader = TarReader(Stream.fromFuture(
        Future.delayed(const Duration(seconds: 2), () => <int>[])));

    expect(reader.moveNext(), completion(isFalse));
    expect(() => reader.moveNext(), throwsStateError);
    return reader.cancel();
  });

  test("can't use next() while a stream is active", () async {
    final input = File('reference/posix.tar').openRead();
    final reader = TarReader(input);

    expect(await reader.moveNext(), isTrue);
    reader.contents.listen((event) {}).pause();

    expect(() => reader.moveNext(), throwsStateError);
    await reader.cancel();
  });

  test('does not read large headers', () {
    final reader =
        TarReader(File('reference/headers/evil_large_header.tar').openRead());

    expect(
      reader.moveNext(),
      throwsA(
        isFormatException.having((e) => e.message, 'message',
            contains('hidden entry with an invalid size')),
      ),
    );
  });

  group('throws on unexpected EoF', () {
    final expectedException = isA<TarException>()
        .having((e) => e.message, 'message', contains('Unexpected end'));

    test('at header', () {
      final reader =
          TarReader(File('reference/bad/truncated_in_header.tar').openRead());
      expect(reader.moveNext(), throwsA(expectedException));
    });

    test('in content', () {
      final reader =
          TarReader(File('reference/bad/truncated_in_body.tar').openRead());
      expect(reader.moveNext(), throwsA(expectedException));
    });
  });

  group('PAX headers', () {
    test('locals overrwrite globals', () {
      final header = PaxHeaders()
        ..newGlobals({'foo': 'foo', 'bar': 'bar'})
        ..newLocals({'foo': 'local'});

      expect(header.keys, containsAll(<String>['foo', 'bar']));
      expect(header['foo'], 'local');
    });

    group('parse', () {
      final mediumName = 'CD' * 50;
      final longName = 'AB' * 100;

      final tests = [
        ['6 k=v\n\n', 'k', 'v', true],
        ['19 path=/etc/hosts\n', 'path', '/etc/hosts', true],
        ['210 path=' + longName + '\nabc', 'path', longName, true],
        ['110 path=' + mediumName + '\n', 'path', mediumName, true],
        ['9 foo=ba\n', 'foo', 'ba', true],
        ['11 foo=bar\n\x00', 'foo', 'bar', true],
        ['18 foo=b=\nar=\n==\x00\n', 'foo', 'b=\nar=\n==\x00', true],
        ['27 foo=hello9 foo=ba\nworld\n', 'foo', 'hello9 foo=ba\nworld', true],
        ['27 ☺☻☹=日a本b語ç\n', '☺☻☹', '日a本b語ç', true],
        ['17 \x00hello=\x00world\n', '', '', false],
        ['1 k=1\n', '', '', false],
        ['6 k~1\n', '', '', false],
        ['6 k=1 ', '', '', false],
        ['632 k=1\n', '', '', false],
        ['16 longkeyname=hahaha\n', '', '', false],
        ['3 somelongkey=\n', '', '', false],
        ['50 tooshort=\n', '', '', false],
      ];

      for (final input in tests) {
        test('parsePax(${input[0]})', () {
          final headers = PaxHeaders();

          final raw = utf8.encode(input[0] as String);
          final key = input[1];
          final value = input[2];
          final isValid = input[3] as bool;

          if (isValid) {
            headers.readPaxHeaders(raw, false, ignoreUnknown: false);
            expect(headers.keys, [key]);
            expect(headers[key], value);
          } else {
            expect(() => headers.readPaxHeaders(raw, false),
                throwsA(isA<TarException>()));
          }
        });
      }
    });
  });
}

Future<void> _testWith(String file, {bool ignoreLongFileName = false}) async {
  final entries = <String, Uint8List>{};

  await TarReader.forEach(File(file).openRead(), (header, contents) async {
    entries[header.name] = await contents.readFully();
  });

  final testEntry = entries['reference/res/test.txt']!;
  expect(utf8.decode(testEntry), 'Test file content!\n');

  if (!ignoreLongFileName) {
    final longName = entries['reference/res/'
        'subdirectory_with_a_long_name/'
        'file_with_a_path_length_of_more_than_100_characters_so_that_it_gets_split.txt']!;
    expect(utf8.decode(longName), 'ditto');
  }
}

Future<void> _testLargeFile(String file) async {
  final reader = TarReader(File(file).openRead());
  await reader.moveNext();

  expect(reader.header.size, 9663676416);
}

extension on Stream<List<int>> {
  Future<Uint8List> readFully() async {
    final builder = BytesBuilder();
    await forEach(builder.add);
    return builder.takeBytes();
  }
}
