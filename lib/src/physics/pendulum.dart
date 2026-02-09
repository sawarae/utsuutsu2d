import 'dart:math' as math;
import '../math/math.dart';
import 'runge_kutta.dart';

/// Base class for pendulum physics
abstract class Pendulum {
  Vec2 anchor;
  Vec2 position;
  Vec2 velocity;
  double length;

  Pendulum({
    required this.anchor,
    required this.length,
    Vec2? position,
    Vec2? velocity,
  })  : position = position ?? Vec2(0, length),
        velocity = velocity ?? const Vec2.zero();

  /// Calculate output value for parameter mapping
  Vec2 calcOutput(Vec2 gravity);

  /// Update physics simulation
  void tick(double dt, Vec2 gravity);

  /// Reset to initial state
  void reset() {
    position = Vec2(0, length);
    velocity = const Vec2.zero();
  }
}

/// Rigid pendulum (angle-based)
class RigidPendulum extends Pendulum {
  double angle = 0;
  double angularVelocity = 0;
  final double frequency;
  final double dampingRatio;

  RigidPendulum({
    required super.anchor,
    required super.length,
    this.frequency = 1.0,
    this.dampingRatio = 0.5,
  });

  @override
  void tick(double dt, Vec2 gravity) {
    // Gravity magnitude
    final g = gravity.length;
    if (g == 0 || length == 0) return;

    // Natural frequency based on pendulum length
    final omega0 = math.sqrt(g / length);
    final dampingCoeff = 2 * dampingRatio * omega0 * frequency;

    // Gravity direction angle
    final gravityAngle = math.atan2(gravity.x, gravity.y);

    // Angular acceleration: -g/L * sin(theta) - damping
    double acceleration(double t, double theta, double omega) {
      final relAngle = theta - gravityAngle;
      return -omega0 * omega0 * math.sin(relAngle) - dampingCoeff * omega;
    }

    // RK4 integration
    final (newAngle, newOmega) = RungeKutta.stepSecondOrder(
      angle,
      angularVelocity,
      0,
      dt,
      acceleration,
    );

    angle = newAngle;
    angularVelocity = newOmega;

    // Update position
    position = Vec2(
      anchor.x + length * math.sin(angle),
      anchor.y + length * math.cos(angle),
    );
  }

  @override
  Vec2 calcOutput(Vec2 gravity) {
    // Return angle and length-normalized position
    return Vec2(angle, length > 0 ? (position - anchor).length / length : 0);
  }

  @override
  void reset() {
    super.reset();
    angle = 0;
    angularVelocity = 0;
  }
}

/// Spring pendulum (position-based)
class SpringPendulum extends Pendulum {
  final double frequencyX;
  final double frequencyY;
  final double dampingRatioX;
  final double dampingRatioY;

  late DampedOscillator _oscillatorX;
  late DampedOscillator _oscillatorY;

  double _offsetX = 0;
  double _offsetY = 0;
  double _velocityX = 0;
  double _velocityY = 0;

  SpringPendulum({
    required super.anchor,
    required super.length,
    this.frequencyX = 1.0,
    this.frequencyY = 1.0,
    this.dampingRatioX = 0.5,
    this.dampingRatioY = 0.5,
  }) {
    _oscillatorX = DampedOscillator(
      frequency: frequencyX,
      dampingRatio: dampingRatioX,
    );
    _oscillatorY = DampedOscillator(
      frequency: frequencyY,
      dampingRatio: dampingRatioY,
    );
  }

  @override
  void tick(double dt, Vec2 gravity) {
    // Add gravity as external force
    final forceX = gravity.x;
    final forceY = gravity.y;

    // Step X oscillator
    final (newOffsetX, newVelX) = _stepWithForce(
      _offsetX,
      _velocityX,
      dt,
      forceX,
      _oscillatorX,
    );

    // Step Y oscillator
    final (newOffsetY, newVelY) = _stepWithForce(
      _offsetY,
      _velocityY,
      dt,
      forceY,
      _oscillatorY,
    );

    _offsetX = newOffsetX;
    _velocityX = newVelX;
    _offsetY = newOffsetY;
    _velocityY = newVelY;

    // Update position
    position = Vec2(
      anchor.x + _offsetX,
      anchor.y + length + _offsetY,
    );
  }

  (double, double) _stepWithForce(
    double offset,
    double velocity,
    double dt,
    double force,
    DampedOscillator oscillator,
  ) {
    // Modified acceleration with external force
    double acceleration(double t, double x, double v) {
      return oscillator.acceleration(x, v) + force;
    }

    return RungeKutta.stepSecondOrder(offset, velocity, 0, dt, acceleration);
  }

  @override
  Vec2 calcOutput(Vec2 gravity) {
    // Return normalized offset
    return Vec2(
      length > 0 ? _offsetX / length : 0,
      length > 0 ? _offsetY / length : 0,
    );
  }

  @override
  void reset() {
    super.reset();
    _offsetX = 0;
    _offsetY = 0;
    _velocityX = 0;
    _velocityY = 0;
  }
}
