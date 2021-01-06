import 'dart:async';

import 'constants.dart';
import 'header.dart';

/// An entry in a tar file.
///
/// Usually, tar entries are read from a stream, and they're bound to the stream
/// from which they've been read. This means that they can only be read once,
/// and that only one [Entry] is active at a time.
class Entry extends Stream<List<int>> {
  /// The parsed [Header] of this tar entry.
  final Header header;
  final Stream<List<int>> _dataStream;

  /// The name of this entry, as indicated in the header or a previous pax
  /// entry.
  String get name => header.name;

  /// The type of tar entry (file, directory, etc.).
  TypeFlag get type => header.typeFlag;

  /// The content size of this entry, in bytes.
  int get size => header.size;

  /// Time of the last modification of this file, as indicated in the [header].
  DateTime get modified => header.modified;

  Entry(this.header, this._dataStream);

  /// Creates an in-memory tar entry from the [header] and the [data] to store.
  factory Entry.data(Header header, List<int> data) {
    return Entry(header, Stream.value(data));
  }

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _dataStream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
