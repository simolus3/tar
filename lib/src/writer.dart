import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'charcodes.dart';
import 'constants.dart';
import 'entry.dart';
import 'format.dart';
import 'header.dart';
import 'utils.dart';

class _WritingTransformer extends StreamTransformerBase<TarEntry, List<int>> {
  final OutputFormat format;

  const _WritingTransformer(this.format);

  @override
  Stream<List<int>> bind(Stream<TarEntry> stream) {
    // sync because the controller proxies another stream
    final controller = StreamController<List<int>>(sync: true);
    controller.onListen = () {
      stream.pipe(tarWritingSink(controller, format: format));
    };

    return controller.stream;
  }
}

/// A stream transformer writing tar entries as byte streams.
///
/// Regardless of the input stream, the stream returned by this
/// [StreamTransformer.bind] is a single-subscription stream.
/// Apart from that, subscriptions, cancellations, pauses and resumes are
/// propagated as one would expect from a [StreamTransformer].
///
/// When piping the resulting stream into a [StreamConsumer], consider using
/// [tarWritingSink] directly.
/// To change the output format of files with long names, use [tarWriterWith].
const StreamTransformer<TarEntry, List<int>> tarWriter =
    _WritingTransformer(OutputFormat.pax);

/// Creates a stream transformer writing tar entries as byte streams, with
/// custom encoding options.
///
/// The [format] [OutputFormat] can be used to select the way tar entries with
/// long file or link names are written. By default, the writer will emit an
/// extended PAX header for the file ([OutputFormat.pax]).
/// Alternatively, [OutputFormat.gnuLongName] can be used to emit special tar
/// entries with the [TypeFlag.gnuLongName] type.
///
/// Regardless of the input stream, the stream returned by this
/// [StreamTransformer.bind] is a single-subscription stream.
/// Apart from that, subscriptions, cancellations, pauses and resumes are
/// propagated as one would expect from a [StreamTransformer].
///
/// When using the default options, prefer using the constant [tarWriter]
/// instead.
StreamTransformer<TarEntry, List<int>> tarWriterWith(
    {OutputFormat format = OutputFormat.pax}) {
  return _WritingTransformer(format);
}

/// Create a sink emitting encoded tar files to the [output] sink.
///
/// For instance, you can use this to write a tar file:
///
/// ```dart
/// import 'dart:convert';
/// import 'dart:io';
/// import 'package:tar/tar.dart';
///
/// Future<void> main() async {
///   Stream<TarEntry> entries = Stream.value(
///     TarEntry.data(
///       TarHeader(
///         name: 'example.txt',
///         mode: int.parse('644', radix: 8),
///       ),
///       utf8.encode('This is the content of the tar file'),
///     ),
///   );
///
///   final output = File('/tmp/test.tar').openWrite();
///   await entries.pipe(tarWritingSink(output));
///  }
/// ```
///
/// Note that, if you don't set the [TarHeader.size], outgoing tar entries need
/// to be buffered once, which decreases performance.
///
/// The [format] argument can be used to control how long file names are written
/// in the tar archive. For more details, see the options in [OutputFormat].
///
/// See also:
///  - [tarWriter], a stream transformer using this sink
///  - [StreamSink]
StreamSink<TarEntry> tarWritingSink(StreamSink<List<int>> output,
    {OutputFormat format = OutputFormat.pax}) {
  return _WritingSink(output, format);
}

/// This option controls how long file and link names should be written.
///
/// This option can be passed to writer in [tarWritingSink] or[tarWriterWith].
enum OutputFormat {
  /// Generates an extended PAX headers to encode files with a long name.
  ///
  /// This is the default option.
  pax,

  /// Generates [TypeFlag.gnuLongName] or [TypeFlag.gnuLongLink] entries when
  /// encoding files with a long name.
  ///
  /// When this option is set, `package:tar` will not emit PAX headers which
  /// may improve compatibility with some legacy systems like old 7zip versions.
  ///
  /// Note that this format can't encode large file sizes or long user names.
  /// Tar entries can't be written if
  ///  * their [TarHeader.userName] is longer than 31 bytes in utf8,
  ///  * their [TarHeader.groupName] is longer than 31 bytes in utf8, or,
  ///  * their [TarEntry.contents] are larger than 8589934591 byte (around
  ///    8 GiB).
  ///
  /// Attempting to encode such file will throw an [UnsupportedError].
  gnuLongName,
}

class _WritingSink extends StreamSink<TarEntry> {
  final StreamSink<List<int>> _output;
  final OutputFormat format;

  final _headerEncoder = _TarHeaderEncoder();
  bool _closed = false;
  final Completer<Object?> _done = Completer();

  int _pendingOperations = 0;
  Future<void> _ready = Future.value();

  _WritingSink(this._output, this.format);

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> add(TarEntry event) {
    if (_closed) {
      throw StateError('Cannot add event after close was called');
    }
    return _doWork(() => _safeAdd(event));
  }

  Future<void> _doWork(FutureOr<void> Function() work) {
    _pendingOperations++;
    // Chain futures to make sure we only write one entry at a time.
    return _ready = _ready
        .then((_) => work())
        .catchError(_output.addError)
        .whenComplete(() {
      _pendingOperations--;

      if (_closed && _pendingOperations == 0) {
        _done.complete(_output.close());
      }
    });
  }

  Uint8List _headerBytes(TarHeader header, int size) {
    final builder = BytesBuilder();

    var nameBytes = utf8.encode(header.name);
    var linkBytes = utf8.encode(header.linkName ?? '');
    var gnameBytes = utf8.encode(header.groupName ?? '');
    var unameBytes = utf8.encode(header.userName ?? '');

    // We only get 100 chars for the name and link name. If they are longer, we
    // have to insert an entry just to store the names. Some tar implementations
    // expect them to be zero-terminated, so use 99 chars to be safe.
    final paxHeader = <String, List<int>>{};

    if (nameBytes.length > 99) {
      paxHeader[paxPath] = nameBytes;
      nameBytes = nameBytes.sublist(0, 99);
    }
    if (linkBytes.length > 99) {
      paxHeader[paxLinkpath] = linkBytes;
      linkBytes = linkBytes.sublist(0, 99);
    }

    // It's even worse for users and groups, where we only get 31 usable chars.
    if (gnameBytes.length > 31) {
      paxHeader[paxGname] = gnameBytes;
      gnameBytes = gnameBytes.sublist(0, 31);
    }
    if (unameBytes.length > 31) {
      paxHeader[paxUname] = unameBytes;
      unameBytes = unameBytes.sublist(0, 31);
    }

    if (size > maxIntFor12CharOct) {
      paxHeader[paxSize] = ascii.encode(size.toString());
    }

    void addHeaderAndData(_HeaderAndData e) {
      builder.add(_headerBytes(e.header, e.data.length));
      builder.add(e.data);
      builder.add(_paddingBytes(e.data.length));
    }

    if (paxHeader.isNotEmpty) {
      if (format == OutputFormat.pax) {
        addHeaderAndData(_headerEncoder._encodePaxHeader(paxHeader));
      } else {
        _headerEncoder._encodeGnuLongName(paxHeader).forEach(addHeaderAndData);
      }
    }

    final headerBlock = Uint8List(blockSize)
      ..setAll(0, nameBytes)
      ..setUint(header.mode, 100, 8)
      ..setUint(header.userId, 108, 8)
      ..setUint(header.groupId, 116, 8)
      ..setUint(size, 124, 12)
      ..setUint(header.modified.millisecondsSinceEpoch ~/ 1000, 136, 12)
      ..[156] = typeflagToByte(header.typeFlag)
      ..setAll(157, linkBytes)
      ..setAll(257, magicUstar)
      ..setUint(0, 263, 2) // version
      ..setAll(265, unameBytes)
      ..setAll(297, gnameBytes)
      // To calculate the checksum, we first fill the checksum range with spaces
      ..setAll(148, List.filled(8, $space));

    // Then, we take the sum of the header
    var checksum = 0;
    for (final byte in headerBlock) {
      checksum += byte;
    }
    headerBlock.setUint(checksum, 148, 8);

    if (builder.isEmpty) {
      return headerBlock;
    } else {
      builder.add(headerBlock);
      return builder.takeBytes();
    }
  }

  Future<void> _safeAdd(TarEntry event) async {
    final header = event.header;
    var size = header.size;
    Uint8List? bufferedData;
    if (size < 0) {
      final builder = BytesBuilder();
      await event.contents.forEach(builder.add);
      bufferedData = builder.takeBytes();
      size = bufferedData.length;
    }

    _output.add(_headerBytes(header, size));

    // Write content.
    if (bufferedData != null) {
      _output.add(bufferedData);
    } else {
      await event.contents.forEach(_output.add);
    }

    _output.add(_paddingBytes(size));
  }

  Uint8List _paddingBytes(int size) {
    final padding = -size % blockSize;
    return Uint8List(padding);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _output.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<TarEntry> stream) async {
    await for (final entry in stream) {
      await add(entry);
    }
  }

  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;

      // Add two empty blocks at the end.
      await _doWork(() {
        _output.add(zeroBlock);
        _output.add(zeroBlock);
      });
    }

    return done;
  }
}

class _TarHeaderEncoder {
  int _paxHeaderCount = 0;

  /// Encodes an extended pax header.
  ///
  /// https://pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html#tag_20_92_13_03
  _HeaderAndData _encodePaxHeader(Map<String, List<int>> values) {
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
        actualLength = payloadLength + indicatedLength.toString().length;
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

    final paxData = buffer.takeBytes();
    return _HeaderAndData(
      HeaderImpl.internal(
        format: TarFormat.pax,
        modified: millisecondsSinceEpoch(0),
        name: 'PaxHeader/${_paxHeaderCount++}',
        mode: 0,
        size: paxData.length,
        typeFlag: TypeFlag.xHeader,
      ),
      paxData,
    );
  }

  Iterable<_HeaderAndData> _encodeGnuLongName(
      Map<String, List<int>> values) sync* {
    // Ensure that a file that can't be written in the GNU format is not written
    const allowedKeys = {paxPath, paxLinkpath};
    final invalidOptions = values.keys.toSet()..removeAll(allowedKeys);
    if (invalidOptions.isNotEmpty) {
      throw UnsupportedError(
        'Unsupporteed entry for OutputFormat.gnu. It uses long fields that '
        "can't be represented: $invalidOptions. \n"
        'Try using OutputFormat.pax instead.',
      );
    }

    final name = values[paxPath];
    final linkName = values[paxLinkpath];

    _HeaderAndData create(List<int> name, TypeFlag flag) {
      return _HeaderAndData(
        HeaderImpl.internal(
          name: '././@LongLink',
          modified: millisecondsSinceEpoch(0),
          format: TarFormat.gnu,
          typeFlag: flag,
        ),
        name,
      );
    }

    if (name != null) {
      yield create(name, TypeFlag.gnuLongName);
    }
    if (linkName != null) {
      yield create(linkName, TypeFlag.gnuLongLink);
    }
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

class _HeaderAndData {
  final TarHeader header;
  final List<int> data;

  _HeaderAndData(this.header, this.data);
}
