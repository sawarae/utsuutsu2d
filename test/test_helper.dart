import 'dart:io';
import 'package:path/path.dart' as p;

const _releaseUrl =
    'https://github.com/sawarae/utsutsu2d/releases/download/v0.01/tsukuyomi_blend_shape.inp';

/// Download and cache the test INP file from GitHub releases.
///
/// Returns the path to the cached file, or throws if download fails.
Future<String> downloadTestModel() async {
  final cacheDir = Directory(p.join(Directory.systemTemp.path, 'utsutsu2d_test'));
  if (!cacheDir.existsSync()) {
    cacheDir.createSync(recursive: true);
  }

  final cachedFile = File(p.join(cacheDir.path, 'tsukuyomi_blend_shape.inp'));
  if (cachedFile.existsSync() && cachedFile.lengthSync() > 0) {
    return cachedFile.path;
  }

  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(_releaseUrl));
    final response = await request.close();

    if (response.statusCode == 200) {
      await response.pipe(cachedFile.openWrite());
      return cachedFile.path;
    } else if (response.statusCode == 302 || response.statusCode == 301) {
      // Follow redirect
      final redirectUrl = response.headers.value('location');
      if (redirectUrl != null) {
        final redirectRequest = await client.getUrl(Uri.parse(redirectUrl));
        final redirectResponse = await redirectRequest.close();
        await redirectResponse.pipe(cachedFile.openWrite());
        return cachedFile.path;
      }
    }
    throw Exception('Failed to download test model: HTTP ${response.statusCode}');
  } finally {
    client.close();
  }
}
