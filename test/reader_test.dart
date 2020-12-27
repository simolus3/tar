import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:tar/tar.dart' as tar;

void main() {
  test('POSIX.1-2001', () => _testWith('reference/posix.tar'));
  test('(new) GNU Tar format', () => _testWith('reference/gnu.tar'));
  test('ustar', () => _testWith('reference/ustar.tar'));
  test('v7', () => _testWith('reference/v7.tar', ignoreLongFileName: true));

  test('does not read large headers', () {
    final tarEntries = File('reference/evil_large_header.tar')
        .openRead()
        .transform(tar.reader);

    expect(tarEntries, emitsError(isStateError));
  });
}

Future<void> _testWith(String file, {bool ignoreLongFileName = false}) async {
  final tarEntries = File(file).openRead().transform(tar.reader);
  final entries = {
    await for (final entry in tarEntries) entry.name: await entry.readFully()
  };

  final testEntry = entries['reference/res/test.txt']!;
  expect(utf8.decode(testEntry.data), 'Test file content!\n');

  if (!ignoreLongFileName) {
    final longName = entries['reference/res/'
        'subdirectory_with_a_long_name/'
        'file_with_a_path_length_of_more_than_100_characters_so_that_it_gets_split.txt']!;
    expect(utf8.decode(longName.data), 'ditto');
  }
}
