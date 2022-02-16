import 'package:file/file.dart';
import 'package:file/local.dart';

FileSystem get fs {
  return const LocalFileSystem();
}
