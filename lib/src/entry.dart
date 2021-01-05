import 'dart:async';
import 'dart:typed_data';

import 'package:charcode/charcode.dart';

import 'common.dart';

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
  FileType get type => header.type;

  /// The content size of this entry, in bytes.
  int get size => header.size;

  /// Time of the last modification of this file, as indicated in the [header].
  DateTime get lastModified => header.lastModified;

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

class Header {
  /// The name of the tar entry.
  final String name;

  /// The file mode of the entry.
  ///
  /// This corresponds to `FileStat.mode` in `dart:io`.
  final int mode;

  /// ID of the user creating this file, or `0` if unknown.
  final int uid;

  /// Group-ID of the user creating this file, or `0` if unknown.
  final int gid;

  /// Size of the entry, in bytes.
  ///
  /// When writing streams with unknown size, set this to a negative value. In
  /// that case, the writer will determine the correct size.
  final int size;

  /// The time where this file was last modified.
  final DateTime lastModified;

  /// The checksum of this header itself.
  ///
  /// This library does not currently verify checksums, but the writer will
  /// generate correct checksums.
  final int checksum;

  /// The [FileType] of this entry.
  final FileType type;

  /// The link target, if this entry is a link.
  final String? linkName;

  /// The tar version field, should always be `0`.
  final int version;

  /// Name of the user creating this file.
  final String? userName;

  /// Name of the group creating this file.
  final String? groupName;

  Header({
    required this.name,
    required this.mode,
    this.version = 0,
    this.type = FileType.regular,
    this.userName = 'root',
    this.groupName = 'root',
    this.uid = 0,
    this.gid = 0,
    this.size = -1,
    this.checksum = 0,
    this.linkName,
    DateTime? lastModified,
  }) : lastModified = lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Reads a tar header from a header block.
  ///
  /// The header block must be stored in [data] and have a byte-length of 512.
  /// The optional [paxHeaders] map can be used to read some fields from
  /// extended PAX-headers.
  factory Header.fromBlock(
    Uint8List data, {
    PaxHeaders? headers,
  }) {
    if (data.length != blockSize) {
      throw ArgumentError.value(
          data, 'data', 'Must have a length of $blockSize');
    }

    var name = headers?.fileName ?? readZeroTerminated(data, 0, 100);
    final mode = _readOctInt(data, 100, 8);
    final uid = _readOctInt(data, 108, 8);
    final gid = _readOctInt(data, 116, 8);
    final size = headers?.size ?? _readOctInt(data, 124, 12);
    final mtime =
        DateTime.fromMillisecondsSinceEpoch(_readOctInt(data, 136, 12) * 1000);
    final checksum = _readOctInt(data, 148, 8);
    final type = const {
          regtype: FileType.regular,
          aregtype: FileType.regular,
          linktype: FileType.link,
          dirtype: FileType.directory,
          globalExtended: FileType.globalExtended,
          extendedHeader: FileType.extendedHeader,
          gnuTypeLongLinkName: FileType.gnuLongLinkName,
          gnuTypeLongName: FileType.gnuLongName,
        }[data[156]] ??
        FileType.unsupported;
    final nameLink = headers?.linkName ?? readZeroTerminated(data, 157, 100);

    var version = 0;
    var uname = headers?[paxHeaderUname];
    var gname = headers?[paxHeaderGname];

    if (data.hasUstarMagic) {
      version = _readOctInt(data, 263, 2);
      uname ??= readZeroTerminated(data, 265, 32);
      gname ??= readZeroTerminated(data, 297, 32);

      if (headers == null || !headers.containsKey(paxHeaderPath)) {
        // Try to append a prefix if the file name wasn't enforced
        final prefix = readZeroTerminated(data, 345, 155);
        if (prefix.isNotEmpty) {
          name = '$prefix/$name';
        }
      }
    }

    return Header(
      name: name,
      mode: mode,
      uid: uid,
      gid: gid,
      size: size,
      lastModified: mtime,
      checksum: checksum,
      type: type,
      linkName: nameLink,
      version: version,
      userName: uname,
      groupName: gname,
    );
  }

  static int _readOctInt(Uint8List data, int offset, int length) {
    var result = 0;
    var multiplier = 1;

    for (var i = length - 1; i >= 0; i--) {
      final charCode = data[offset + i];
      // Some tar implementations add a \0 or space at the end, ignore that
      if (charCode < $0 || charCode > $9) continue;

      final digit = charCode - $0;
      result += digit * multiplier;
      multiplier <<= 3; // Multiply by the base, 8
    }

    return result;
  }
}

enum FileType {
  /// A regular file entry.
  regular,

  /// A link to another entry in the tar file
  link,

  /// An entry used to indicate directories
  directory,

  /// An entry with an unknown typeflag.
  unsupported,

  /// A synthentic entry storing the header of the next entry.
  ///
  /// No entry with this type will be reported by the reader, they're handled
  /// internally.
  extendedHeader,

  /// A synthentic entry storing headers of upcoming entries.
  ///
  /// No entry with this type will be reported by the reader, they're handled
  /// internally.
  globalExtended,

  /// A synthentic entry storing the name of the next entry.
  ///
  /// No entry with this type will be reported by the reader, they're handled
  /// internally.
  gnuLongName,

  /// A synthentic entry storing the link target of the next entry.
  ///
  /// No entry with this type will be reported by the reader, they're handled
  /// internally.
  gnuLongLinkName,
}

extension on Uint8List {
  bool get hasUstarMagic {
    // Ensure that the header has "ustar" as magic bytes
    for (var i = 0; i < magic.length; i++) {
      if (this[257 + i] != magic[i]) {
        return false;
      }
    }

    return true;
  }
}
