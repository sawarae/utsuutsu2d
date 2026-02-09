import 'node.dart';
import 'meta.dart';
import '../params/param.dart';
import '../params/param_ctx.dart';
import '../physics/physics_ctx.dart';
import '../math/math.dart';
import '../components/components.dart';
import '../animation/animation.dart';
import '../render/render_ctx.dart';

/// Physics simulation settings for a puppet.
///
/// Controls global physics parameters like gravity and pixel-to-meter
/// conversion for realistic motion simulation.
class PuppetPhysics {
  /// Scaling factor from screen pixels to physics meters.
  ///
  /// Higher values make physics objects appear lighter/smaller.
  /// Default: 100 pixels = 1 meter.
  double pixelsPerMeter;

  /// Horizontal gravity component in m/s².
  ///
  /// Positive values pull right, negative pull left.
  /// Default: 0.0 (no horizontal gravity).
  double gravityX;

  /// Vertical gravity component in m/s².
  ///
  /// Positive values pull down (Earth-like), negative pull up.
  /// Default: 9.8 m/s² (Earth gravity).
  double gravityY;

  PuppetPhysics({
    this.pixelsPerMeter = 100.0,
    this.gravityX = 0.0,
    this.gravityY = 9.8,
  });

  Vec2 get gravity => Vec2(gravityX, gravityY);

  factory PuppetPhysics.fromJson(Map<String, dynamic> json) {
    return PuppetPhysics(
      pixelsPerMeter: (json['pixels_per_meter'] ?? 100.0).toDouble(),
      gravityX: (json['gravity_x'] ?? 0.0).toDouble(),
      gravityY: (json['gravity_y'] ?? 9.8).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pixels_per_meter': pixelsPerMeter,
      'gravity_x': gravityX,
      'gravity_y': gravityY,
    };
  }
}

/// Internal context for managing node transform calculations.
///
/// Maintains relative and absolute transforms for each node in the puppet's
/// hierarchy. This is an internal implementation detail; users typically
/// interact with puppets through [Puppet] and [PuppetController].
class TransformCtx {
  final Map<PuppetNodeUuid, TransformStore> _stores = {};

  TransformCtx();

  /// Initialize transform stores for all nodes
  void initialize(PuppetNodeTree tree) {
    for (final treeNode in tree.preOrder()) {
      final node = treeNode.data;
      final store = TransformStore();
      store.reset(node.transOffset);
      _stores[node.uuid] = store;
    }
  }

  /// Reset all transforms
  void reset(PuppetNodeTree tree) {
    for (final treeNode in tree.preOrder()) {
      final node = treeNode.data;
      _stores[node.uuid]?.reset(node.transOffset);
    }
  }

  /// Update absolute transforms
  void update(PuppetNodeTree tree) {
    for (final treeNode in tree.preOrder()) {
      final node = treeNode.data;
      final store = _stores[node.uuid];
      if (store == null) continue;

      final relativeMatrix = store.relative.toMatrix();
      final parent = treeNode.parent;
      if (parent == null) {
        // Root node
        store.absolute = relativeMatrix;
      } else if (node.lockToRoot) {
        // Lock to root
        final rootStore = _stores[tree.root.data.uuid];
        if (rootStore != null) {
          store.absolute = rootStore.absolute * relativeMatrix;
        }
      } else {
        // Inherit from parent
        final parentStore = _stores[parent.data.uuid];
        if (parentStore != null) {
          store.absolute = parentStore.absolute * relativeMatrix;
        }
      }
    }
  }

  /// Get transform store for a node
  TransformStore? getStore(PuppetNodeUuid uuid) => _stores[uuid];
}

/// Internal context for managing node rendering order (Z-sorting).
///
/// Tracks Z-sort values for each node to determine draw order.
/// Nodes with higher Z-sort values are drawn on top.
///
/// This is an internal implementation detail.
class ZSortCtx {
  final Map<PuppetNodeUuid, double> _zsorts = {};

  ZSortCtx();

  void initialize(PuppetNodeTree tree) {
    for (final treeNode in tree.preOrder()) {
      final node = treeNode.data;
      _zsorts[node.uuid] = node.zsort;
    }
  }

  void reset(PuppetNodeTree tree) {
    for (final treeNode in tree.preOrder()) {
      final node = treeNode.data;
      _zsorts[node.uuid] = node.zsort;
    }
  }

  void update(PuppetNodeTree tree) {
    for (final treeNode in tree.preOrder()) {
      final node = treeNode.data;
      final parent = treeNode.parent;

      if (parent != null) {
        final parentZsort = _zsorts[parent.data.uuid] ?? 0.0;
        _zsorts[node.uuid] = parentZsort + node.zsort;
      }
    }
  }

  double? getZSort(PuppetNodeUuid uuid) => _zsorts[uuid];
  void setZSort(PuppetNodeUuid uuid, double value) => _zsorts[uuid] = value;
}

/// The core puppet rig containing nodes, parameters, and physics.
///
/// [Puppet] represents a complete rigged character with its node hierarchy,
/// deformation parameters, and physics simulation. It must be initialized
/// before use and updated each frame during animation.
///
/// ## Initialization
///
/// Before using a puppet, you must initialize its subsystems in order:
///
/// ```dart
/// puppet.initAll(); // Initialize all systems at once
/// ```
///
/// Or initialize subsystems individually:
/// ```dart
/// puppet.initTransforms(); // Required first - sets up node transforms
/// puppet.initParams();     // After transforms - sets up parameter system
/// puppet.initPhysics();    // After params - sets up physics simulation
/// ```
///
/// ## Frame Update Loop
///
/// For animated puppets, call these methods each frame:
///
/// ```dart
/// void onTick(double deltaTime) {
///   puppet.beginFrame();         // Reset transforms to base state
///   puppet.endFrame(deltaTime);  // Apply parameters and physics
/// }
/// ```
///
/// For static puppets (manual parameter control):
/// ```dart
/// puppet.beginFrame();
/// puppet.setParam('Head: Yaw-Pitch', 0.5, 0);
/// puppet.endFrame(0); // dt=0 means no physics simulation
/// ```
///
/// ## Parameter Manipulation
///
/// ```dart
/// // Set parameter value
/// puppet.setParam('Mouth: Open', 0.8);
///
/// // Get parameter value
/// final value = puppet.getParamValue('Mouth: Open');
///
/// // Find parameter by name
/// final param = puppet.getParam('Head: Yaw-Pitch');
/// ```
///
/// ## Structure
///
/// - [meta] - Puppet metadata (name, version, artist, etc.)
/// - [physics] - Physics simulation settings
/// - [nodes] - Node hierarchy tree (mesh parts, transforms, etc.)
/// - [params] - List of deformation parameters
///
/// See also:
/// - [PuppetController] for high-level puppet management
/// - [Model] for the complete model with textures
/// - [Param] for parameter details
class Puppet {
  /// Metadata about the puppet (name, version, author, etc.).
  final PuppetMeta meta;

  /// Physics simulation settings (gravity, scale, etc.).
  final PuppetPhysics physics;

  /// Node hierarchy tree containing all mesh parts and transforms.
  final PuppetNodeTree nodes;

  /// List of deformation parameters that control the puppet's appearance.
  final List<Param> params;

  /// Expression presets mapping name → parameter values.
  ///
  /// Each preset is a map of parameter names to their target values.
  /// These are embedded in the model by the parts model generator.
  final Map<String, Map<String, double>> expressions;

  /// Contexts (initialized when needed)
  TransformCtx? _transformCtx;
  ZSortCtx? _zsortCtx;
  ParamCtx? _paramCtx;
  PhysicsCtx? _physicsCtx;
  RenderCtx? _renderCtx;

  bool _transformsInitialized = false;
  bool _renderingInitialized = false;
  bool _paramsInitialized = false;
  bool _physicsInitialized = false;

  Puppet({
    required this.meta,
    required this.physics,
    required this.nodes,
    required this.params,
    this.expressions = const {},
  });

  /// Serialize puppet to JSON.
  Map<String, dynamic> toJson() {
    return {
      'meta': meta.toJson(),
      'physics': physics.toJson(),
      'nodes': nodes.toJson(),
      'param': params.map((p) => p.toJson()).toList(),
    };
  }

  /// Initialize transforms (must be called first)
  void initTransforms() {
    if (_transformsInitialized) {
      throw StateError('Transforms already initialized');
    }
    _transformCtx = TransformCtx()..initialize(nodes);
    _zsortCtx = ZSortCtx()..initialize(nodes);
    _transformsInitialized = true;
  }

  /// Initialize rendering (requires transforms)
  void initRendering() {
    if (!_transformsInitialized) {
      throw StateError('Must initialize transforms first');
    }
    if (_renderingInitialized) {
      throw StateError('Rendering already initialized');
    }
    _renderCtx = RenderCtx()..initialize(this);
    _renderingInitialized = true;
  }

  /// Initialize parameters (requires rendering)
  void initParams() {
    if (!_renderingInitialized) {
      throw StateError('Must initialize rendering first');
    }
    if (_paramsInitialized) {
      throw StateError('Params already initialized');
    }
    _paramCtx = ParamCtx(params);
    _paramsInitialized = true;
  }

  /// Initialize physics (requires params)
  void initPhysics() {
    if (!_paramsInitialized) {
      throw StateError('Must initialize params first');
    }
    if (_physicsInitialized) {
      throw StateError('Physics already initialized');
    }
    _physicsCtx = PhysicsCtx(physics, nodes);
    _physicsInitialized = true;
  }

  /// Initialize all systems
  void initAll() {
    initTransforms();
    initRendering();
    initParams();
    initPhysics();
  }

  /// Begin a new frame
  void beginFrame() {
    _transformCtx?.reset(nodes);
    _zsortCtx?.reset(nodes);
    // Reset deform stacks for all nodes
    for (final treeNode in nodes.preOrder()) {
      treeNode.data.components?.deformStack?.clear();
    }
  }

  /// End frame and update with delta time
  void endFrame(double dt) {
    // Apply parameters
    _paramCtx?.apply(nodes, _transformCtx, _zsortCtx);

    // Update transforms
    _transformCtx?.update(nodes);
    _zsortCtx?.update(nodes);

    // Update physics
    _physicsCtx?.update(dt, _paramCtx);

    // Update render data (transforms, deformed vertices, z-sort order)
    _renderCtx?.update(this);
  }

  /// Get parameter by name
  Param? getParam(String name) {
    for (final param in params) {
      if (param.name == name) return param;
    }
    return null;
  }

  /// Set parameter value
  void setParam(String name, double x, [double y = 0]) {
    _paramCtx?.setValueByName(name, Vec2(x, y));
  }

  /// Get current parameter value
  Vec2? getParamValue(String name) => _paramCtx?.getValueByName(name);

  /// Get parameter by ID
  Param? getParamById(String id) {
    for (final param in params) {
      if (param.id == id) return param;
    }
    return null;
  }

  /// Set parameter value by axis (for animations)
  void setParamAxis(
    String paramId,
    int axis,
    double value, {
    ParamMergeMode? mergeMode,
  }) {
    final param = getParamById(paramId);
    if (param == null) return;

    final currentValue = _paramCtx?.getValue(paramId) ?? Vec2.zero();
    final newValue = axis == 0
        ? Vec2(value, currentValue.y)
        : Vec2(currentValue.x, value);

    _paramCtx?.setValue(paramId, newValue);
  }

  /// Get transform context
  TransformCtx? get transformCtx => _transformCtx;

  /// Get zsort context
  ZSortCtx? get zsortCtx => _zsortCtx;

  /// Get parameter context
  ParamCtx? get paramCtx => _paramCtx;

  /// Get physics context
  PhysicsCtx? get physicsCtx => _physicsCtx;

  /// Get render context
  RenderCtx? get renderCtx => _renderCtx;
}
