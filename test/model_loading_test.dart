@Tags(['integration'])
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:utsutsu2d/utsutsu2d.dart';
import 'test_helper.dart';

void main() {
  group('Model loading (network)', () {
    late String modelPath;

    setUpAll(() async {
      modelPath = await downloadTestModel();
    });

    test('loads INP file successfully', () {
      final bytes = File(modelPath).readAsBytesSync();
      final model = ModelLoader.loadFromBytes(bytes);

      expect(model.puppet, isNotNull);
      expect(model.textures, isNotEmpty);
    });

    test('has nodes', () {
      final bytes = File(modelPath).readAsBytesSync();
      final model = ModelLoader.loadFromBytes(bytes);

      expect(model.puppet.nodes.nodeCount, greaterThan(0));
    });

    test('has parameters', () {
      final bytes = File(modelPath).readAsBytesSync();
      final model = ModelLoader.loadFromBytes(bytes);

      expect(model.puppet.params, isNotEmpty);
    });

    test('has textures', () {
      final bytes = File(modelPath).readAsBytesSync();
      final model = ModelLoader.loadFromBytes(bytes);

      expect(model.textures.length, greaterThan(0));
      for (final tex in model.textures) {
        expect(tex.data, isNotEmpty);
      }
    });

    test('initializes without error', () {
      final bytes = File(modelPath).readAsBytesSync();
      final model = ModelLoader.loadFromBytes(bytes);

      expect(() => model.puppet.initAll(), returnsNormally);
    });
  });
}
