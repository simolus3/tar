import 'dart:io';

Future<void> main() async {
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(
      'https://storage.googleapis.com/simon-public-euw3/assets/7za.exe'));
  final response = await request.close();

  await response.pipe(File('7za.exe').openWrite());
  client.close();
}
