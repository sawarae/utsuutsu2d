/// IO-specific model loading (not available on web)
import 'dart:io';
import 'dart:typed_data';
import '../core/model.dart';
import 'formats.dart';

/// Load model from file path (IO platforms only)
Future<Model> loadFromFile(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  return ModelLoader.loadFromBytes(bytes, path);
}
