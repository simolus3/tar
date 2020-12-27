// Wrapper around the `tar` command, for testing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tar/tar.dart' as tar;
import 'package:test/test.dart';

Future<Process> startTar(List<String> args) {
  return Process.start('tar', args).then((proc) {
    expect(proc.exitCode, completion(0));

    // Attach stderr listener, we don't expect any output on that
    late List<int> data;
    final sink = ByteConversionSink.withCallback((result) => data = result);
    proc.stderr.forEach(sink.add).then((_) {
      sink.close();
      const LineSplitter().convert(utf8.decode(data)).forEach(stderr.writeln);
    });

    return proc;
  });
}

Future<Process> writeToTar(List<String> args, Stream<tar.Entry> entries) async {
  final proc = await startTar(args);
  await entries.pipe(tar.WritingSink(proc.stdin));

  return proc;
}

extension ProcessUtils on Process {
  Stream<String> get lines {
    return this.stdout.transform(utf8.decoder).transform(const LineSplitter());
  }
}
