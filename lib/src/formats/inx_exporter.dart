import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../core/core.dart';

/// File extension mapping for image formats.
String _imageFormatExtension(ImageFormat format) {
  switch (format) {
    case ImageFormat.png:
      return '.png';
    case ImageFormat.jpeg:
      return '.jpg';
    case ImageFormat.webp:
      return '.webp';
    case ImageFormat.tga:
      return '.tga';
    case ImageFormat.bc7:
      return '.bc7';
    case ImageFormat.unknown:
      return '.bin';
  }
}

/// Exports a model to INX format (ZIP containing puppet.json + textures).
///
/// The INX ZIP archive contains:
/// - `puppet.json` - Puppet metadata, nodes, and parameters as JSON
/// - `textures/0.png`, `textures/1.tga`, etc. - Texture image files
/// - `vendor/<name>.json` - Optional vendor-specific data
///
/// Example:
/// ```dart
/// final model = await loadFromFile('puppet.inp');
/// final bytes = await exportToInx(model);
/// await File('exported.inx').writeAsBytes(bytes);
/// ```
Future<Uint8List> exportToInx(Model model) async {
  final archive = Archive();

  // Add puppet.json
  final puppetJson = model.puppet.toJson();
  final puppetJsonStr = const JsonEncoder.withIndent('  ').convert(puppetJson);
  final puppetJsonBytes = utf8.encode(puppetJsonStr);
  archive.addFile(ArchiveFile(
    'puppet.json',
    puppetJsonBytes.length,
    puppetJsonBytes,
  ));

  // Add textures
  for (int i = 0; i < model.textures.length; i++) {
    final texture = model.textures[i];
    final ext = _imageFormatExtension(texture.format);
    archive.addFile(ArchiveFile(
      'textures/$i$ext',
      texture.data.length,
      texture.data,
    ));
  }

  // Add vendor data
  for (final vendor in model.vendorData) {
    final vendorJsonStr = jsonEncode(vendor.toJson());
    final vendorBytes = utf8.encode(vendorJsonStr);
    archive.addFile(ArchiveFile(
      'vendor/${vendor.name}.json',
      vendorBytes.length,
      vendorBytes,
    ));
  }

  // Encode as ZIP
  final zipBytes = ZipEncoder().encode(archive);
  if (zipBytes == null) {
    throw StateError('Failed to encode ZIP archive');
  }
  return Uint8List.fromList(zipBytes);
}
