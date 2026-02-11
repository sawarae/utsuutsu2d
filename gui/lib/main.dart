import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:utsutsu2d/utsutsu2d.dart';

// dart-define configuration
const String? _envModelPath = String.fromEnvironment('MODEL_PATH') != ''
    ? String.fromEnvironment('MODEL_PATH')
    : null;
const bool _autoScreenshot = bool.fromEnvironment('AUTO_SCREENSHOT');
const String? _screenshotPath = String.fromEnvironment('SCREENSHOT_PATH') != ''
    ? String.fromEnvironment('SCREENSHOT_PATH')
    : null;
const String? _screenshotMode =
    String.fromEnvironment('SCREENSHOT_MODE') != ''
        ? String.fromEnvironment('SCREENSHOT_MODE')
        : null;
const String _zoomLevelStr = String.fromEnvironment('ZOOM_LEVEL');
const String _cameraXStr = String.fromEnvironment('CAMERA_X');
const String _cameraYStr = String.fromEnvironment('CAMERA_Y');
const String? _paramName = String.fromEnvironment('PARAM_NAME') != ''
    ? String.fromEnvironment('PARAM_NAME')
    : null;
const String _paramXStr = String.fromEnvironment('PARAM_X');
const String _paramYStr = String.fromEnvironment('PARAM_Y');
const bool _dumpMesh = bool.fromEnvironment('DUMP_MESH');
const String? _dumpMeshPath = String.fromEnvironment('DUMP_MESH_PATH') != ''
    ? String.fromEnvironment('DUMP_MESH_PATH')
    : null;

/// Top-level function for compute() - decodes TGA to PNG bytes
Uint8List _decodeTgaToPng(Uint8List data) {
  img.Image? decodedImage = img.decodeTga(data);
  decodedImage ??= img.decodeImage(data);
  if (decodedImage == null) return Uint8List(0);
  return Uint8List.fromList(img.encodePng(decodedImage));
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  String? modelPath = _envModelPath;
  for (final arg in args) {
    if (arg.startsWith('--model=')) {
      modelPath = arg.substring('--model='.length);
    }
  }

  runApp(Utsutsu2DApp(initialModelPath: modelPath));
}

class Utsutsu2DApp extends StatelessWidget {
  final String? initialModelPath;

  const Utsutsu2DApp({super.key, this.initialModelPath});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'utsutsu2d',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
      home: ViewerPage(initialModelPath: initialModelPath),
    );
  }
}

class ViewerPage extends StatefulWidget {
  final String? initialModelPath;

  @visibleForTesting
  static PuppetController? activeController;

  const ViewerPage({super.key, this.initialModelPath});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage>
    with TickerProviderStateMixin {
  PuppetController? _controller;
  String? _errorMessage;
  bool _isLoading = false;
  final GlobalKey _puppetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.initialModelPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadModelFromPath(widget.initialModelPath!);
      });
    }
  }

  @override
  void dispose() {
    ViewerPage.activeController = null;
    _controller?.dispose();
    super.dispose();
  }

  Future<ui.Image?> _decodeTexture(ModelTexture texture, int index) async {
    try {
      Uint8List imageBytes = texture.data;
      if (texture.format == ImageFormat.tga ||
          texture.format == ImageFormat.unknown) {
        imageBytes = await compute(_decodeTgaToPng, texture.data);
        if (imageBytes.isEmpty) return null;
      }
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('Error loading texture $index: $e');
      return null;
    }
  }

  Future<void> _loadModelFromPath(String path) async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final file = File(path);
      if (!file.existsSync()) {
        throw Exception('File not found: $path');
      }

      final bytes = await file.readAsBytes();
      final model = ModelLoader.loadFromBytes(bytes);

      // Load textures in parallel
      final futures = <Future<ui.Image?>>[];
      for (int i = 0; i < model.textures.length; i++) {
        futures.add(_decodeTexture(model.textures[i], i));
      }
      final images = await Future.wait(futures);
      final textures = images.whereType<ui.Image>().toList();

      final controller = PuppetController();
      await controller.loadModel(model, textures);

      setState(() {
        _controller = controller;
        _isLoading = false;
      });
      ViewerPage.activeController = controller;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyDartDefineSettings(controller);
      });
    } catch (e) {
      debugPrint('Error loading model: $e');
      setState(() {
        _errorMessage = 'Failed to load: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _applyDartDefineSettings(PuppetController controller) async {
    // Set parameter if specified
    if (_paramName != null && _paramName!.isNotEmpty) {
      final px =
          _paramXStr.isNotEmpty ? (double.tryParse(_paramXStr) ?? 0.0) : 0.0;
      final py =
          _paramYStr.isNotEmpty ? (double.tryParse(_paramYStr) ?? 0.0) : 0.0;
      controller.setParameter(_paramName!, px, py);
      WidgetsBinding.instance.scheduleFrame();
      await Future.delayed(const Duration(milliseconds: 100));
    } else if (_screenshotMode == 'diagonal') {
      controller.setParameter('Head:: Yaw-Pitch', 0.5, 0.5);
      WidgetsBinding.instance.scheduleFrame();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Set camera
    final camera = controller.camera;
    if (camera != null) {
      if (_screenshotMode == 'face') {
        camera.zoom = 0.32;
        camera.position = Vec2(0, -1850);
      } else if (_screenshotMode == 'whole') {
        camera.zoom = 0.12;
        camera.position = Vec2(0, -850);
      } else if (_screenshotMode == 'diagonal') {
        camera.zoom = 0.32;
        camera.position = Vec2(0, -1850);
      } else {
        camera.zoom = _zoomLevelStr.isNotEmpty
            ? (double.tryParse(_zoomLevelStr) ?? 0.32)
            : 0.32;
        final x = _cameraXStr.isNotEmpty
            ? (double.tryParse(_cameraXStr) ?? 0)
            : 0.0;
        final y = _cameraYStr.isNotEmpty
            ? (double.tryParse(_cameraYStr) ?? -1850)
            : -1850.0;
        camera.position = Vec2(x, y);
      }
      controller.updateManual();
    }

    // Dump mesh or auto screenshot
    if (_dumpMesh && _dumpMeshPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Future.delayed(const Duration(milliseconds: 500));
          await _dumpMeshData(controller, _dumpMeshPath!);
          exit(0);
        });
      });
    } else if (_autoScreenshot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Future.delayed(const Duration(milliseconds: 500));
          await _saveScreenshot(path: _screenshotPath);
          exit(0);
        });
      });
    }
  }

  Future<void> _saveScreenshot({String? path}) async {
    try {
      final boundary = _puppetKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final outputPath =
          path ?? 'screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(outputPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());
      debugPrint('Screenshot saved: $outputPath');
    } catch (e) {
      debugPrint('Error saving screenshot: $e');
    }
  }

  Future<void> _dumpMeshData(
      PuppetController controller, String outputPath) async {
    try {
      final puppet = controller.puppet;
      final renderCtx = puppet?.renderCtx;
      if (puppet == null || renderCtx == null) return;

      final meshes = <Map<String, dynamic>>[];
      for (final renderData in renderCtx.drawables) {
        final mesh = renderData.mesh;
        if (mesh == null) continue;

        final node = puppet.nodes.getNode(renderData.nodeId);
        final nodeName = node?.data.name ?? 'unknown';
        final deformedVertices = renderData.deformedVertices;

        final deforms = <List<double>>[];
        final deformed = <List<double>>[];
        final vertices = <List<double>>[];

        for (int i = 0; i < mesh.vertices.length; i++) {
          final base = mesh.vertices[i];
          vertices.add([base.x, base.y]);

          if (deformedVertices != null && i < deformedVertices.length) {
            final def = deformedVertices[i];
            deforms.add([def.x - base.x, def.y - base.y]);
            deformed.add([def.x, def.y]);
          } else {
            deforms.add([0, 0]);
            deformed.add([base.x, base.y]);
          }
        }

        meshes.add({
          'node_name': nodeName,
          'node_uuid': renderData.nodeId,
          'vert_count': mesh.vertices.length,
          'vertices': vertices,
          'deforms': deforms,
          'deformed': deformed,
        });
      }

      // Build parameter info
      final params = <String, List<double>>{};
      for (final param in puppet.params) {
        final value = puppet.getParamValue(param.name);
        if (value != null) {
          params[param.name] = [value.x, value.y];
        }
      }
      if (_paramName != null && _paramName!.isNotEmpty) {
        final px =
            _paramXStr.isNotEmpty ? (double.tryParse(_paramXStr) ?? 0.0) : 0.0;
        final py =
            _paramYStr.isNotEmpty ? (double.tryParse(_paramYStr) ?? 0.0) : 0.0;
        params[_paramName!] = [px, py];
      }

      final output = {
        'parameters': params,
        'camera': {
          'scale': controller.camera?.zoom ?? 0.32,
          'position': [0, -(controller.camera?.position.y ?? -1850)],
          'viewport': [1280, 720],
        },
        'mesh_count': meshes.length,
        'meshes': meshes,
      };

      final file = File(outputPath);
      await file
          .writeAsString(const JsonEncoder.withIndent('  ').convert(output));
      debugPrint('Mesh data saved: $outputPath (${meshes.length} meshes)');
    } catch (e) {
      debugPrint('Error dumping mesh data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('utsutsu2d'),
        actions: [
          if (_controller != null) ...[
            IconButton(
              icon: Icon(
                  _controller!.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                _controller!.togglePlay(this);
                setState(() {});
              },
              tooltip: _controller!.isPlaying ? 'Pause' : 'Play',
            ),
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: () => _saveScreenshot(),
              tooltip: 'Screenshot',
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!, style: TextStyle(color: Colors.red[300])),
      );
    }

    if (_controller == null) {
      return const Center(
        child: Text('No model loaded. Use --dart-define=MODEL_PATH=...'),
      );
    }

    if (_autoScreenshot || _dumpMesh) {
      return RepaintBoundary(
        key: _puppetKey,
        child: PuppetWidget(
          controller: _controller!,
          backgroundColor: Colors.grey[300],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: RepaintBoundary(
            key: _puppetKey,
            child: PuppetWidget(
              controller: _controller!,
              backgroundColor: Colors.grey[300],
            ),
          ),
        ),
        SizedBox(
          width: 300,
          child: _buildParameterPanel(),
        ),
      ],
    );
  }

  String? _activeExpression;

  void _applyExpression(String name, Map<String, double> values) {
    final puppet = _controller!.puppet;
    if (puppet == null) return;
    // Batch: reset all parameters to defaults, then apply expression values
    for (final param in puppet.params) {
      puppet.setParam(param.name, param.defaultValue.x, param.defaultValue.y);
    }
    for (final entry in values.entries) {
      puppet.setParam(entry.key, entry.value);
    }
    _controller!.updateManual();
    setState(() {
      _activeExpression = name;
    });
  }

  Widget _buildParameterPanel() {
    final puppet = _controller!.puppet;
    if (puppet == null) return const SizedBox.shrink();
    final params = puppet.params;
    final expressions = puppet.expressions;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expressions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Expressions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: expressions.entries.map((entry) {
                  final isActive = _activeExpression == entry.key;
                  return ChoiceChip(
                    label: Text(entry.key),
                    selected: isActive,
                    onSelected: (_) =>
                        _applyExpression(entry.key, entry.value),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 24),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              'Parameters (${params.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: params.length,
              itemBuilder: (context, index) {
                final param = params[index];
                if (param.is2D) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Parameter2DPad(
                      controller: _controller!,
                      param: param,
                      label: param.name,
                      size: 150,
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ParameterSlider(
                    controller: _controller!,
                    param: param,
                    label: param.name,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
