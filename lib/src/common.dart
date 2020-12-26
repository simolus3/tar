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
