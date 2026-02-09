import '../math/math.dart';

/// Physics simulation model type
enum PhysicsModel {
  rigidPendulum,
  springPendulum,
}

/// Parameter mapping mode for physics output
enum PhysicsParamMapMode {
  angleLength,
  xyProjection,
}

/// Simple physics component for pendulum-based animation
class SimplePhysics {
  /// Physics model type
  PhysicsModel model;

  /// Parameter to map physics output to
  String? mapParamId;

  /// How to map physics to parameter
  PhysicsParamMapMode mapMode;

  /// Local gravity override (null = use global)
  Vec2? localGravity;

  /// Length of pendulum in pixels
  double length;

  /// Natural frequency in Hz
  double frequency;

  /// Angle frequency in Hz (for rigid pendulum)
  double angleFrequency;

  /// Damping ratio (0 = no damping, 1 = critical damping)
  double dampingRatio;

  /// Angle damping ratio (for rigid pendulum)
  double angleDampingRatio;

  /// Output scale
  double outputScale;

  SimplePhysics({
    this.model = PhysicsModel.springPendulum,
    this.mapParamId,
    this.mapMode = PhysicsParamMapMode.xyProjection,
    this.localGravity,
    this.length = 100.0,
    this.frequency = 1.0,
    this.angleFrequency = 1.0,
    this.dampingRatio = 0.5,
    this.angleDampingRatio = 0.5,
    this.outputScale = 1.0,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'model': model == PhysicsModel.rigidPendulum
          ? 'rigid_pendulum'
          : 'spring_pendulum',
      'map_mode': mapMode == PhysicsParamMapMode.angleLength
          ? 'angle_length'
          : 'xy_projection',
      'length': length,
      'frequency': frequency,
      'angle_frequency': angleFrequency,
      'damping_ratio': dampingRatio,
      'angle_damping_ratio': angleDampingRatio,
      'output_scale': outputScale,
    };
    if (mapParamId != null) json['map_param_id'] = mapParamId;
    if (localGravity != null) {
      json['local_gravity'] = [localGravity!.x, localGravity!.y];
    }
    return json;
  }

  factory SimplePhysics.fromJson(Map<String, dynamic> json) {
    return SimplePhysics(
      model: json['model'] == 'rigid_pendulum'
          ? PhysicsModel.rigidPendulum
          : PhysicsModel.springPendulum,
      mapParamId: json['map_param_id'],
      mapMode: json['map_mode'] == 'angle_length'
          ? PhysicsParamMapMode.angleLength
          : PhysicsParamMapMode.xyProjection,
      localGravity: json['local_gravity'] != null
          ? Vec2(
              (json['local_gravity'][0] as num).toDouble(),
              (json['local_gravity'][1] as num).toDouble(),
            )
          : null,
      length: _parseDouble(json['length'], 100.0),
      frequency: _parseDouble(json['frequency'], 1.0),
      angleFrequency: _parseDouble(json['angle_frequency'], 1.0),
      dampingRatio: _parseDouble(json['damping_ratio'], 0.5),
      angleDampingRatio: _parseDouble(json['angle_damping_ratio'], 0.5),
      outputScale: _parseDouble(json['output_scale'], 1.0),
    );
  }

  static double _parseDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is List && value.isNotEmpty) {
      return (value[0] as num).toDouble();
    }
    return defaultValue;
  }
}
