import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:charcode/ascii.dart';

import 'common.dart';
import 'entry.dart';

/// A stream transformer turning byte-streams into a stream of tar entries.
///
/// You can iterate over entries in a tar archive like this:
///
/// ```dart
/// import 'dart:io';
/// import 'package:tar/tar.dart' as tar;
///
/// Future<void> main() async {
///   final tarFile = File('file.tar.gz')
///        .openRead()
///        // use gzip.decoder if you're reading .tar.gz files
///        .transform(gzip.decoder)
///        .transform(const tar.Reader());
///
///  await for (final entry in tarFile) {
///    print(entry.name);
///    print(await entry.transform(utf8.decoder).first);
///  }
/// }
/// ```
class Reader extends StreamTransformerBase<List<int>, Entry> {
  /// The maximum length for special files, such as extended PAX headers or long
  /// file names in GNU-tar.
  ///
  /// The content of those files has to be buffered in the reader until it
  /// reaches the next entry. To avoid memory-based denial-of-service attacks
  /// with large headers, this library only allows 1 KiB by default.
  /// This limit can be increased, which is rarely needed.
  final int maxSpecialFileLength;

  /// Creates a reader with a custom [maxSpecialFileLength].
  ///
  /// When using the default value, consider using the regular [reader] instead.
  const Reader({this.maxSpecialFileLength = defaultSpecialLength})
      : assert(maxSpecialFileLength >= blockSize);

  @override
  Stream<Entry> bind(Stream<List<int>> stream) {
    return _BoundTarStream(stream, maxSpecialFileLength).stream;
  }
}

/// A stream transformer turning byte-streams into a stream of tar entries.
///
/// You can iterate over entries in a tar archive like this:
///
/// ```dart
/// import 'dart:io';
/// import 'package:tar/tar.dart' as tar;
///
/// Future<void> main() async {
///   final tarFile = File('file.tar.gz')
///        .openRead()
///        // use gzip.decoder if you're reading .tar.gz files
///        .transform(gzip.decoder)
///        .transform(tar.reader);
///
///  await for (final entry in tarFile) {
///    print(entry.name);
///    print(await entry.transform(utf8.decoder).first);
///  }
/// }
/// ```
const reader = Reader();

class _BoundTarStream {
  // sync because we'll only add events in response to events that we receive.
  final _controller = StreamController<Entry>(sync: true);
  // We don't propagate pauses/resumes from the global [_controller] when we're
  // reading an entry, so we have to remember the state to do that later.
  var _controllerState = _ControllerState.idle;
  // Whether we're skipping input to get to the end of a tar block.
  bool _isWaitingForBlockToFinish = false;
  // Whether we've seen the end of the tar stream, indicated by two empty
  // blocks.
  bool _hasReachedEnd = false;

  StreamController<Uint8List>? _entryController;
  // The subscription to the input stream from the constructor. We only start to
  // listen when we have a listener to this stream, and we pause/resume the
  // subscription as necessary.
  late StreamSubscription<List<int>> _subscription;

  /// Extended PAX headers used for long names.
  ///
  /// See also: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html#tag_20_92_13_03
  final PaxHeaders _paxHeaders = PaxHeaders();

  FileType? _processingSpecialType;

  // When we're parsing a header, this stores collected header values. When
  // processing a special file type (e.g. extended headers), this buffer will
  // store the content of that file. We start by reading a header.
  Uint8List _buffer = Uint8List(blockSize);
  // The amount of bytes to read before we switch states (e.g. from headers to
  // entries to vice-versa)
  int _remainingBytes = blockSize;
  // The offset in the current block, used to track how much data to skip when
  // we go to the next block.
  int _offsetInBlock = 0;

  final int maxSpecialTypeLength;

  Stream<Entry> get stream => _controller.stream;

  _BoundTarStream(Stream<List<int>> stream, this.maxSpecialTypeLength) {
    _controller
      ..onPause = () {
        _setStateAndPropagate(_ControllerState.paused);
      }
      ..onResume = () {
        _setStateAndPropagate(_ControllerState.active);
      }
      ..onCancel = () {
        _setStateAndPropagate(_ControllerState.canceled);
      }
      ..onListen = () {
        _controllerState = _ControllerState.active;
        _subscription = stream.listen(
          (chunk) {
            try {
              _processChunk(chunk);
            } catch (e, s) {
              _controller.addError(e, s);
            }
          },
          onDone: () {
            if (!_hasReachedEnd) {
              _controller.addError(StateError('Unexpected end of input'));
            }
            _controller.close();
          },
          onError: _controller.addError,
        );
      };
  }

  void _setStateAndPropagate(_ControllerState state) {
    _controllerState = state;
    _propagateStateIfPossible();
  }

  void _propagateStateIfPossible() {
    // Don't pause or resume if we are processing an entry. Users are supposed
    // to pause/resume the entry stream instead.
    if (_entryController == null) {
      switch (_controllerState) {
        case _ControllerState.idle:
          throw AssertionError('Should not get back to idle.');
        case _ControllerState.active:
          if (_subscription.isPaused) _subscription.resume();
          break;
        case _ControllerState.paused:
          if (!_subscription.isPaused) _subscription.pause();
          break;
        case _ControllerState.canceled:
          _subscription.cancel();
          break;
      }
    }
  }

  /// Switches to a state in which we're skipping padding, if necessary.
  void _skipPadding() {
    if (_offsetInBlock != 0) {
      _remainingBytes = blockSize - _offsetInBlock;
      _isWaitingForBlockToFinish = true;
    }
  }

  void _processChunk(List<int> chunk) {
    var offset = 0;

    List<int> read(int amount) {
      final result = chunk.sublist(offset, offset + amount);
      _remainingBytes -= amount;
      offset += amount;
      _offsetInBlock = (_offsetInBlock + amount).toUnsigned(blockSizeLog2);

      return result;
    }

    void readSpecialFile(int availableBytes) {
      _buffer.setAll(_buffer.length - _remainingBytes, read(availableBytes));

      if (_remainingBytes == 0) {
        switch (_processingSpecialType) {
          case FileType.extendedHeader:
            _paxHeaders.newLocals(_readPaxHeader());
            break;
          case FileType.globalExtended:
            _paxHeaders.newGlobals(_readPaxHeader());
            break;
          // Fake a pax header for these two, they're otherwise equivalent
          case FileType.gnuLongLinkName:
            _paxHeaders.linkName = _readZeroTerminated();
            break;
          case FileType.gnuLongName:
            _paxHeaders.fileName = _readZeroTerminated();
            break;
          default:
            throw AssertionError('Only headers are special types');
        }

        // Resume by parsing the next header, which is then a regular one
        _skipPadding();
        _processingSpecialType = null;
        if (_buffer.length != blockSize) _buffer = Uint8List(blockSize);
        _remainingBytes = blockSize;
      }
    }

    void readHeader(int availableBytes) {
      _buffer.setAll(blockSize - _remainingBytes, read(availableBytes));
      if (_remainingBytes == 0) {
        // Header is complete, start emitting an entry. Note that we don't have
        // to skip padding as headers always have the length of one block.
        if (_buffer.isAllZeroes) {
          _hasReachedEnd = true;
          return;
        }

        final header = Header.fromBlock(_buffer, headers: _paxHeaders);
        final type = header.type;
        if (!_transparentFileTypes.contains(type)) {
          final entry = _entryController = StreamController(
            sync: true,
            onListen: () {
              if (_subscription.isPaused) _subscription.resume();
            },
            onPause: _subscription.pause,
            onResume: _subscription.resume,
          );
          _remainingBytes = header.size;
          _controller.add(Entry(header, entry.stream));
        } else {
          final length = header.size;
          if (length > maxSpecialTypeLength) {
            _controller.addError(StateError(
              'This tar file contains an extended PAX-header with a length of '
              '$length bytes. Since these headers have to be buffered, this '
              'tar reader permits a maximum length of $maxSpecialTypeLength. \n'
              'You can increase this limit when constructing a tar.Reader().',
            ));
          }

          _remainingBytes = header.size;
          _buffer = Uint8List(header.size);
          _processingSpecialType = type;
        }
      }
    }

    while (offset < chunk.length) {
      if (_hasReachedEnd) break;

      var remainingInChunk = chunk.length - offset;

      if (_isWaitingForBlockToFinish) {
        final remainingInBlock = blockSize - _offsetInBlock;

        if (remainingInBlock <= remainingInChunk) {
          // Skip the block padding, then go on with the next block
          offset += remainingInBlock;
          _offsetInBlock += remainingInBlock;
          remainingInChunk -= remainingInBlock;
          _isWaitingForBlockToFinish = false;
        } else {
          // The rest of this chunk is padding data that we can ignore.
          _offsetInBlock += remainingInChunk;
          _subscription.resume();
          break;
        }
      }

      final availableBytes = min(_remainingBytes, remainingInChunk);

      if (_processingSpecialType != null) {
        readSpecialFile(availableBytes);
      } else {
        final currentEntry = _entryController;
        if (currentEntry == null) {
          // If there's no current entry, we're reading a header
          readHeader(availableBytes);
        } else {
          // Otherwise, add to the current entry
          final outputChunk = read(availableBytes);
          currentEntry.add(outputChunk.asUint8List());

          if (_remainingBytes == 0) {
            // Entry is done. Close and start by reading the next header
            currentEntry.close();
            _entryController = null;
            _propagateStateIfPossible();

            _skipPadding();
            _remainingBytes = blockSize;

            _paxHeaders.clearLocals();
          }
        }
      }
    }
  }

  /// Decodes the content of an extended pax header entry.
  ///
  /// For details, see https://pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html#tag_20_92_13_03
  Map<String, String> _readPaxHeader() {
    var offset = 0;
    final map = <String, String>{};

    while (offset < _buffer.length) {
      // At the start of an entry, expect its length
      var length = 0;
      var currentChar = _buffer[offset];
      var charsInLength = 0;
      while (currentChar >= $0 && currentChar <= $9) {
        length = length * 10 + currentChar - $0;
        charsInLength++;
        currentChar = _buffer[++offset];
      }

      if (length == 0) {
        throw StateError('Could not parse extended pax header: Got entry with '
            'zero length.');
      }

      // Skip the whitespace
      if (currentChar != $space) {
        throw StateError('Could not parse extended pax header: Expected '
            'whitespace after length indicator.');
      }
      currentChar = _buffer[++offset];

      // Read the key
      final keyBuffer = StringBuffer();
      while (currentChar != $equal) {
        keyBuffer.writeCharCode(currentChar);
        currentChar = _buffer[++offset];
      }
      final key = keyBuffer.toString();
      // Skip over the equals sign
      offset++;

      // Now, read the value from the known size. We subtract 3 for the space,
      // the equals and the trailing newline
      final lengthOfValue = length - 3 - keyBuffer.length - charsInLength;
      final value =
          utf8.decode(_buffer.sublist(offset, offset + lengthOfValue));
      // Ignore unrecognized headers to avoid unbounded growth of the global
      // header map.
      if (supportedPaxHeaders.contains(key)) {
        map[key] = value;
      }

      // Skip over value and trailing newline
      offset += lengthOfValue + 1;
    }

    return map;
  }

  String _readZeroTerminated() {
    return readZeroTerminated(_buffer, 0, _buffer.length);
  }
}

// Archive entries with those types are hidden from users
const _transparentFileTypes = {
  FileType.extendedHeader,
  FileType.globalExtended,
  FileType.gnuLongLinkName,
  FileType.gnuLongName,
};

enum _ControllerState {
  idle,
  active,
  paused,
  canceled,
}

extension on Uint8List {
  bool get isAllZeroes {
    for (var i = 0; i < length; i++) {
      if (this[i] != 0) return false;
    }
    return true;
  }
}
