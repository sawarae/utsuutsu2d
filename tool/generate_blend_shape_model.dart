import 'dart:io';
import 'dart:typed_data';
import 'lib/inp_builder.dart';
import 'lib/mesh_generator.dart';
import 'lib/toml_parser.dart';

// ============================================================================
// TOML-driven blend shape model generator
//
// Reads a TOML config that defines:
//   [meta]       — model name, artist, copyright, base_dir
//   [mesh]       — width/height for quad meshes
//   [background] — always-visible layers rendered behind everything (optional)
//   [base]       — mouth_closed / mouth_open layers (MouthOpen param)
//   [emotions]   — N emotion overlays, each with its own 0→1 param
//
// Generates an INP with:
//   Background layers (always opacity 1.0, no parameters)
//   MouthOpen (0→1): toggles base mouth closed/open
//   <EmotionName> (0→1): toggles each emotion overlay opacity
// ============================================================================

void main(List<String> args) {
  String? configPath;
  String? outputPath;

  for (int i = 0; i < args.length; i++) {
    if ((args[i] == '--config' || args[i] == '-c') && i + 1 < args.length) {
      configPath = args[i + 1];
      i++;
    } else if ((args[i] == '--output' || args[i] == '-o') &&
        i + 1 < args.length) {
      outputPath = args[i + 1];
      i++;
    } else if (args[i] == '--help' || args[i] == '-h') {
      print('''
Blend Shape Model Generator (TOML-driven)

Builds an INP model from a TOML configuration file that defines:
- Base layers (mouth closed/open) controlled by MouthOpen param
- Emotion overlay layers, each controlled by its own 0→1 param

Usage:
  dart run tool/generate_blend_shape_model.dart --config <toml> [options]

Options:
  --config, -c PATH   TOML config file (required)
  --output, -o PATH   Output .inp file (default: build/<config_name>.inp)
  --help, -h          Show this help
''');
      return;
    }
  }

  if (configPath == null) {
    print('Error: --config is required. Use --help for usage.');
    exit(1);
  }

  generateBlendShapeModel(
    configPath: configPath,
    outputPath: outputPath,
  );
}

/// Generate an INP model from a TOML blend shape config.
void generateBlendShapeModel({
  required String configPath,
  String? outputPath,
}) {
  // UUID counters, scoped per invocation
  int nextNodeUuid = 1;
  int nextParamUuid = 100;
  int allocNodeUuid() => nextNodeUuid++;
  int allocParamUuid() => nextParamUuid++;

  // ──────────────────────────────────────────────────────
  // Load and parse config
  // ──────────────────────────────────────────────────────
  final configFile = File(configPath);
  if (!configFile.existsSync()) {
    print('Error: Config file not found: $configPath');
    exit(1);
  }

  final config = TomlParser.parse(configFile.readAsStringSync());
  final meta = (config['meta'] ?? {}) as Map<String, dynamic>;
  final meshConfig = (config['mesh'] ?? {}) as Map<String, dynamic>;
  final backgroundConfig =
      (config['background'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final baseConfig = (config['base'] ?? {}) as Map<String, dynamic>;
  final emotionsConfig = (config['emotions'] ?? {}) as Map<String, dynamic>;
  final expressionsConfig =
      (config['expressions'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  final modelName = meta['name'] as String? ?? 'Blend Shape Model';
  final baseDir = meta['base_dir'] as String? ?? '';
  final output = outputPath ?? 'build/${_slugify(modelName)}.inp';

  final meshWidth = _toDouble(meshConfig['width']) ?? 2000.0;
  final meshHeight = _toDouble(meshConfig['height']) ?? 4000.0;

  // ──────────────────────────────────────────────────────
  // Validate base directory
  // ──────────────────────────────────────────────────────
  final dir = Directory(baseDir);
  if (!dir.existsSync()) {
    print('Error: Assets directory not found: $baseDir');
    print('Make sure the expression PNGs are available.');
    exit(1);
  }

  print('=== $modelName — Blend Shape Model Generator ===\n');

  // ──────────────────────────────────────────────────────
  // Parse base layers
  // ──────────────────────────────────────────────────────
  final mouthClosed = baseConfig['mouth_closed'] as Map<String, dynamic>?;
  final mouthOpen = baseConfig['mouth_open'] as Map<String, dynamic>?;

  if (mouthClosed == null || mouthOpen == null) {
    print('Error: [base] must define mouth_closed and mouth_open');
    exit(1);
  }

  // Collect all layers: background + base + emotions
  final layers = <Map<String, String>>[];

  // Background layers (always visible, no parameters)
  final backgroundCount = backgroundConfig.length;
  for (final entry in backgroundConfig.entries) {
    if (entry.value is! Map<String, dynamic>) {
      print('Error: [background.${entry.key}] must be a table with a "file" key');
      exit(1);
    }
    final bgDef = entry.value as Map<String, dynamic>;
    final bgFile = bgDef['file'];
    if (bgFile is! String) {
      print(
          'Error: [background.${entry.key}] must have a "file" key with a string value');
      exit(1);
    }
    layers.add({
      'name': bgDef['name'] as String? ?? entry.key,
      'file': bgFile,
    });
  }

  // Validate and add base layers
  final closedFile = mouthClosed['file'];
  if (closedFile is! String) {
    print('Error: [base.mouth_closed] must have a "file" key with a string value');
    exit(1);
  }
  final openFile = mouthOpen['file'];
  if (openFile is! String) {
    print('Error: [base.mouth_open] must have a "file" key with a string value');
    exit(1);
  }
  layers.add({
    'name': mouthClosed['name'] as String? ?? 'Base_MouthClosed',
    'file': closedFile,
  });
  layers.add({
    'name': mouthOpen['name'] as String? ?? 'Base_MouthOpen',
    'file': openFile,
  });

  // Emotion layers
  final emotionNames = <String>[];
  for (final entry in emotionsConfig.entries) {
    final emotionName = entry.key;
    if (entry.value is! Map<String, dynamic>) {
      print('Error: [emotions.$emotionName] must be a table with a "file" key');
      exit(1);
    }
    final emotionDef = entry.value as Map<String, dynamic>;
    final emotionFile = emotionDef['file'];
    if (emotionFile is! String) {
      print('Error: [emotions.$emotionName] must have a "file" key with a string value');
      exit(1);
    }
    emotionNames.add(emotionName);
    layers.add({
      'name': emotionName,
      'file': emotionFile,
    });
  }

  // ──────────────────────────────────────────────────────
  // Load textures
  // ──────────────────────────────────────────────────────
  print('Loading expression images...');
  final textures = <Uint8List>[];
  for (final layer in layers) {
    final path = '$baseDir/${layer['file']}';
    final file = File(path);
    if (!file.existsSync()) {
      print('Error: Expression image not found: $path');
      exit(1);
    }
    final bytes = file.readAsBytesSync();
    textures.add(bytes);
    print(
        '  [${textures.length - 1}] ${layer['name']}: ${layer['file']} (${bytes.length} bytes)');
  }

  // ──────────────────────────────────────────────────────
  // Build model
  // ──────────────────────────────────────────────────────
  print('\nBuilding INP model...');
  final builder = InpBuilder();

  builder.meta(
    name: modelName,
    version: '1.0',
    artist: meta['artist'] as String?,
    copyright: meta['copyright'] as String?,
  );

  builder.physics(pixelsPerMeter: 1000.0, gravity: 9.8);

  // Add textures
  for (final tex in textures) {
    builder.addTexture(tex);
  }

  // Build node tree: root + N layers
  final treeBuilder = NodeTreeBuilder(uuid: 0, name: 'Root');
  final nodeUuids = <int>[];

  for (int i = 0; i < layers.length; i++) {
    final uuid = allocNodeUuid();
    nodeUuids.add(uuid);
    // Background layers and first base layer (mouth closed) start visible
    final isBackground = i < backgroundCount;
    final isMouthClosed = i == backgroundCount;
    treeBuilder.addChild(createPartNode(
      uuid: uuid,
      name: layers[i]['name']!,
      mesh: MeshGenerator.quad(meshWidth, meshHeight),
      textureId: i,
      translation: [0.0, 0.0, 0.0],
      opacity: (isBackground || isMouthClosed) ? 1.0 : 0.0,
    ));
  }

  builder.nodes(treeBuilder.build());

  // ──────────────────────────────────────────────────────
  // Build parameters
  // ──────────────────────────────────────────────────────
  final params = <Map<String, dynamic>>[];

  // Parameter: MouthOpen — controls base layers (after background)
  final mouthClosedIdx = backgroundCount;
  final mouthOpenIdx = backgroundCount + 1;
  params.add(createParam(
    name: 'MouthOpen',
    uuid: allocParamUuid(),
    min: 0.0,
    max: 1.0,
    defaultValue: 0.0,
    bindings: [
      // Mouth closed: visible when closed, hidden when open
      createBinding(
          node: nodeUuids[mouthClosedIdx],
          paramName: 'opacity',
          values: [[1.0], [0.0]]),
      // Mouth open: hidden when closed, visible when open
      createBinding(
          node: nodeUuids[mouthOpenIdx],
          paramName: 'opacity',
          values: [[0.0], [1.0]]),
    ],
  ));

  // Parameters: one per emotion overlay (layers after background + base)
  for (int i = 0; i < emotionNames.length; i++) {
    final layerIdx = backgroundCount + 2 + i;
    params.add(createParam(
      name: emotionNames[i],
      uuid: allocParamUuid(),
      min: 0.0,
      max: 1.0,
      defaultValue: 0.0,
      bindings: [
        createBinding(
          node: nodeUuids[layerIdx],
          paramName: 'opacity',
          values: [[0.0], [1.0]], // 0=hidden, 1=visible
        ),
      ],
    ));
  }

  builder.params(params);

  // ──────────────────────────────────────────────────────
  // Build expression presets
  // ──────────────────────────────────────────────────────
  final expressionPresets = <String, Map<String, double>>{};
  for (final entry in expressionsConfig.entries) {
    if (entry.value is! Map<String, dynamic>) continue;
    final preset = entry.value as Map<String, dynamic>;
    final name = preset['name'] as String? ?? entry.key;
    final paramValues = <String, double>{};
    for (final p in preset.entries) {
      if (p.key == 'name') continue;
      final val = _toDouble(p.value);
      if (val != null) paramValues[p.key] = val;
    }
    expressionPresets[name] = paramValues;
  }

  if (expressionPresets.isNotEmpty) {
    builder.expressions(expressionPresets);
  }

  // ──────────────────────────────────────────────────────
  // Write output
  // ──────────────────────────────────────────────────────
  final inpBytes = builder.build();

  final outputFile = File(output);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsBytesSync(inpBytes);

  print('\n=== Generated $output (${(inpBytes.length / 1024 / 1024).toStringAsFixed(1)} MB) ===');
  if (backgroundCount > 0) {
    print('\nBackground layers ($backgroundCount): always visible');
    for (int i = 0; i < backgroundCount; i++) {
      print('  ${layers[i]['name']}');
    }
  }
  print('\nParameters (${params.length}):');
  print('  MouthOpen: toggles base mouth (layers $mouthClosedIdx-$mouthOpenIdx)');
  for (final name in emotionNames) {
    print('  $name: overlay (0=off, 1=on)');
  }
  if (expressionPresets.isNotEmpty) {
    print('\nExpressions (${expressionPresets.length}):');
    for (final entry in expressionPresets.entries) {
      final active = entry.value.entries
          .where((e) => e.value > 0)
          .map((e) => '${e.key}=${e.value}')
          .join(', ');
      print('  ${entry.key}: $active');
    }
  }
}

// ============================================================================
// Helpers
// ============================================================================

/// Convert a dynamic value to double.
double? _toDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Convert a model name to a filename-safe slug.
/// Falls back to 'model' if the result would be empty (e.g. all-Japanese name).
String _slugify(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'model' : slug;
}
