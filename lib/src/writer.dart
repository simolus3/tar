import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:charcode/ascii.dart';

import 'common.dart';
import 'entry.dart';

import 'package:synchronized/synchronized.dart';

/// A sink emitting encoded tar files.
///
/// For instance, you can use this to write a tar file:
///
/// ```dart
/// import 'package:tar/tar.dart' as tar;
///
/// Future<void> main() async {
///   Stream<tar.TarEntry> entries = Stream.value(
///     tar.MemoryEntry(
///       tar.Header(
///         name: 'example.txt',
///         mode: int.parse('644', radix: 8),
///       ),
///       utf8.encode('This is the content of the tar file'),
///     ),
///   );
///
///   final output = File('/tmp/test.tar').openWrite();
///   await entries.pipe(tar.WritingSink(output));
/// }
/// ```
///
/// Note that, if you don't set the [Header.size], outgoing tar entries need to
/// be buffered once, which decreases performance.
///
/// See also:
///  - [StreamSink]
class WritingSink extends StreamSink<Entry> {
  final StreamSink<List<int>> _output;

  int _paxHeaderCount = 0;
  bool _closed = false;
  final Completer<void> _done = Completer();

  int _pendingOperations = 0;
  final Lock _lock = Lock();

  WritingSink(this._output);

  @override
  Future get done => _done.future;

  @override
  Future<void> add(Entry event) {
    if (_closed) {
      throw StateError('Cannot add event after close was called');
    }
    return _doWork(() => _safeAdd(event));
  }

  Future<void> _doWork(FutureOr Function() work) async {
    _pendingOperations++;
    try {
      await _lock.synchronized(work);
    } finally {
      _pendingOperations--;
    }

    if (_closed && _pendingOperations == 0) {
      _done.complete();
    }
  }

  Future<void> _safeAdd(Entry event) async {
    final header = event.header;
    var size = header.size;
    Uint8List? bufferedData;
    if (size < 0) {
      final builder = BytesBuilder();
      await event.forEach(builder.add);
      bufferedData = builder.takeBytes();
      size = bufferedData.length;
    }

    var nameBytes = utf8.encode(header.name);
    var linkBytes = utf8.encode(header.linkName ?? '');

    // We only get 100 chars for the name and link name. If they are longer, we
    // have to insert an entry just to store the names.
    final paxHeader = <String, List<int>>{};
    if (nameBytes.length > 100) {
      paxHeader['path'] = nameBytes;
      nameBytes = nameBytes.sublist(0, 100);
    }
    if (linkBytes.length > 100) {
      paxHeader['linkpath'] = linkBytes;
      linkBytes = linkBytes.sublist(0, 100);
    }

    if (paxHeader.isNotEmpty) {
      await _writePaxHeader(paxHeader);
    }

    final headerBlock = Uint8List(blockSize)
      ..setAll(0, nameBytes)
      ..setUint(header.mode, 100, 8)
      ..setUint(header.uid, 108, 8)
      ..setUint(header.gid, 116, 8)
      ..setUint(size, 124, 12)
      ..setUint(header.lastModified.millisecondsSinceEpoch ~/ 1000, 136, 12)
      ..[156] = header.type.char
      ..setAll(157, linkBytes)
      ..setAll(257, magic)
      ..setUint(0, 263, 2)
      // To calculate the checksum, we first fill the checksum range with spaces
      ..setAll(148, List.filled(8, $space));

    // Then, we take the sum of the header
    var checksum = 0;
    for (final byte in headerBlock) {
      checksum += byte;
    }
    headerBlock..setUint(checksum, 148, 8);

    _output.add(headerBlock);

    // Write content.
    if (bufferedData != null) {
      _output.add(bufferedData);
    } else {
      await for (final chunk in event) {
        _output.add(chunk);
      }
    }

    final padding = -size % blockSize;
    _output.add(Uint8List(padding));
  }

  /// Writes an extended pax header.
  ///
  /// https://pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html#tag_20_92_13_03
  Future<void> _writePaxHeader(Map<String, List<int>> values) {
    final buffer = BytesBuilder();
    // format of each entry: "%d %s=%s\n", <length>, <keyword>, <value>
    // note that the length includes the trailing \n and the length description
    // itself.
    values.forEach((key, value) {
      final encodedKey = utf8.encode(key);
      // +3 for the whitespace, the equals and the \n
      final payloadLength = encodedKey.length + value.length + 3;
      var indicatedLength = payloadLength;

      // The indicated length contains the length (in decimals) itself. So if
      // we had payloadLength=9, then we'd prefix a 9 at which point the whole
      // string would have a length of 10. If that happens, increment length.
      var actualLength = payloadLength + indicatedLength.toString().length;

      while (actualLength != indicatedLength) {
        indicatedLength++;
        indicatedLength.toString().length;
      }

      // With that sorted out, let's add the line
      buffer
        ..add(utf8.encode(indicatedLength.toString()))
        ..addByte($space)
        ..add(encodedKey)
        ..addByte($equal)
        ..add(value)
        ..addByte($lf); // \n
    });

    final file = MemoryEntry(
      Header(
        name: 'PaxHeader/${_paxHeaderCount++}',
        mode: 0,
        type: FileType.extendedHeader,
      ),
      buffer.takeBytes(),
    );
    return _safeAdd(file);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _output.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<Entry> stream) async {
    await for (final entry in stream) {
      await add(entry);
    }
  }

  @override
  Future close() async {
    if (!_closed) {
      _closed = true;

      // Add two empty blocks at the end.
      await _doWork(() {
        final empty = Uint8List(blockSize);
        _output.add(empty);
        _output.add(empty);
      });
      await _output.close();
    }

    return done;
  }
}

extension on Uint8List {
  void setUint(int value, int position, int length) {
    // Values are encoded as octal string, terminated and left-padded with
    // space chars.

    // Set terminating space char.
    this[position + length - 1] = $space;

    // Write as octal value, we write from right to left
    var number = value;
    var needsExplicitZero = number == 0;

    for (var pos = position + length - 2; pos >= position; pos--) {
      if (number != 0) {
        // Write the last octal digit of the number (e.g. the last 4 bits)
        this[pos] = (number & 7) + $0;
        // then drop the last digit (divide by 8 = 2³)
        number >>= 3;
      } else if (needsExplicitZero) {
        this[pos] = $0;
        needsExplicitZero = false;
      } else {
        // done, left-pad with spaces
        this[pos] = $space;
      }
    }
  }
}

extension FileTypeChar on FileType {
  int get char {
    switch (this) {
      case FileType.regular:
        return aregtype;
      case FileType.link:
        return linktype;
      case FileType.directory:
        return dirtype;
      case FileType.extendedHeader:
        return extendedHeader;
      case FileType.globalExtended:
        return globalExtended;
      case FileType.unsupported:
      case FileType.gnuLongLinkName:
      case FileType.gnuLongName:
        throw UnsupportedError('Unsupported file type');
    }
  }
}
