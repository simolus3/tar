import 'package:file/local.dart';

Stream<List<int>> openRead(String path) {
  const fs = LocalFileSystem();
  return fs.file(path).openRead();
}
