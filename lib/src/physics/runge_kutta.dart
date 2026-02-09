import 'dart:math' as math;

/// 4th-order Runge-Kutta integration
class RungeKutta {
  /// Single step of RK4 integration for a first-order ODE: dy/dt = f(t, y)
  static double step(
    double y,
    double t,
    double dt,
    double Function(double t, double y) f,
  ) {
    final k1 = f(t, y);
    final k2 = f(t + dt / 2, y + dt * k1 / 2);
    final k3 = f(t + dt / 2, y + dt * k2 / 2);
    final k4 = f(t + dt, y + dt * k3);

    return y + (dt / 6) * (k1 + 2 * k2 + 2 * k3 + k4);
  }

  /// Step for a second-order ODE: d²y/dt² = f(t, y, dy/dt)
  /// Converted to system of first-order ODEs
  static (double, double) stepSecondOrder(
    double y,
    double v, // dy/dt
    double t,
    double dt,
    double Function(double t, double y, double v) f,
  ) {
    // k1
    final k1y = v;
    final k1v = f(t, y, v);

    // k2
    final k2y = v + dt * k1v / 2;
    final k2v = f(t + dt / 2, y + dt * k1y / 2, v + dt * k1v / 2);

    // k3
    final k3y = v + dt * k2v / 2;
    final k3v = f(t + dt / 2, y + dt * k2y / 2, v + dt * k2v / 2);

    // k4
    final k4y = v + dt * k3v;
    final k4v = f(t + dt, y + dt * k3y, v + dt * k3v);

    final newY = y + (dt / 6) * (k1y + 2 * k2y + 2 * k3y + k4y);
    final newV = v + (dt / 6) * (k1v + 2 * k2v + 2 * k3v + k4v);

    return (newY, newV);
  }
}

/// Damped harmonic oscillator helper
class DampedOscillator {
  final double frequency; // Natural frequency in Hz
  final double dampingRatio; // 0 = undamped, 1 = critically damped

  DampedOscillator({
    required this.frequency,
    required this.dampingRatio,
  });

  double get omega => 2 * math.pi * frequency;
  double get dampingCoeff => 2 * dampingRatio * omega;

  /// Acceleration function for the oscillator
  /// d²x/dt² = -omega² * x - 2 * zeta * omega * dx/dt
  double acceleration(double x, double v) {
    return -omega * omega * x - dampingCoeff * v;
  }

  /// Step the oscillator forward in time
  (double, double) step(double x, double v, double t, double dt) {
    return RungeKutta.stepSecondOrder(
      x,
      v,
      t,
      dt,
      (t, x, v) => acceleration(x, v),
    );
  }
}
