import 'dart:math' as math;
import '../math/math.dart';
import '../core/node.dart';
import '../core/puppet.dart';
import '../components/simple_physics.dart';
import '../params/param_ctx.dart';
import 'pendulum.dart';

/// Physics simulation state for a node
class PhysicsState {
  final PuppetNodeUuid nodeId;
  final SimplePhysics config;
  final Pendulum pendulum;

  PhysicsState({
    required this.nodeId,
    required this.config,
    required this.pendulum,
  });
}

/// Physics context for managing physics simulation
class PhysicsCtx {
  final PuppetPhysics globalPhysics;
  final List<PhysicsState> _states = [];
  double _elapsedTime = 0;

  static const double _maxFrameTime = 10.0; // Max 10 seconds per frame
  static const double _timestep = 0.01; // 10ms timestep for stability

  PhysicsCtx(this.globalPhysics, PuppetNodeTree nodes) {
    _initialize(nodes);
  }

  void _initialize(PuppetNodeTree nodes) {
    for (final treeNode in nodes.preOrder()) {
      final node = treeNode.data;
      final components = node.components;
      if (components == null || components.simplePhysics == null) continue;

      final config = components.simplePhysics!;
      final anchor = Vec2(
        node.transOffset.translation.x,
        node.transOffset.translation.y,
      );

      Pendulum pendulum;
      if (config.model == PhysicsModel.rigidPendulum) {
        pendulum = RigidPendulum(
          anchor: anchor,
          length: config.length,
          frequency: config.angleFrequency,
          dampingRatio: config.angleDampingRatio,
        );
      } else {
        pendulum = SpringPendulum(
          anchor: anchor,
          length: config.length,
          frequencyX: config.frequency,
          frequencyY: config.frequency,
          dampingRatioX: config.dampingRatio,
          dampingRatioY: config.dampingRatio,
        );
      }

      _states.add(PhysicsState(
        nodeId: node.uuid,
        config: config,
        pendulum: pendulum,
      ));
    }
  }

  /// Update physics simulation
  void update(double dt, ParamCtx? paramCtx) {
    if (dt < 0) {
      throw ArgumentError('Delta time cannot be negative');
    }

    // Clamp frame time
    dt = math.min(dt, _maxFrameTime);
    _elapsedTime += dt;

    // Fixed timestep integration
    while (dt >= _timestep) {
      _tick(_timestep, paramCtx);
      dt -= _timestep;
    }

    // Handle remaining time
    if (dt > 0) {
      _tick(dt, paramCtx);
    }
  }

  void _tick(double dt, ParamCtx? paramCtx) {
    for (final state in _states) {
      final config = state.config;

      // Determine gravity
      final gravity = config.localGravity ?? globalPhysics.gravity;

      // Update pendulum
      state.pendulum.tick(dt, gravity);

      // Map output to parameter
      if (config.mapParamId != null && paramCtx != null) {
        final output = state.pendulum.calcOutput(gravity);
        final scaled = output * config.outputScale;

        paramCtx.setValue(config.mapParamId!, scaled);
      }
    }
  }

  /// Reset all physics states
  void reset() {
    for (final state in _states) {
      state.pendulum.reset();
    }
    _elapsedTime = 0;
  }

  /// Get elapsed simulation time
  double get elapsedTime => _elapsedTime;
}
