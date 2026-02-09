import '../math/math.dart';
import '../core/node.dart';

/// Types of node properties that can be controlled by parameter bindings.
///
/// Each type corresponds to a specific transform or visual property
/// that can be animated through parameter changes.
enum BindingValueType {
  transformTX,
  transformTY,
  transformSX,
  transformSY,
  transformRX,
  transformRY,
  transformRZ,
  deform,
  zSort,
  opacity,
}

/// Values for a parameter binding, organized as a 2D interpolation grid.
///
/// Stores values that will be applied to a node property based on
/// the parameter's current position in its 2D space.
class BindingValues {
  /// The type of node property these values control.
  final BindingValueType type;

  /// 2D matrix of values for interpolation.
  ///
  /// Organized as `values[yIndex][xIndex]`.
  /// - For 1D parameters: Only one row (Y=0)
  /// - For 2D parameters: Multiple rows for different Y positions
  final List<List<dynamic>> values;

  BindingValues({
    required this.type,
    required this.values,
  });

  /// Get value at specific x,y indices.
  ///
  /// Model data is stored as `values[xIndex][yIndex]` in the Inochi2D format.
  dynamic getValue(int xIdx, int yIdx) {
    if (xIdx >= values.length || yIdx >= values[xIdx].length) {
      return null;
    }
    return values[xIdx][yIdx];
  }

  factory BindingValues.fromJson(Map<String, dynamic> json, BindingValueType type) {
    final rawValues = json['values'] as List? ?? [];
    final values = <List<dynamic>>[];

    for (final row in rawValues) {
      if (row is List) {
        values.add(row.toList());
      }
    }

    return BindingValues(type: type, values: values);
  }

  Map<String, dynamic> toJson() {
    return {
      'values': values,
    };
  }
}

/// Links a parameter to a specific node property with interpolation values.
///
/// A binding defines how a parameter's value affects a node's property
/// (e.g., translation, rotation, scale, opacity). The binding contains
/// a grid of values that are interpolated based on the parameter's position.
class Binding {
  /// UUID of the target node.
  final PuppetNodeUuid nodeId;

  /// The values and target property type for this binding.
  final BindingValues values;

  Binding({
    required this.nodeId,
    required this.values,
  });

  factory Binding.fromJson(Map<String, dynamic> json) {
    // Field name changed from 'type' to 'param_name'
    final typeStr = json['param_name'] as String? ?? json['type'] as String? ?? '';
    final type = _parseBindingType(typeStr);

    return Binding(
      nodeId: json['node'] ?? json['node_id'] ?? 0,
      values: BindingValues.fromJson(json, type),
    );
  }

  Map<String, dynamic> toJson() {
    final json = values.toJson();
    json['node'] = nodeId;
    json['param_name'] = _bindingTypeToString(values.type);
    return json;
  }

  static String _bindingTypeToString(BindingValueType type) {
    switch (type) {
      case BindingValueType.transformTX:
        return 'transform.t.x';
      case BindingValueType.transformTY:
        return 'transform.t.y';
      case BindingValueType.transformSX:
        return 'transform.s.x';
      case BindingValueType.transformSY:
        return 'transform.s.y';
      case BindingValueType.transformRX:
        return 'transform.r.x';
      case BindingValueType.transformRY:
        return 'transform.r.y';
      case BindingValueType.transformRZ:
        return 'transform.r.z';
      case BindingValueType.deform:
        return 'deform';
      case BindingValueType.zSort:
        return 'zsort';
      case BindingValueType.opacity:
        return 'opacity';
    }
  }

  static BindingValueType _parseBindingType(String type) {
    final lower = type.toLowerCase();

    // Handle both old format (transform_tx) and new format (transform.t.x)
    switch (lower) {
      case 'transform_tx':
      case 'translatex':
      case 'transform.t.x':
        return BindingValueType.transformTX;
      case 'transform_ty':
      case 'translatey':
      case 'transform.t.y':
        return BindingValueType.transformTY;
      case 'transform_sx':
      case 'scalex':
      case 'transform.s.x':
        return BindingValueType.transformSX;
      case 'transform_sy':
      case 'scaley':
      case 'transform.s.y':
        return BindingValueType.transformSY;
      case 'transform_rx':
      case 'rotatex':
      case 'transform.r.x':
        return BindingValueType.transformRX;
      case 'transform_ry':
      case 'rotatey':
      case 'transform.r.y':
        return BindingValueType.transformRY;
      case 'transform_rz':
      case 'rotatez':
      case 'transform.r.z':
        return BindingValueType.transformRZ;
      case 'deform':
        return BindingValueType.deform;
      case 'zsort':
      case 'z_sort':
        return BindingValueType.zSort;
      case 'opacity':
        return BindingValueType.opacity;
      default:
        return BindingValueType.transformTX;
    }
  }
}

/// A deformation parameter that controls puppet animation.
///
/// [Param] represents an animatable parameter (like "Head Yaw", "Mouth Open", etc.)
/// that can be manipulated to deform the puppet. Parameters can be 1D (single axis)
/// or 2D (X and Y axes) and contain bindings to node properties.
///
/// ## Parameter Types
///
/// - **1D Parameter**: Single axis control (e.g., "Mouth: Open" from 0 to 1)
/// - **2D Parameter**: Two-axis control (e.g., "Head: Yaw-Pitch" from -1,-1 to 1,1)
///
/// ## Basic Usage
///
/// ```dart
/// // Get parameter from puppet
/// final headParam = puppet.getParam('Head: Yaw-Pitch');
/// if (headParam != null) {
///   print('Name: ${headParam.name}');
///   print('Is 2D: ${headParam.is2D}');
///   print('Range: ${headParam.minValue} to ${headParam.maxValue}');
///   print('Bindings: ${headParam.bindings.length}');
/// }
///
/// // Set parameter value
/// puppet.setParam('Head: Yaw-Pitch', 0.5, 0.3);
/// ```
///
/// ## How Parameters Work
///
/// 1. User sets parameter value (e.g., via `setParam`)
/// 2. Value is normalized to 0-1 range based on min/max
/// 3. Interpolation indices are computed from axis points
/// 4. Binding values are interpolated based on indices
/// 5. Node properties (transforms, deforms) are updated
///
/// ## Bindings
///
/// Each parameter has multiple [Binding]s that connect it to node properties:
/// - Transform (translation, rotation, scale)
/// - Deformation (mesh vertex positions)
/// - Visual properties (opacity, z-sort)
///
/// See also:
/// - [Puppet.setParam] for setting parameter values
/// - [Puppet.getParam] for finding parameters by name
/// - [Binding] for parameter-to-node connections
class Param {
  /// Unique identifier (UUID as string).
  final String id;

  /// Human-readable name (e.g., "Head: Yaw-Pitch", "Mouth: Open").
  final String name;

  /// Minimum value for X and Y axes.
  ///
  /// Typical range: `Vec2(-1, -1)` for centered 2D parameters.
  final Vec2 minValue;

  /// Maximum value for X and Y axes.
  ///
  /// Typical range: `Vec2(1, 1)` for centered 2D parameters.
  final Vec2 maxValue;

  /// Default resting value.
  ///
  /// Usually `Vec2.zero()` for centered parameters.
  final Vec2 defaultValue;

  /// Normalized positions (0-1) for X-axis interpolation points.
  ///
  /// Defines where binding values are sampled along the X axis.
  /// Example: `[0.0, 0.5, 1.0]` creates three interpolation points.
  final List<double> axisPointsX;

  /// Normalized positions (0-1) for Y-axis interpolation points.
  ///
  /// For 1D parameters: `[0.0]` (single point)
  /// For 2D parameters: Multiple points (e.g., `[0.0, 0.5, 1.0]`)
  final List<double> axisPointsY;

  /// Bindings that connect this parameter to node properties.
  ///
  /// Each binding targets a specific node and property type.
  final List<Binding> bindings;

  /// Whether this is a 2D parameter (has Y-axis variation).
  ///
  /// Returns true if there are multiple Y-axis points.
  bool get is2D => axisPointsY.length > 1;

  Param({
    required this.id,
    required this.name,
    this.minValue = const Vec2(-1, -1),
    this.maxValue = const Vec2(1, 1),
    this.defaultValue = const Vec2.zero(),
    this.axisPointsX = const [0.0, 1.0],
    this.axisPointsY = const [0.0],
    this.bindings = const [],
  });

  /// Normalize a value to 0-1 range
  Vec2 normalize(Vec2 value) {
    final rangeX = maxValue.x - minValue.x;
    final rangeY = maxValue.y - minValue.y;

    return Vec2(
      rangeX != 0 ? (value.x - minValue.x) / rangeX : 0,
      rangeY != 0 ? (value.y - minValue.y) / rangeY : 0,
    );
  }

  /// Find interpolation indices for a normalized value.
  ///
  /// Uses reference-compatible logic: binary search to find the enclosing interval,
  /// then clamp to that local interval before computing t. This prevents dead
  /// zones when axis points don't span [0, 1].
  (int, int, double) findInterpIndices(double normalized, List<double> axisPoints) {
    if (axisPoints.length <= 1) {
      return (0, 0, 0.0);
    }

    final lastIdx = axisPoints.length - 1;

    // reference-compatible: find insertion point via linear scan
    // (axis points are typically 3-5 elements, so linear is fine)
    int low, high;
    int insertPos = axisPoints.length;
    bool exactMatch = false;
    int exactIdx = 0;

    for (int i = 0; i < axisPoints.length; i++) {
      if ((axisPoints[i] - normalized).abs() < 1e-9) {
        exactMatch = true;
        exactIdx = i;
        break;
      }
      if (axisPoints[i] > normalized) {
        insertPos = i;
        break;
      }
    }

    if (exactMatch) {
      // Exact match: use the point and its neighbor
      if (exactIdx >= lastIdx) {
        low = lastIdx - 1;
        high = lastIdx;
      } else {
        low = exactIdx;
        high = exactIdx + 1;
      }
    } else {
      // Between points: insertPos-1 .. insertPos
      low = insertPos - 1;
      high = insertPos;
    }

    // Boundary clamp
    low = low.clamp(0, lastIdx);
    high = high.clamp(0, lastIdx);

    // reference-compatible: clamp to local interval, then compute t
    final rangeBeg = axisPoints[low];
    final rangeEnd = axisPoints[high];
    final clampedNorm = normalized.clamp(rangeBeg, rangeEnd);
    final range = rangeEnd - rangeBeg;
    final t = range != 0 ? (clampedNorm - rangeBeg) / range : 0.0;

    return (low, high, t);
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'uuid': int.tryParse(id) ?? id,
      'name': name,
      'min': [minValue.x, minValue.y],
      'max': [maxValue.x, maxValue.y],
      'defaults': [defaultValue.x, defaultValue.y],
      'axis_points': [
        axisPointsX,
        if (axisPointsY.isNotEmpty) axisPointsY,
      ],
      'bindings': bindings.map((b) => b.toJson()).toList(),
    };
    return json;
  }

  factory Param.fromJson(Map<String, dynamic> json) {
    // Parse axis points (format: [[x-axis points], [y-axis points]])
    List<double> axisPointsXRaw = [0.0, 1.0];
    List<double> axisPointsYRaw = [];

    final axisPoints = json['axis_points'] as List?;
    if (axisPoints != null && axisPoints.isNotEmpty) {
      if (axisPoints[0] is List) {
        axisPointsXRaw = (axisPoints[0] as List).map((e) => (e as num).toDouble()).toList();
      }
      if (axisPoints.length > 1 && axisPoints[1] is List) {
        axisPointsYRaw = (axisPoints[1] as List).map((e) => (e as num).toDouble()).toList();
      }
    }

    // Parse bindings
    final bindingsRaw = json['bindings'] as List? ?? [];
    final bindings = bindingsRaw
        .map((b) => Binding.fromJson(b as Map<String, dynamic>))
        .toList();

    // uuid is an int, convert to string for id
    final idValue = json['uuid'] ?? json['id'] ?? json['name'] ?? '';
    final id = idValue is int ? idValue.toString() : idValue.toString();

    return Param(
      id: id,
      name: json['name'] ?? '',
      minValue: _parseVec2(json['min'] ?? json['min_value'], const Vec2(-1, -1)),
      maxValue: _parseVec2(json['max'] ?? json['max_value'], const Vec2(1, 1)),
      defaultValue: _parseVec2(json['defaults'] ?? json['default_value'], const Vec2.zero()),
      axisPointsX: axisPointsXRaw,
      axisPointsY: axisPointsYRaw,
      bindings: bindings,
    );
  }

  static Vec2 _parseVec2(dynamic value, Vec2 defaultVal) {
    if (value == null) return defaultVal;
    if (value is List && value.length >= 2) {
      return Vec2(
        (value[0] as num).toDouble(),
        (value[1] as num).toDouble(),
      );
    }
    if (value is num) {
      return Vec2(value.toDouble(), 0);
    }
    return defaultVal;
  }
}
