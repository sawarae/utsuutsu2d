/// Core animation data structures
library;

/// Interpolation mode for animation keyframes
enum AnimInterpolateMode {
  /// Snap to nearest value
  nearest,

  /// Linearly interpolate between values
  linear,

  /// Snap to current keyframe (no interpolation)
  stepped,

  /// Smooth curve using quadratic/bezier interpolation
  quadratic,

  /// Smooth curve using cubic (Catmull-Rom) interpolation
  cubic,
}

/// Parse interpolation mode from string
AnimInterpolateMode parseAnimInterpolateMode(String value) {
  switch (value.toLowerCase()) {
    case 'nearest':
      return AnimInterpolateMode.nearest;
    case 'linear':
      return AnimInterpolateMode.linear;
    case 'stepped':
      return AnimInterpolateMode.stepped;
    case 'bezier':
    case 'quadratic':
      return AnimInterpolateMode.quadratic;
    case 'cubic':
      return AnimInterpolateMode.cubic;
    default:
      return AnimInterpolateMode.linear;
  }
}

/// A single keyframe in an animation
class Keyframe {
  /// The frame number at which this keyframe occurs
  final int frame;

  /// The value of the parameter at this frame
  final double value;

  /// Interpolation tension for cubic/quadratic modes (0.0 to 1.0)
  final double tension;

  const Keyframe({
    required this.frame,
    required this.value,
    this.tension = 0.5,
  });

  factory Keyframe.fromJson(Map<String, dynamic> json) {
    return Keyframe(
      frame: json['frame'] as int? ?? 0,
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      tension: (json['tension'] as num?)?.toDouble() ?? 0.5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'frame': frame,
      'value': value,
      'tension': tension,
    };
  }

  @override
  String toString() => 'Keyframe(frame: $frame, value: $value, tension: $tension)';
}

/// Merge mode for parameter values
enum ParamMergeMode {
  /// Add to existing value
  additive,

  /// Weighted average with existing value
  weighted,

  /// Multiply with existing value
  multiplicative,

  /// Force set to this value
  forced,

  /// Pass through (use parameter's default merge mode)
  passthrough,
}

/// Parse merge mode from string
ParamMergeMode parseMergeMode(String value) {
  switch (value.toLowerCase()) {
    case 'additive':
      return ParamMergeMode.additive;
    case 'weighted':
      return ParamMergeMode.weighted;
    case 'multiplicative':
      return ParamMergeMode.multiplicative;
    case 'forced':
      return ParamMergeMode.forced;
    case 'passthrough':
      return ParamMergeMode.passthrough;
    default:
      return ParamMergeMode.passthrough;
  }
}

/// Reference to a parameter and its axis
class AnimationParameterRef {
  /// Parameter ID (UUID as string)
  final String paramId;

  /// Target axis (0 for X, 1 for Y)
  final int targetAxis;

  const AnimationParameterRef({
    required this.paramId,
    required this.targetAxis,
  });

  @override
  String toString() => 'AnimationParameterRef(paramId: $paramId, axis: $targetAxis)';
}

/// A lane of animation targeting a specific parameter axis
class AnimationLane {
  /// Reference to the target parameter
  final AnimationParameterRef paramRef;

  /// List of keyframes in this lane (sorted by frame number)
  final List<Keyframe> keyframes;

  /// Interpolation mode for this lane
  final AnimInterpolateMode interpolation;

  /// Merge mode for parameter values
  final ParamMergeMode mergeMode;

  AnimationLane({
    required this.paramRef,
    required this.keyframes,
    this.interpolation = AnimInterpolateMode.linear,
    this.mergeMode = ParamMergeMode.forced,
  }) {
    // Ensure keyframes are sorted by frame number
    keyframes.sort((a, b) => a.frame.compareTo(b.frame));
  }

  factory AnimationLane.fromJson(Map<String, dynamic> json) {
    final keyframesJson = json['keyframes'] as List? ?? json['frames'] as List? ?? [];
    final keyframes = keyframesJson
        .map((k) => Keyframe.fromJson(k as Map<String, dynamic>))
        .toList();

    final interpolationValue = json['interpolation'];
    final interpolation = interpolationValue is int
        ? AnimInterpolateMode.values[interpolationValue]
        : parseAnimInterpolateMode(interpolationValue?.toString() ?? 'linear');

    final mergeModeValue = json['merge_mode'];
    final mergeMode = mergeModeValue is int
        ? ParamMergeMode.values[mergeModeValue]
        : parseMergeMode(mergeModeValue?.toString() ?? 'forced');

    return AnimationLane(
      paramRef: AnimationParameterRef(
        paramId: json['guid']?.toString() ?? json['param_id']?.toString() ?? '',
        targetAxis: json['target'] as int? ?? json['target_axis'] as int? ?? 0,
      ),
      keyframes: keyframes,
      interpolation: interpolation,
      mergeMode: mergeMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'guid': paramRef.paramId,
      'target': paramRef.targetAxis,
      'interpolation': interpolation.index,
      'merge_mode': mergeMode.index,
      'keyframes': keyframes.map((k) => k.toJson()).toList(),
    };
  }

  /// Get the interpolated value at a specific frame
  double getValue(double frame, {bool snapSubframes = false}) {
    if (keyframes.isEmpty) return 0.0;
    if (keyframes.length == 1) return keyframes[0].value;

    // Snap to integer frame if requested
    if (snapSubframes) {
      frame = frame.floorToDouble();
    }

    // Check for exact match first
    for (int i = 0; i < keyframes.length; i++) {
      if (keyframes[i].frame == frame) {
        return keyframes[i].value;
      }
    }

    // Find surrounding keyframes
    for (int i = 0; i < keyframes.length; i++) {
      if (keyframes[i].frame < frame) continue;

      // If we're at the first keyframe, return its value
      if (i == 0) return keyframes[0].value;

      final prevFrame = keyframes[i - 1];
      final nextFrame = keyframes[i];

      // Calculate interpolation parameter (0.0 to 1.0)
      final tonext = nextFrame.frame.toDouble() - frame;
      final ilen = nextFrame.frame.toDouble() - prevFrame.frame.toDouble();
      final t = ilen > 0 ? 1.0 - (tonext / ilen) : 0.0;

      return _interpolate(prevFrame, nextFrame, t, i);
    }

    // Past the last keyframe
    return keyframes.last.value;
  }

  /// Interpolate between two keyframes
  double _interpolate(Keyframe prev, Keyframe next, double t, int nextIndex) {
    switch (interpolation) {
      case AnimInterpolateMode.nearest:
        return t > 0.5 ? next.value : prev.value;

      case AnimInterpolateMode.stepped:
        return prev.value;

      case AnimInterpolateMode.linear:
        return _lerp(prev.value, next.value, t);

      case AnimInterpolateMode.cubic:
        return _cubicInterpolate(prev, next, t, nextIndex);

      case AnimInterpolateMode.quadratic:
        return _quadraticInterpolate(prev, next, t);
    }
  }

  /// Linear interpolation
  double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  /// Cubic (Catmull-Rom) interpolation
  double _cubicInterpolate(Keyframe prev, Keyframe next, double t, int nextIndex) {
    // Get surrounding points for cubic interpolation
    final prevPrev = nextIndex >= 2 ? keyframes[nextIndex - 2].value : prev.value;
    final curr = prev.value;
    final next1 = next.value;
    final next2 = nextIndex + 1 < keyframes.length
        ? keyframes[nextIndex + 1].value
        : next.value;

    return _cubic(prevPrev, curr, next1, next2, t);
  }

  /// Cubic polynomial interpolation (Catmull-Rom)
  double _cubic(double p0, double p1, double p2, double p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;

    return 0.5 *
        ((2 * p1) +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
  }

  /// Quadratic (Hermite) interpolation with tension
  double _quadraticInterpolate(Keyframe prev, Keyframe next, double t) {
    final tension = next.tension;
    final h = _hermite(0, 2 * tension, 1, 2 * tension, t);
    return _lerp(prev.value, next.value, h.clamp(0.0, 1.0));
  }

  /// Hermite interpolation
  double _hermite(double p0, double m0, double p1, double m1, double t) {
    final t2 = t * t;
    final t3 = t2 * t;

    return (2 * t3 - 3 * t2 + 1) * p0 +
        (t3 - 2 * t2 + t) * m0 +
        (-2 * t3 + 3 * t2) * p1 +
        (t3 - t2) * m1;
  }

  @override
  String toString() => 'AnimationLane(param: ${paramRef.paramId}, '
      'axis: ${paramRef.targetAxis}, keyframes: ${keyframes.length})';
}

/// Complete animation data
class Animation {
  /// Name of the animation
  final String name;

  /// Timestep per frame in seconds (default: ~60fps)
  final double timestep;

  /// Total length in frames
  final int length;

  /// Whether this is an additive animation
  final bool additive;

  /// Weight for additive animations (0.0 to 1.0)
  final double weight;

  /// Frame where lead-in ends (-1 if no lead-in)
  final int leadIn;

  /// Frame where lead-out starts (-1 if no lead-out)
  final int leadOut;

  /// All animation lanes
  final List<AnimationLane> lanes;

  const Animation({
    required this.name,
    this.timestep = 0.0166, // ~60fps
    required this.length,
    this.additive = false,
    this.weight = 1.0,
    this.leadIn = -1,
    this.leadOut = -1,
    required this.lanes,
  });

  /// Duration in seconds
  double get duration => length * timestep;

  /// Has lead-in section
  bool get hasLeadIn => leadIn > 0 && leadIn + 1 < length;

  /// Has lead-out section
  bool get hasLeadOut => leadOut > 0 && leadOut + 1 < length;

  factory Animation.fromJson(String name, Map<String, dynamic> json) {
    final lanesJson = json['lanes'] as List? ?? [];
    final lanes = lanesJson
        .map((l) => AnimationLane.fromJson(l as Map<String, dynamic>))
        .toList();

    return Animation(
      name: name,
      timestep: (json['timestep'] as num?)?.toDouble() ?? 0.0166,
      length: json['length'] as int? ?? 0,
      additive: json['additive'] as bool? ?? false,
      weight: (json['animationWeight'] as num?)?.toDouble() ??
          (json['animation_weight'] as num?)?.toDouble() ??
          1.0,
      leadIn: json['leadIn'] as int? ?? json['lead_in'] as int? ?? -1,
      leadOut: json['leadOut'] as int? ?? json['lead_out'] as int? ?? -1,
      lanes: lanes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestep': timestep,
      'length': length,
      'additive': additive,
      'animationWeight': weight,
      'leadIn': leadIn,
      'leadOut': leadOut,
      'lanes': lanes.map((l) => l.toJson()).toList(),
    };
  }

  @override
  String toString() => 'Animation(name: $name, length: $length frames, '
      'duration: ${duration.toStringAsFixed(2)}s, lanes: ${lanes.length})';
}
