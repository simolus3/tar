# tar

![Build status](https://github.com/simolus3/tar/workflows/build/badge.svg)

This package provides stream-based readers and writers for tar files.

When working with large tar files, this library consumes considerably less memory
than [package:archive](https://pub.dev/packages/archive), although it is slightly slower.

## Reading

To read entries from a tar file, use

```dart
import 'dart:io';
import 'package:tar/tar.dart' as tar;

Future<void> main() async {
  final tarFile = File('file.tar')
       .openRead()
       .transform(tar.reader);

  await for (final entry in tarFile) {
    print(entry.name);
    print(await entry.transform(utf8.decoder).first);
  }
}
```

To read `.tar.gz` files, transform the stream with `gzip.decoder` first.

## Writing

You can write tar files into a `StreamSink<List<int>>`, such as an `IOSink`:

```dart
import 'dart:io';
import 'package:tar/tar.dart' as tar;

Future<void> main() async {
  final output = File('test.tar').openWrite();

  await Stream<tar.Entry>.value(
    tar.MemoryEntry(
      tar.Header(
        name: 'hello.txt',
        mode: int.parse('644', radix: 8),
      ),
      utf8.encode('Hello world'),
    ),
  ).pipe(tar.WritingSink(output));
}
```

Note that tar files are always written in the format defined by the POSIX.1-2001 specification
(`--format=posix` in GNU tar).

## Features

- Supports ustar archives
- Supports extended pax headers for long file or link names