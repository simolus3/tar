import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:tar/tar.dart' as tar;

void main() {
  group('POSIX.1-2001', () {
    test('reads files', () => _testWith('reference/posix.tar'));

    test('reads large files',
        () => _testLargeFile('reference/headers/large_posix.tar'));
  });

  test('(new) GNU Tar format', () => _testWith('reference/gnu.tar'));
  test('ustar', () => _testWith('reference/ustar.tar'));
  test('v7', () => _testWith('reference/v7.tar', ignoreLongFileName: true));

  test('does not read large headers', () {
    final reader =
        tar.Reader(File('reference/headers/evil_large_header.tar').openRead());

    expect(
      reader.moveNext(),
      throwsA(
        isFormatException.having((e) => e.message, 'message',
            contains('hidden entry with an invalid size')),
      ),
    );
  });

  group('throws on unexpected EoF', () {
    final expectedException = isA<tar.TarException>()
        .having((e) => e.message, 'message', contains('Unexpected end'));

    test('at header', () {
      final reader =
          tar.Reader(File('reference/bad/truncated_in_header.tar').openRead());
      expect(reader.moveNext(), throwsA(expectedException));
    });

    test('in content', () {
      final reader =
          tar.Reader(File('reference/bad/truncated_in_body.tar').openRead());
      expect(reader.moveNext(), throwsA(expectedException));
    });
  });
}

Future<void> _testWith(String file, {bool ignoreLongFileName = false}) async {
  final entries = <String, Uint8List>{};

  await tar.Reader.forEach(File(file).openRead(), (header, contents) async {
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
  final reader = tar.Reader(File(file).openRead());
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
