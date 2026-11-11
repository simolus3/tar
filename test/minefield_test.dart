/// Runs the test cases from https://github.com/haampie/tar-minefield.
///
/// The archives are downloaded into `reference/minefield`, run
/// `tool/minefield.sh` to update them.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';
import 'package:test/test.dart';

void main() {
  final jsonFiles = Directory('reference/minefield')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final jsonFile in jsonFiles) {
    final testCase = MinefieldCase.fromJson(
        json.decode(jsonFile.readAsStringSync()) as Map<String, Object?>);
    final tarFile = File(p.setExtension(jsonFile.path, '.tar'));

    test(
      '${testCase.id}: ${testCase.description}',
      () async {
        List<TreeEntry>? tree;
        Exception? rejection;
        try {
          tree = await extractInMemory(tarFile.openRead());
        } on TarException catch (e) {
          rejection = e;
        } on ExtractionRejected catch (e) {
          rejection = e;
        }

        switch (testCase.verdict) {
          case Verdict.reject:
            expect(tree, isNull,
                reason: 'Should reject, but extracted ${_describe(tree)}');
          case Verdict.accept:
            expect(rejection, isNull, reason: 'Should accept');
            expect(_describe(tree), _describe(testCase.tree));
          case Verdict.tolerate:
            if (tree != null) {
              expect(_describe(tree), _describe(testCase.tree));
            }
        }
      },
      tags: _knownFailures.contains(testCase.id)
          ? 'known_minefield_failure'
          : null,
    );
  }
}

const _knownFailures = {
  // Numeric fields
  'F06', 'F11', 'F12', 'F37', 'F40', 'F41',
  // End of archive and framing
  'F03', 'F39', 'F54',
  // Pax size
  'F10', 'F13', 'F19', 'F20', 'F21', 'F23', 'F24', 'F26', 'F44',
  // Conflicting names
  'N08', 'N09', 'N23', 'N29', 'N37', 'N38',
  // Duplicate or empty pax keys
  'N20', 'N22', 'N26', 'N34', 'N40', 'N41',
  // Non-UTF-8 names and link targets
  'N18', 'N24', 'N31', 'N32',
  // Header fields
  'N10', 'N11', 'N14', 'N39', 'N48',
  // Sparse files (reader throws a StateError after the sparse entry)
  'N36',
};

Map<String, Object?> _describe(List<TreeEntry>? tree) {
  return {
    for (final entry in tree ?? const <TreeEntry>[]) entry.path: entry.toJson()
  };
}

/// Thrown by [extractInMemory] for archives that are well-formed, but can't be
/// extracted unambiguously.
final class ExtractionRejected implements Exception {
  final String message;

  ExtractionRejected(this.message);

  @override
  String toString() => 'ExtractionRejected: $message';
}

/// Extracts a tar archive into memory, returning every path it would create.
///
/// This mirrors what a strict extractor would do, so that the expectations of
/// the minefield suite (which are phrased in terms of extracted trees) can be
/// checked against the parser.
Future<List<TreeEntry>> extractInMemory(Stream<List<int>> tar) async {
  final nodes = <String, TreeEntry>{};

  void createParents(String path) {
    final segments = p.posix.split(path);
    for (var i = 1; i < segments.length; i++) {
      final parent = p.posix.joinAll(segments.take(i));
      switch (nodes[parent]) {
        case null:
          nodes[parent] = DirectoryEntry(parent);
        case DirectoryEntry():
          break;
        case _:
          throw ExtractionRejected('$path is below non-directory $parent');
      }
    }
  }

  void create(TreeEntry entry) {
    createParents(entry.path);
    final existing = nodes[entry.path];
    if (existing == null) {
      nodes[entry.path] = entry;
    } else if (existing is! DirectoryEntry || entry is! DirectoryEntry) {
      throw ExtractionRejected('Duplicate entry for ${entry.path}');
    }
  }

  final reader = TarReader(tar, disallowTrailingData: true);
  while (await reader.moveNext()) {
    final entry = reader.current;
    final header = entry.header;
    final linkName = header.linkName ?? '';

    switch (entry.type) {
      case TypeFlag.reg || TypeFlag.reserved:
        if (linkName.isNotEmpty) {
          throw ExtractionRejected('Regular file ${entry.name} has a link');
        }

        final contents = await entry.contents
            .fold(BytesBuilder(copy: false), (b, chunk) => b..add(chunk))
            .then((b) => b.takeBytes());
        create(FileEntry(
          _normalize(entry.name),
          executable: header.mode & 0x40 != 0, // 0o100, owner execute
          size: contents.length,
          sha256: sha256.convert(contents).toString(),
        ));
      case TypeFlag.dir:
        _checkNoData(entry);
        final path = _normalize(entry.name, isDirectory: true);
        // Ignore the root of the archive, as written by `tar cf x.tar .`.
        if (path.isNotEmpty) create(DirectoryEntry(path));
      case TypeFlag.symlink:
        _checkNoData(entry);
        if (linkName.isEmpty) {
          throw ExtractionRejected('Symlink ${entry.name} has no target');
        }
        create(SymlinkEntry(_normalize(entry.name), target: linkName));
      case TypeFlag.link:
        _checkNoData(entry);
        final target = nodes[_normalize(linkName)];
        if (target is! FileEntry) {
          throw ExtractionRejected(
              'Hardlink ${entry.name} to $linkName, which is not a file');
        }
        create(FileEntry(
          _normalize(entry.name),
          executable: target.executable,
          size: target.size,
          sha256: target.sha256,
        ));
      case final type:
        throw ExtractionRejected('Unsupported type $type for ${entry.name}');
    }
  }

  return nodes.values.toList();
}

void _checkNoData(TarEntry entry) {
  if (entry.size != 0) {
    throw ExtractionRejected('${entry.type} ${entry.name} has a size');
  }
}

/// Normalizes the [name] of an archive member into a relative path, rejecting
/// names that are empty, ambiguous or escape the destination.
///
/// Returns the empty string for the root directory.
String _normalize(String name, {bool isDirectory = false}) {
  if (name.isEmpty) {
    throw ExtractionRejected('Empty name');
  }
  if (name.startsWith('/') ||
      name.contains(r'\') ||
      name.startsWith(RegExp('[a-zA-Z]:'))) {
    throw ExtractionRejected('Unsafe or platform-dependent name $name');
  }
  if (name.endsWith('/') && !isDirectory) {
    throw ExtractionRejected('Non-directory $name ends in a slash');
  }

  final segments = [
    for (final segment in name.split('/'))
      if (segment.isNotEmpty && segment != '.') segment,
  ];
  if (segments.contains('..')) {
    throw ExtractionRejected('$name escapes the destination');
  }
  if (segments.isEmpty && !isDirectory) {
    throw ExtractionRejected('Non-directory $name is the root');
  }

  return segments.join('/');
}

enum Verdict {
  /// The archive is well-formed and must be read.
  accept,

  /// The archive is malformed in a way that readers may tolerate.
  tolerate,

  /// The archive is malformed and must be rejected.
  reject,
}

final class MinefieldCase {
  final String id;
  final Verdict verdict;
  final String description;

  /// The entries expected when reading the archive, or `null` if the archive
  /// should be rejected.
  final List<TreeEntry>? tree;

  MinefieldCase({
    required this.id,
    required this.verdict,
    required this.description,
    required this.tree,
  });

  factory MinefieldCase.fromJson(Map<String, Object?> json) {
    final tree = json['tree'] as List<Object?>?;

    return MinefieldCase(
      id: json['id'] as String,
      verdict: Verdict.values.byName(json['verdict'] as String),
      description: json['description'] as String,
      tree: tree
          ?.map((entry) => TreeEntry.fromJson(entry as Map<String, Object?>))
          .toList(),
    );
  }
}

sealed class TreeEntry {
  final String path;

  TreeEntry(this.path);

  factory TreeEntry.fromJson(Map<String, Object?> json) {
    final path = json['path'] as String;

    return switch (json['kind']) {
      'file' => FileEntry(
          path,
          executable: json['executable'] as bool,
          size: json['size'] as int,
          sha256: json['sha256'] as String,
        ),
      'directory' => DirectoryEntry(path),
      'symlink' => SymlinkEntry(path, target: json['target'] as String),
      final kind => throw ArgumentError.value(kind, 'kind', 'Unknown kind'),
    };
  }

  /// The attributes of this entry, in the format of the minefield suite but
  /// without the [path].
  Map<String, Object?> toJson();
}

final class FileEntry extends TreeEntry {
  final bool executable;
  final int size;

  /// The hex-encoded SHA-256 hash of the file's contents.
  final String sha256;

  FileEntry(
    super.path, {
    required this.executable,
    required this.size,
    required this.sha256,
  });

  @override
  Map<String, Object?> toJson() => {
        'kind': 'file',
        'executable': executable,
        'size': size,
        'sha256': sha256,
      };
}

final class DirectoryEntry extends TreeEntry {
  DirectoryEntry(super.path);

  @override
  Map<String, Object?> toJson() => {'kind': 'directory'};
}

final class SymlinkEntry extends TreeEntry {
  final String target;

  SymlinkEntry(super.path, {required this.target});

  @override
  Map<String, Object?> toJson() => {'kind': 'symlink', 'target': target};
}
