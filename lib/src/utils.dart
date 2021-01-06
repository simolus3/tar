import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:charcode/charcode.dart';
import 'package:chunked_stream/chunked_stream.dart';

import 'constants.dart';
import 'exception.dart';

const _checksumEnd = checksumOffset + checksumLength;
const _checksumPlaceholder = $space;

extension ByteBufferUtils on Uint8List {
  String readString(int offset, int maxLength) {
    return readStringOrNullIfEmpty(offset, maxLength) ?? '';
  }

  String? readStringOrNullIfEmpty(int offset, int maxLength) {
    var sublistView = sublist(offset, offset + maxLength);
    var contentLength = sublistView.indexOf(0);
    // If there's no \0, assume that the string fills the whole segment
    if (contentLength.isNegative) contentLength = maxLength;

    if (contentLength == 0) return null;

    sublistView = sublistView.sublist(0, contentLength);
    try {
      return utf8.decode(sublistView);
    } on FormatException {
      return String.fromCharCodes(sublistView).trim();
    }
  }

  /// Parse an octal string encoded from index [offset] with the maximum length
  /// [length].
  int readOctal(int offset, int length) {
    var result = 0;
    var multiplier = 1;

    for (var i = length - 1; i >= 0; i--) {
      final charCode = this[offset + i];
      // Some tar implementations add a \0 or space at the end, ignore that
      if (charCode < $0 || charCode > $9) continue;

      // Obtain the numerical value of this digit
      final digit = charCode - $0;
      result += digit * multiplier;
      multiplier <<= 3; // Multiply by the base, 8
    }

    return result;
  }

  /// Parses an encoded int, either as base-256 or octal.
  ///
  /// This function may return negative numbers.
  int readNumeric(int offset, int length) {
    // Check for base-256 (binary) format first. If the first bit is set, then
    // all following bits constitute a two's complement encoded number in big-
    // endian byte order.
    final firstByte = this[offset];
    if (firstByte & 0x80 != 0) {
      // Handling negative numbers relies on the following identity:
      // -a-1 == ~a
      //
      // If the number is negative, we use an inversion mask to invert the
      // date bytes and treat the value as an unsigned number.
      final inverseMask = firstByte & 0x40 != 0 ? 0xff : 0x00;

      var x = firstByte & 0x7f; // Ignore signal bit in the first byte

      for (var i = 1; i < length; i++) {
        var byte = this[offset + i];
        byte ^= inverseMask;

        x = x << 8 | byte;
      }

      return inverseMask == 0xff ? ~x : x;
    }

    return readOctal(offset, length);
  }

  int computeUnsignedHeaderChecksum() {
    var result = 0;

    for (var i = 0; i < length; i++) {
      result += (i < checksumOffset || i >= _checksumEnd)
          ? this[i] // Not in range of where the checksum is written
          : _checksumPlaceholder;
    }

    return result;
  }

  int computeSignedHeaderChecksum() {
    var result = 0;

    for (var i = 0; i < length; i++) {
      // Note that _checksumPlaceholder.toSigned(8) == _checksumPlaceholder
      result += (i < checksumOffset || i >= _checksumEnd)
          ? this[i].toSigned(8)
          : _checksumPlaceholder;
    }

    return result;
  }

  bool matchesHeader(List<int> header, {int offset = magicOffset}) {
    for (var i = 0; i < header.length; i++) {
      if (this[offset + i] != header[i]) return false;
    }

    return true;
  }
}

bool isNotAscii(int i) => i > 128;

/// Takes a [paxTimeString] of the form %d.%d as described in the PAX
/// specification. Note that this implementation allows for negative timestamps,
/// which is allowed for by the PAX specification, but not always portable.
///
/// Note that Dart's [DateTime] class only allows us to give up to microsecond
/// precision, which implies that we cannot parse all the digits in since PAX
/// allows for nanosecond level encoding.
DateTime parsePaxTime(String paxTimeString) {
  const maxMicroSecondDigits = 6;

  /// Split [paxTimeString] into seconds and sub-seconds parts.
  var secondsString = paxTimeString;
  var microSecondsString = '';
  final position = paxTimeString.indexOf('.');
  if (position >= 0) {
    secondsString = paxTimeString.substring(0, position);
    microSecondsString = paxTimeString.substring(position + 1);
  }

  /// Parse the seconds.
  final seconds = int.tryParse(secondsString);
  if (seconds == null) {
    throw TarException.header('Invalid PAX time $paxTimeString detected!');
  }

  if (microSecondsString.replaceAll(RegExp('[0-9]'), '') != '') {
    throw TarException.header(
        'Invalid nanoseconds $microSecondsString detected');
  }

  microSecondsString = microSecondsString.padRight(maxMicroSecondDigits, '0');
  microSecondsString = microSecondsString.substring(0, maxMicroSecondDigits);

  var microSeconds =
      microSecondsString.isEmpty ? 0 : int.parse(microSecondsString);
  if (paxTimeString.startsWith('-')) microSeconds = -microSeconds;

  return DateTime.fromMicrosecondsSinceEpoch(
      microSeconds + seconds * pow(10, 6).toInt());
}

DateTime secondsSinceEpoch(int timestamp) {
  return DateTime.fromMillisecondsSinceEpoch(timestamp * 100);
}

int numBlocks(int fileSize) {
  if (fileSize % blockSize == 0) return fileSize ~/ blockSize;

  return fileSize ~/ blockSize + 1;
}

extension ToTyped on List<int> {
  Uint8List asUint8List() {
    // Flow analysis doesn't work on this.
    final $this = this;
    return $this is Uint8List ? $this : Uint8List.fromList(this);
  }

  bool get isAllZeroes {
    for (var i = 0; i < length; i++) {
      if (this[i] != 0) return false;
    }

    return true;
  }
}

extension ChunkedStreamUtils on ChunkedStreamIterator<int> {
  Future<Uint8List> readAsBlock(int size) async {
    return (await read(size)).asUint8List();
  }
}
