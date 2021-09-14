import 'dart:io';
import 'dart:typed_data';

import 'package:tar/tar.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    print('Usage: dart run benchmark/list.dart <tar file>');
    exit(1);
  }

  final file = File(args.single);

  await _mark('Streaming', () => file.openRead());

  final content = await file.readAsBytes();
  await _mark('Single chunk', () => Stream.value(content));
}

Future<void> _mark(String desc, Stream<List<int>> Function() stream) async {
  final timings = Int64List(50);
  final stopwatch = Stopwatch();

  for (var i = 0; i < timings.length; i++) {
    stopwatch
      ..reset()
      ..start();

    final reader = TarReader(stream());

    while (await reader.moveNext()) {
      final entry = reader.current;
      // Make sure that we listen to the content stream
      await entry.contents
          .fold<int>(0, (previous, element) => previous + element.length);
    }

    timings[i] = stopwatch.elapsedMicroseconds;
  }

  timings.sort();

  print('$desc: Took ${Duration(microseconds: timings[24])}');
}
