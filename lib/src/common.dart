import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:charcode/ascii.dart';

// Source of these constants: https://www.gnu.org/software/tar/manual/html_node/Standard.html
const magic = [$u, $s, $t, $a, $r, 0];
const regtype = $0; // '0' in C
const aregtype = 0; // '\0' in C
const linktype = $1;
const dirtype = $5;
const gnuTypeLongName = $L;
const gnuTypeLongLinkName = $K;
const globalExtended = $g;
const extendedHeader = $x;
const blockSize = 512;
const blockSizeLog2 = 9;
const maxIntFor12CharOct = 0x1ffffffff; // 777 7777 7777 in oct

// https://pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html#tag_20_92_13_03
const paxHeaderLinkName = 'linkpath';
const paxHeaderPath = 'path';
const paxHeaderUname = 'uname';
const paxHeaderGname = 'gname';
const paxHeaderSize = 'size';

/// These are the pax headers considered when reading tar files.
///
/// Other pax headers are dropped in the reader to avoid memory-based DOS
/// attacks. We already limit the size of a headers file by default, but an
/// attacker could provide many small global header files with bogus keys, which
/// we'd all have to store.
/// With this approach, we can ensure that the reader's buffer will have an
/// upper bound of `(supportedPaxHeaders.length + 1) * maxHeaderSize`.
const supportedPaxHeaders = {
  paxHeaderLinkName,
  paxHeaderPath,
  paxHeaderUname,
  paxHeaderGname,
  paxHeaderSize,
};

const defaultSpecialLength = blockSize * 2;

extension ToTyped on List<int> {
  Uint8List asUint8List() {
    // Flow typing doesn't work on this
    final $this = this;
    return $this is Uint8List ? $this : Uint8List.fromList($this);
  }
}

String readZeroTerminated(Uint8List data, int offset, int maxLength) {
  final view = data.sublist(offset, offset + maxLength);
  var contentLength = view.indexOf(0);
  if (contentLength.isNegative) contentLength = maxLength;

  return utf8.decode(view.sublist(0, contentLength));
}

/// Extended PAX headers in the POSIX tar format.
class PaxHeaders extends UnmodifiableMapBase<String, String> {
  final Map<String, String> _globalHeaders = {};
  Map<String, String> _localHeaders = {};

  /// The size of the next tar entry as stored in these headers.
  int? get size {
    final sizeStr = this[paxHeaderSize];
    return sizeStr != null ? int.parse(sizeStr) : null;
  }

  /// The file name of the next tar entry.
  String? get fileName => this[paxHeaderPath];
  set fileName(String? name) => _setOrRemove(paxHeaderPath, name);

  /// The link name of the next tar entry
  String? get linkName => this[paxHeaderLinkName];
  set linkName(String? name) => _setOrRemove(paxHeaderLinkName, name);

  void _setOrRemove(String key, String? value) {
    if (value == null) {
      _localHeaders.remove(key);
    } else {
      _localHeaders[key] = value;
    }
  }

  /// Applies new global PAX-headers from the map.
  ///
  /// The [headers] will replace global headers with the same key, but leave
  /// others intact.
  void newGlobals(Map<String, String> headers) {
    _globalHeaders.addAll(headers);
  }

  /// Applies new local PAX-headers from the map.
  ///
  /// This replaces all currently active local headers.
  void newLocals(Map<String, String> headers) {
    _localHeaders = headers;
  }

  /// Clears local headers.
  ///
  /// This is used by the reader after a file has ended, as local headers only
  /// apply to the next entry.
  void clearLocals() {
    _localHeaders = {};
  }

  @override
  String? operator [](Object? key) {
    return _globalHeaders[key] ?? _localHeaders[key];
  }

  @override
  Iterable<String> get keys => {..._globalHeaders.keys, ..._localHeaders.keys};
}
