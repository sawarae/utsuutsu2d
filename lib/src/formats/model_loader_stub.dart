/// Stub for web platform (file loading not supported)
import '../core/model.dart';

/// Load model from file path - not available on web
Future<Model> loadFromFile(String path) {
  throw UnsupportedError('loadFromFile is not supported on web. Use ModelLoader.loadFromBytes instead.');
}
