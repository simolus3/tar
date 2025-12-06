import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';

const outputName = 'self.tar.gz';

/// This example creates a `.tar.gz` file of the directory its running in.
Future<void> main() {
  final entries = findEntries();
  final output = File(outputName);

  return entries
      .transform(tarWriter)
      .transform(gzip.encoder)
      .pipe(output.openWrite());
}

Stream<TarEntry> findEntries() async* {
  // Build a stream of tar entries by going through each file system entity in
  // the current directory.
  final root = Directory.current;
  await for (final entry in root.list(recursive: true)) {
    // We could write directories too, but we only care about files for
    // simplicity.
    if (entry is! File) continue;

    final name = p.relative(entry.path, from: root.path);

    // Let's also ignore hidden directories and files.
    if (name.split(p.separator).any((part) => part.startsWith('.'))) continue;

    // Finally, we should ignore the output file since weird things may happen
    // otherwise.
    if (name == outputName) continue;

    final stat = entry.statSync();

    yield TarEntry(
      TarHeader(
        name: name,
        typeFlag: TypeFlag.reg, // It's a regular file
        // Apart from that, copy over meta information
        mode: stat.mode,
        modified: stat.modified,
        accessed: stat.accessed,
        changed: stat.changed,
        // This assumes that the file won't change until we're writing it into
        // the archive later, since then the size might be wrong. It's more
        // efficient though, since the tar writer would otherwise have to buffer
        // everything to find out the size.
        size: stat.size,
      ),
      // Use entry.openRead() to obtain an input stream for the file that the
      // writer will use later.
      entry.openRead(),
    );
  }
}
