import '../math/math.dart';

/// Curve type for path deformation
enum PathDeformCurveType {
  bezier,
  spline,
}

/// PathDeform component for path-based mesh deformation
///
/// Phase 1: Data structure and parsing only. Deformation logic
/// will be implemented in future phases.
class PathDeform {
  /// Control points defining the deformation path
  final List<Vec2> controlPoints;

  /// Type of curve interpolation
  final PathDeformCurveType curveType;

  /// Whether physics simulation drives the deformation
  final bool physicsOnly;

  /// Whether deformation is applied dynamically (post-process)
  final bool dynamicDeformation;

  /// Raw JSON data preserved for future phases (physics config, etc.)
  final Map<String, dynamic>? rawData;

  PathDeform({
    required this.controlPoints,
    this.curveType = PathDeformCurveType.spline,
    this.physicsOnly = false,
    this.dynamicDeformation = false,
    this.rawData,
  });

  Map<String, dynamic> toJson() {
    // If rawData was preserved, use it as the base to avoid data loss
    if (rawData != null) {
      return Map<String, dynamic>.from(rawData!);
    }

    // Flatten control points to [x, y, x, y, ...]
    final vertices = <double>[];
    for (final p in controlPoints) {
      vertices.add(p.x);
      vertices.add(p.y);
    }

    return {
      'vertices': vertices,
      'curve_type': curveType == PathDeformCurveType.bezier ? 'bezier' : 'spline',
      'physics_only': physicsOnly,
      'dynamic_deformation': dynamicDeformation,
    };
  }

  factory PathDeform.fromJson(Map<String, dynamic> json) {
    // Parse control points from flat vertex list [x, y, x, y, ...]
    final controlPoints = <Vec2>[];
    final verticesRaw = json['vertices'] as List?;
    if (verticesRaw != null) {
      for (int i = 0; i + 1 < verticesRaw.length; i += 2) {
        controlPoints.add(Vec2(
          (verticesRaw[i] as num).toDouble(),
          (verticesRaw[i + 1] as num).toDouble(),
        ));
      }
    }

    // Parse curve type
    PathDeformCurveType curveType = PathDeformCurveType.spline;
    final curveTypeRaw = json['curve_type'];
    if (curveTypeRaw is String) {
      switch (curveTypeRaw.toLowerCase()) {
        case 'bezier':
          curveType = PathDeformCurveType.bezier;
          break;
        case 'spline':
          curveType = PathDeformCurveType.spline;
          break;
      }
    } else if (curveTypeRaw is int) {
      // Enum index: 0 = Bezier, 1 = Spline (from reference D code)
      curveType = curveTypeRaw == 0
          ? PathDeformCurveType.bezier
          : PathDeformCurveType.spline;
    }

    return PathDeform(
      controlPoints: controlPoints,
      curveType: curveType,
      physicsOnly: json['physics_only'] as bool? ?? false,
      dynamicDeformation: json['dynamic_deformation'] as bool? ?? false,
      rawData: json,
    );
  }
}
