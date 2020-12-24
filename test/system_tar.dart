// Wrapper around the `tar` command, for testing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tar/tar.dart' as tar;

Future<Process> startTar(List<String> args) {
  return Process.start('tar', args);
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
