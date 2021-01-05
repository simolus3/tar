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
    final tarEntries = File('reference/headers/evil_large_header.tar')
        .openRead()
        .transform(tar.reader);

    expect(tarEntries, emitsError(isStateError));
  });

  test('throws on unexpected EOF', () {
    final tarEntries =
        File('reference/bad_truncated.tar').openRead().transform(tar.reader);

    expect(
      tarEntries,
      emitsError(
        isA<StateError>()
            .having((e) => e.message, 'message', contains('Unexpected end')),
      ),
    );
  });
}

Future<void> _testWith(String file, {bool ignoreLongFileName = false}) async {
  final tarEntries = File(file).openRead().transform(tar.reader);
  final entries = {
    await for (final entry in tarEntries) entry.name: await entry.readFully()
  };

  final testEntry = entries['reference/res/test.txt']!;
  expect(utf8.decode(testEntry), 'Test file content!\n');

  if (!ignoreLongFileName) {
    final longName = entries['reference/res/'
        'subdirectory_with_a_long_name/'
        'file_with_a_path_length_of_more_than_100_characters_so_that_it_gets_split.txt']!;
    expect(utf8.decode(longName), 'ditto');
  }
}

void _testLargeFile(String file) {
  final entries = File(file).openRead().transform(tar.reader);

  expect(entries,
      emits(isA<tar.Entry>().having((e) => e.size, 'size', 9663676416)));
}

extension on Stream<List<int>> {
  Future<Uint8List> readFully() async {
    final builder = BytesBuilder();
    await forEach(builder.add);
    return builder.takeBytes();
  }
}
