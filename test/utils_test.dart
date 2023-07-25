@TestOn('vm')
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:tar/src/constants.dart';
import 'package:tar/src/exception.dart';
import 'package:tar/src/utils.dart';
import 'package:test/test.dart';

// ignore_for_file: avoid_js_rounded_ints
void main() {
  group('readString', () {
    test('can read empty strings', () {
      expect(_bytes('').readString(0, 0), '');
    });

    test('does not include trailing null', () {
      expect(_bytes('hello\x00').readString(0, 6), 'hello');
    });

    test('does not require a trailing null', () {
      expect(_bytes('hello').readString(0, 5), 'hello');
    });
  });

  group('readStringOrNullIfEmpty', () {
    test('returns null if empty', () {
      expect(_bytes('').readStringOrNullIfEmpty(0, 0), isNull);
    });

    test('can read non-empty strings', () {
      expect(_bytes('hello').readStringOrNullIfEmpty(0, 5), 'hello');
    });
  });

  group('generates stream of zeroes', () {
    const lengths = [024 * 1024 * 128 + 12, 12, 0];

    for (final length in lengths) {
      test('with length $length', () async {
        final stream = zeroes(length);

        expect(
          await stream.fold<int>(
              0, (previous, element) => previous + element.length),
          length,
        );
      });
    }
  });

  group('readNumeric', () {
    void testValid(String value, int expected) {
      test('readNumeric($value)', () {
        expect(Uint8List.fromList(value.codeUnits).readNumeric(0, value.length),
            expected);
      });
    }

    void testValidBin(List<int> value, int expected) {
      test('readNumeric($value)', () {
        expect(
            Uint8List.fromList(value).readNumeric(0, value.length), expected);
      });
    }

    void testInvalid(String value) {
      test('readNumeric($value)', () {
        expect(() => _bytes(value).readNumeric(0, value.length),
            throwsA(isA<TarException>()));
      });
    }

    group('base-256', () {
      testValidBin([0x0], 0);
      testValidBin([0x80], 0);
      testValidBin([0x80, 0x00], 0);
      testValidBin([0x80, 0x00, 0x00], 0);
      testValidBin([0xbf], (1 << 6) - 1);
      testValidBin([0xbf, 0xff], (1 << 14) - 1);
      testValid('\xbf\xff\xff', (1 << 22) - 1);
      testValidBin([0xff], -1);
      testValidBin([0xff, 0xff], -1);
      testValidBin([0xff, 0xff, 0xff], -1);
      testValid('\xc0', -1 * (1 << 6));
      testValid('\xc0\x00', -1 * (1 << 14));
      testValid('\xc0\x00\x00', -1 * (1 << 22));
      testValid('\x87\x76\xa2\x22\xeb\x8a\x72\x61', 537795476381659745);
      testValid('\x80\x00\x00\x00\x07\x76\xa2\x22\xeb\x8a\x72\x61',
          537795476381659745);
      testValid('\xf7\x76\xa2\x22\xeb\x8a\x72\x61', -615126028225187231);
      testValid('\xff\xff\xff\xff\xf7\x76\xa2\x22\xeb\x8a\x72\x61',
          -615126028225187231);
      testValid('\x80\x7f\xff\xff\xff\xff\xff\xff\xff', 9223372036854775807);
      testValid('\xff\x80\x00\x00\x00\x00\x00\x00\x00', -9223372036854775808);
    });

    group('octal', () {
      testValid('', 0);
      testValid('   \x00  ', 0);
      testValid('0000000\x00', 0);
      testValid(' \x0000000\x00', 0);
      testValid(' \x0000003\x00', 3);
      testValid('00000000644\x00', 420);
      testValid('032033\x00 ', 13339);
      testValid('320330\x00 ', 106712);
      testValid('0000660\x00 ', 432);
      testValid('\x00 0000660\x00 ', 432);

      testInvalid('0123456789abcdef');
      testInvalid('0123456789\x00abcdef');
      testInvalid('0123\x7e\x5f\x264123');
    });
  });

  group('parsePaxTime', () {
    const validTimes = {
      '1350244992.023960108': 1350244992023960,
      '1350244992.02396010': 1350244992023960,
      '1350244992.0239601089': 1350244992023960,
      '1350244992.3': 1350244992300000,
      '1350244992': 1350244992000000,
      '-1.000000001': -1000000,
      '-1.000001': -1000001,
      '-1.001000': -1001000,
      '-1': -1000000,
      '-1.999000': -1999000,
      '-1.999999': -1999999,
      '-1.999999999': -1999999,
      '0.000000001': 0,
      '0.000001': 1,
      '0.001000': 1000,
      '0': 0,
      '0.999000': 999000,
      '0.999999': 999999,
      '0.999999999': 999999,
      '1.000000001': 1000000,
      '1.000001': 1000001,
      '1.001000': 1001000,
      '1': 1000000,
      '1.999000': 1999000,
      '1.999999': 1999999,
      '1.999999999': 1999999,
      '-1350244992.023960108': -1350244992023960,
      '-1350244992.02396010': -1350244992023960,
      '-1350244992.0239601089': -1350244992023960,
      '-1350244992.3': -1350244992300000,
      '-1350244992': -1350244992000000,
      '1.': 1000000,
      '0.0': 0,
      '-1.': -1000000,
      '-1.0': -1000000,
      '-0.0': 0,
      '-0.1': -100000,
      '-0.01': -10000,
      '-0.99': -990000,
      '-0.98': -980000,
      '-1.1': -1100000,
      '-1.01': -1010000,
      '-2.99': -2990000,
      '-5.98': -5980000,
    };

    validTimes.forEach((str, micros) {
      test('parsePaxTime($str)', () {
        expect(parsePaxTime(str), microsecondsSinceEpoch(micros));
      });
    });

    const invalidTimes = {
      '',
      '.5',
      '-',
      '+',
      '-1.-1',
      '99999999999999999999999999999999999999999999999',
      '0.123456789abcdef',
      'foo',
      '𝟵𝟴𝟳𝟲𝟱.𝟰𝟯𝟮𝟭𝟬', // Unicode numbers (U+1D7EC to U+1D7F5)
      '98765﹒43210', // Unicode period (U+FE52);
    };

    for (final invalid in invalidTimes) {
      test('parsePaxTime($invalid)', () {
        expect(() => parsePaxTime(invalid), throwsA(isA<TarException>()));
      });
    }
  });

  group('BlockReader', () {
    late StreamController<List<int>> controller;

    setUp(() {
      controller = StreamController();
    });

    test('does not attach listener before needed', () async {
      final reader = BlockReader(controller.stream);
      expect(controller.hasListener, isFalse);

      final stream = reader.nextBlocks(10);
      expect(controller.hasListener, isFalse);

      stream.listen(null);
      // Should not attach synchronously
      expect(controller.hasListener, isFalse);

      await pumpEventQueue(times: 1);
      expect(controller.hasListener, isTrue);
    });

    test('emits individual blocks', () async {
      for (var i = 0; i < 10; i++) {
        controller.add(Uint8List(blockSize)..fillRange(0, blockSize, i));
      }

      final reader = BlockReader(controller.stream);

      for (var i = 0; i < 10; i++) {
        expect((await reader.nextBlock()).first, i);
      }
      await reader.close();
    });

    test('combines multiple chunks into a block', () async {
      controller
        ..add(Uint8List(blockSize - 10))
        ..add(Uint8List(blockSize + 20)..fillRange(0, blockSize + 10, 1));

      final reader = BlockReader(controller.stream);
      final firstBlock = await reader.nextBlock();

      expect(firstBlock[0], 0);
      expect(firstBlock[511], 1);

      final secondBlock = await reader.nextBlock();
      expect(secondBlock[0], 1);
      expect(secondBlock[511], 1);

      controller.close(); // ignore: unawaited_futures
      final thirdBlock = await reader.nextBlock();
      expect(thirdBlock.length, 10);

      expect(controller.hasListener, isFalse);
      await reader.close();
    });

    test('can pause and resume from saved chunk', () async {
      controller
        ..add(Uint8List(blockSize - 10))
        ..add(Uint8List(2 * blockSize + 10)..fillRange(0, blockSize + 10, 1));

      final reader = BlockReader(controller.stream);
      // ignore: cancel_subscriptions
      final subscription = reader.nextBlocks(3).listen(null);
      var eventCounter = 0;

      subscription.onData(expectAsync1((data) {
        eventCounter += data.length ~/ blockSize;

        // After the first block completed, we will trailing data. Ensure that
        // resuming in this state works!
        if (eventCounter == 1) {
          subscription.pause(Future.delayed(Duration.zero));
        }
      }, max: 3));

      await subscription.asFuture<void>();
      expect(eventCounter, 3);
      await reader.close();
    });

    test('can cancel subscriptions', () async {
      controller
        ..add(Uint8List(blockSize))
        ..add(Uint8List(blockSize));

      final reader = BlockReader(controller.stream);
      await reader.nextBlocks(2).first;
      await reader.close();
    });

    test('can pause stream subscriptions when all data has been emitted',
        () async {
      final reader = BlockReader(controller.stream);
      controller.add(Uint8List(blockSize * 3));
      await reader.nextBlock();

      late StreamSubscription<Uint8List> subscription;
      final didPause = Completer<void>();

      subscription = reader.nextBlocks(2).listen((_) {
        scheduleMicrotask(() {
          subscription.pause();
          didPause.complete();
        });
      });

      await didPause.future;
      await subscription.cancel();
      await reader.close();
    });
  });
}

Uint8List _bytes(String str) {
  return Uint8List.fromList(utf8.encode(str));
}
