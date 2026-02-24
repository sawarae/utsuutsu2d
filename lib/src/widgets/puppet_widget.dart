import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../core/core.dart';
import '../math/camera.dart';
import '../math/vec2.dart';
import '../render/render.dart';

/// Controller for managing puppet model loading, animation, and interaction.
///
/// [PuppetController] is the main interface for working with puppets
/// in Flutter applications. It handles model loading, animation playback, parameter
/// manipulation, and render state management.
///
/// ## Basic Usage
///
/// ```dart
/// // Create controller
/// final controller = PuppetController();
///
/// // Load model and textures
/// final model = await loadFromFile('puppet.inx');
/// final textures = <ui.Image>[];
/// for (final texture in model.textures) {
///   final codec = await ui.instantiateImageCodec(texture.data);
///   final frame = await codec.getNextFrame();
///   textures.add(frame.image);
/// }
/// await controller.loadModel(model, textures);
///
/// // Start animation
/// controller.play(vsync); // vsync from TickerProviderStateMixin
///
/// // Manipulate parameters
/// controller.setParameter('Head: Yaw-Pitch', 0.5, 0.5);
/// ```
///
/// ## Animation Control
///
/// The controller supports play/pause animation with configurable FPS:
/// - [play] - Start animation loop with physics simulation
/// - [pause] - Stop animation and physics
/// - [togglePlay] - Toggle between play and pause states
/// - [fps] - Set frame rate (1-120 fps, default: 60)
///
/// ## Manual Updates
///
/// For non-animated use cases, use [updateManual] to update the puppet state
/// without advancing time:
///
/// ```dart
/// controller.setParameter('Mouth: Open', 0.8);
/// controller.updateManual(); // Apply parameter change without physics
/// ```
///
/// See also:
/// - [PuppetWidget] for displaying the puppet
/// - [Model] for the underlying puppet data
/// - [CanvasRenderer] for rendering implementation
class PuppetController extends ChangeNotifier {
  Model? _model;
  CanvasRenderer? _renderer;

  bool _isPlaying = false;
  double _fps = 60.0;
  Ticker? _ticker;
  Duration _lastTime = Duration.zero;

  PuppetController();

  /// Loads a puppet model and its textures into the controller.
  ///
  /// This method initializes the puppet's transform hierarchy, physics system,
  /// and render context. It must be called before using the controller to
  /// display or animate the puppet.
  ///
  /// Parameters:
  /// - [model]: The loaded Model containing puppet data and metadata
  /// - [textures]: List of decoded Flutter Image objects for the puppet's textures.
  ///   The order must match the texture order in the model.
  ///
  /// Example:
  /// ```dart
  /// final model = await loadFromFile('puppet.inx');
  /// final textures = <ui.Image>[];
  /// for (final texture in model.textures) {
  ///   final codec = await ui.instantiateImageCodec(texture.data);
  ///   final frame = await codec.getNextFrame();
  ///   textures.add(frame.image);
  /// }
  /// await controller.loadModel(model, textures);
  /// ```
  ///
  /// Throws an exception if the model or textures are invalid.
  Future<void> loadModel(Model model, List<ui.Image> textures) async {
    _model = model;

    // Initialize puppet (sets up transforms, rendering, params, physics)
    model.puppet.initAll();

    // Set up renderer using puppet's render context
    final renderCtx = model.puppet.renderCtx!;
    _renderer = CanvasRenderer(renderCtx: renderCtx);
    await _renderer!.loadShaders();

    // Cache textures
    for (int i = 0; i < textures.length; i++) {
      renderCtx.setTexture(i, textures[i]);
    }

    // Perform initial frame update to ensure puppet is properly initialized
    // even when animation is paused (fixes rendering regression - issue 009)
    _model!.puppet.beginFrame();
    _model!.puppet.endFrame(0);

    notifyListeners();
  }

  /// Get the loaded model
  Model? get model => _model;

  /// Get the puppet
  Puppet? get puppet => _model?.puppet;

  /// Get the renderer
  CanvasRenderer? get renderer => _renderer;

  /// Get the camera
  Camera? get camera => _renderer?.camera;

  /// Check if playing
  bool get isPlaying => _isPlaying;

  /// Get FPS
  double get fps => _fps;

  /// Set FPS
  set fps(double value) {
    _fps = value.clamp(1, 120);
    notifyListeners();
  }

  /// Starts the animation loop with physics simulation.
  ///
  /// Begins animating the puppet at the configured [fps] rate, updating
  /// physics simulation and parameter bindings each frame.
  ///
  /// Parameters:
  /// - [vsync]: A TickerProvider (typically from TickerProviderStateMixin)
  ///   used to create the animation ticker synchronized with the display refresh.
  ///
  /// Does nothing if already playing or if no model is loaded.
  ///
  /// Example:
  /// ```dart
  /// class MyWidget extends StatefulWidget {
  ///   // ...
  /// }
  ///
  /// class _MyWidgetState extends State<MyWidget>
  ///     with SingleTickerProviderStateMixin {
  ///   void startAnimation() {
  ///     controller.play(this); // 'this' provides TickerProvider
  ///   }
  /// }
  /// ```
  ///
  /// See also:
  /// - [pause] to stop animation
  /// - [togglePlay] to toggle play/pause state
  /// - [fps] to configure frame rate
  void play(TickerProvider vsync) {
    if (_isPlaying || _model == null) return;

    _isPlaying = true;
    _ticker = vsync.createTicker(_onTick);
    _ticker!.start();
    notifyListeners();
  }

  /// Stops the animation loop and disposes the ticker.
  ///
  /// Halts physics simulation and parameter updates. The puppet remains
  /// in its current state and can be manipulated manually via [setParameter]
  /// and [updateManual].
  ///
  /// Safe to call even if not currently playing.
  ///
  /// See also:
  /// - [play] to resume animation
  /// - [togglePlay] to toggle play/pause state
  void pause() {
    _isPlaying = false;
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _lastTime = Duration.zero;
    notifyListeners();
  }

  /// Toggle play/pause
  void togglePlay(TickerProvider vsync) {
    if (_isPlaying) {
      pause();
    } else {
      play(vsync);
    }
  }

  void _onTick(Duration elapsed) {
    if (!_isPlaying || _model == null) return;

    // Calculate delta time
    final dt = _lastTime == Duration.zero
        ? 1.0 / _fps
        : (elapsed - _lastTime).inMicroseconds / 1000000.0;
    _lastTime = elapsed;

    // Update puppet (endFrame includes render context update)
    _model!.puppet.beginFrame();
    _model!.puppet.endFrame(dt);

    notifyListeners();
  }

  /// Sets a puppet parameter value and updates the render state.
  ///
  /// Parameters can be 1D (single X value) or 2D (X and Y values).
  /// Common examples include head rotation, eye position, mouth opening, etc.
  ///
  /// Parameters:
  /// - [name]: The parameter name (e.g., "Head: Yaw-Pitch", "Mouth: Open")
  /// - [x]: The X-axis value, typically in range [-1.0, 1.0]
  /// - [y]: The Y-axis value for 2D parameters, defaults to 0
  ///
  /// The parameter name must match exactly as defined in the model.
  /// Use [puppet.params] to enumerate available parameters.
  ///
  /// Example:
  /// ```dart
  /// // 1D parameter
  /// controller.setParameter('Mouth: Open', 0.8);
  ///
  /// // 2D parameter
  /// controller.setParameter('Head: Yaw-Pitch', -0.3, 0.2);
  /// ```
  ///
  /// Note: This method does not advance physics time. For animated puppets,
  /// use [play] to enable continuous updates. For static puppets, this method
  /// provides immediate visual feedback.
  void setParameter(String name, double x, [double y = 0]) {
    _model?.puppet.setParam(name, x, y);
    // Apply parameters by running frame update (endFrame includes render update)
    _model?.puppet.beginFrame();
    _model?.puppet.endFrame(0); // dt=0 means no physics simulation
    notifyListeners();
  }

  /// Set manual per-vertex offset override for a specific node.
  ///
  /// [offsets] must have the same length as the node's mesh vertex count.
  /// Pass null to clear the override for that node.
  /// The offsets are in local mesh space and are added on top of any
  /// parameter-driven deformation.
  void setManualVertexOverride(int nodeId, List<Vec2>? offsets) {
    _model?.puppet.renderCtx?.setVertexOverride(nodeId, offsets);
    notifyListeners();
  }

  /// Clear all manual vertex overrides.
  void clearManualVertexOverrides() {
    _model?.puppet.renderCtx?.clearVertexOverrides();
    notifyListeners();
  }

  /// Set the visibility of a specific part by node ID.
  ///
  /// When [visible] is false the part is skipped during rendering.
  /// When [visible] is true the part renders normally.
  void setPartVisibility(int nodeId, bool visible) {
    _model?.puppet.renderCtx?.setNodeHidden(nodeId, !visible);
    notifyListeners();
  }

  /// Returns true if the part with the given node ID is currently visible.
  bool isPartVisible(int nodeId) {
    return !(_model?.puppet.renderCtx?.isNodeHidden(nodeId) ?? false);
  }

  /// Make all parts visible by clearing all hidden-node overrides.
  void clearPartVisibilityOverrides() {
    _model?.puppet.renderCtx?.clearHiddenNodes();
    notifyListeners();
  }

  /// Updates the puppet state without advancing physics time.
  ///
  /// This method is useful for manual parameter control when animation
  /// is paused. It applies current parameter values and updates transforms
  /// without simulating physics or advancing time.
  ///
  /// Example use case:
  /// ```dart
  /// // Pause animation
  /// controller.pause();
  ///
  /// // Manually adjust parameters
  /// controller.setParameter('Head: Yaw-Pitch', 0.5, 0);
  /// controller.setParameter('Eye: Happy', 1.0);
  ///
  /// // Force update without physics
  /// controller.updateManual();
  /// ```
  ///
  /// Note: [setParameter] already calls this internally, so you typically
  /// don't need to call it explicitly. Use it when you need to force a
  /// refresh without parameter changes.
  void updateManual() {
    if (_model == null) return;
    _model!.puppet.beginFrame();
    _model!.puppet.endFrame(0);
    notifyListeners();
  }

  @override
  void dispose() {
    pause();
    _model?.puppet.renderCtx?.dispose();
    super.dispose();
  }
}

/// A Flutter widget for displaying and interacting with puppets.
///
/// [PuppetWidget] provides a canvas-based rendering surface for puppet models
/// with built-in support for camera controls, zooming, and panning.
///
/// ## Features
///
/// - **Canvas Rendering**: Hardware-accelerated rendering using Flutter's Canvas API
/// - **Interactive Controls**: Pan, zoom, and manipulate the puppet view
/// - **Keyboard Support**: Ctrl/Cmd + Scroll for zooming
/// - **Gesture Support**: Pinch-to-zoom and drag-to-pan
/// - **Customizable Background**: Optional background color
///
/// ## Basic Usage
///
/// ```dart
/// PuppetWidget(
///   controller: puppetController,
///   interactive: true,
///   backgroundColor: Color(0xFFBDBDBD),
/// )
/// ```
///
/// ## Interactive Controls
///
/// When [interactive] is true (default):
/// - **Drag**: Pan the camera
/// - **Pinch**: Zoom in/out
/// - **Ctrl/Cmd + Scroll**: Zoom in/out
///
/// ## Performance Considerations
///
/// - The widget automatically repaints when the controller notifies listeners
/// - For static puppets, consider setting [interactive] to false
/// - Background color defaults to transparent; opaque colors improve performance
///
/// See also:
/// - [PuppetController] for managing puppet state and animation
/// - [CanvasRenderer] for the underlying rendering implementation
class PuppetWidget extends StatefulWidget {
  /// The controller managing the puppet model and animation state.
  final PuppetController controller;

  /// Whether to enable interactive camera controls (pan, zoom).
  ///
  /// When true, the widget responds to gestures and keyboard input.
  /// When false, the widget displays the puppet without interaction.
  /// Defaults to true.
  final bool interactive;

  /// Background color for the puppet display.
  ///
  /// Defaults to transparent. Using an opaque color can improve
  /// rendering performance by eliminating alpha blending with
  /// underlying widgets.
  final Color? backgroundColor;

  const PuppetWidget({
    super.key,
    required this.controller,
    this.interactive = true,
    this.backgroundColor,
  });

  @override
  State<PuppetWidget> createState() => _PuppetWidgetState();
}

class _PuppetWidgetState extends State<PuppetWidget>
    with SingleTickerProviderStateMixin {
  bool _ctrlPressed = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    // CustomPainterがrepaint Listenableを使用しているため、
    // ここでsetState()を呼ぶ必要はない
    // (CustomPaintが自動的にrepaintされる)
  }

  void _onKey(KeyEvent event) {
    final isCtrl = event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight ||
        event.logicalKey == LogicalKeyboardKey.metaLeft ||
        event.logicalKey == LogicalKeyboardKey.metaRight;
    if (isCtrl) {
      setState(() {
        _ctrlPressed = event is KeyDownEvent;
      });
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final camera = widget.controller.camera;
      if (camera == null) return;

      if (_ctrlPressed) {
        // Ctrl + scroll = zoom
        final zoomDelta = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
        camera.zoom *= zoomDelta;
        camera.zoom = camera.zoom.clamp(0.1, 10.0);
        widget.controller.notifyListeners();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: Container(
          color: widget.backgroundColor ?? Colors.transparent,
          child: widget.interactive
              ? GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: _buildCanvas(),
                )
              : _buildCanvas(),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    final renderer = widget.controller.renderer;
    final puppet = widget.controller.puppet;

    if (renderer == null || puppet == null) {
      return const Center(
        child: Text('No puppet loaded'),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    return CustomPaint(
      painter: _PuppetPainter(
        renderer: renderer,
        puppet: puppet,
        repaint: widget.controller,
        devicePixelRatio: dpr,
      ),
      size: Size.infinite,
    );
  }

  Offset? _lastFocalPoint;

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final camera = widget.controller.camera;
    if (camera == null || _lastFocalPoint == null) return;

    // Pan
    final delta = details.focalPoint - _lastFocalPoint!;
    camera.position = camera.position -
        Vec2(
          delta.dx / camera.zoom,
          delta.dy / camera.zoom,
        );

    // Zoom
    if (details.scale != 1.0) {
      camera.zoom *= details.scale;
      camera.zoom = camera.zoom.clamp(0.1, 10.0);
    }

    _lastFocalPoint = details.focalPoint;
    widget.controller.notifyListeners();
  }
}

class _PuppetPainter extends CustomPainter {
  final CanvasRenderer renderer;
  final Puppet puppet;
  final double devicePixelRatio;

  _PuppetPainter({
    required this.renderer,
    required this.puppet,
    Listenable? repaint,
    this.devicePixelRatio = 1.0,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    renderer.devicePixelRatio = devicePixelRatio;
    renderer.render(canvas, size, puppet);
  }

  @override
  bool shouldRepaint(_PuppetPainter oldDelegate) {
    return renderer != oldDelegate.renderer ||
        puppet != oldDelegate.puppet ||
        devicePixelRatio != oldDelegate.devicePixelRatio;
  }
}
