/// Streaming tar implementation for Dart.
///
/// This library is meant to be imported with a prefix:
///
/// ```
/// import 'package:tar/tar.dart' as tar;
/// ```
///
/// To read tar files, see [reader]. To write tar files, use [WritingSink] or
/// [writer].
library tar;

export 'src/constants.dart' show TypeFlag;
export 'src/entry.dart';
export 'src/exception.dart';
export 'src/format.dart';
export 'src/header.dart' show Header;
export 'src/reader.dart' show createReader, reader;
export 'src/writer.dart' show createWritingSink, writer;

// For dartdoc.
import 'src/reader.dart';
import 'src/writer.dart';
