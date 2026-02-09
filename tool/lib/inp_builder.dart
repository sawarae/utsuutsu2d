import 'dart:convert';
import 'dart:typed_data';

/// Builder for creating INP files in TRNSRTS binary format
///
/// Format:
/// ```
/// TRNSRTS\0           (8 bytes magic)
/// [json_length]       (4 bytes big-endian u32)
/// [puppet.json]       (UTF-8 JSON)
/// TEX_SECT            (8 bytes marker)
/// [texture_count]     (4 bytes big-endian u32)
/// For each texture:
///   [data_length]     (4 bytes big-endian u32)
///   [tex_type]        (1 byte: 0=PNG)
///   [image_data]      (raw PNG bytes)
/// ```
class InpBuilder {
  static const _trnsrtsMagic = [0x54, 0x52, 0x4E, 0x53, 0x52, 0x54, 0x53, 0x00]; // "TRNSRTS\0"
  static const _texSectMagic = [0x54, 0x45, 0x58, 0x5F, 0x53, 0x45, 0x43, 0x54]; // "TEX_SECT"

  final Map<String, dynamic> _puppet = {};
  final List<Uint8List> _textures = [];

  InpBuilder();

  /// Set puppet metadata
  /// Set puppet metadata.
  ///
  /// All fields are emitted in JSON (as null if not provided) for
  /// compatibility with inox2d's parser which requires keys to exist.
  InpBuilder meta({
    String? name,
    String? version,
    String? author,
    String? rigger,
    String? artist,
    String? rights,
    String? copyright,
    String? licenseUrl,
    String? contact,
    String? reference,
    String? thumbnailId,
    bool preservePixels = false,
  }) {
    _puppet['meta'] = <String, dynamic>{
      'name': name,
      'version': version ?? '1.0',
      'rigger': rigger,
      'artist': artist,
      'copyright': copyright,
      // Emit both key styles for kokoro2d (snake_case) and inox2d (camelCase)
      'license_url': licenseUrl,
      'licenseURL': licenseUrl,
      'contact': contact,
      'reference': reference,
      'thumbnail_id': thumbnailId != null ? int.tryParse(thumbnailId!) ?? 0 : null,
      'thumbnailId': thumbnailId != null ? int.tryParse(thumbnailId!) ?? 0 : null,
      'preserve_pixels': preservePixels,
      'preservePixels': preservePixels,
    };
    return this;
  }

  /// Set physics settings.
  ///
  /// Emits both key styles for kokoro2d and inox2d compatibility.
  InpBuilder physics({
    double? pixelsPerMeter,
    double? gravity,
  }) {
    _puppet['physics'] = <String, dynamic>{
      'pixels_per_meter': pixelsPerMeter ?? 1000.0,
      'pixelsPerMeter': pixelsPerMeter ?? 1000.0,
      'gravity': gravity ?? 9.8,
    };
    return this;
  }

  /// Set the node tree structure
  InpBuilder nodes(Map<String, dynamic> nodesJson) {
    _puppet['nodes'] = nodesJson;
    return this;
  }

  /// Set parameters
  InpBuilder params(List<Map<String, dynamic>> paramsJson) {
    _puppet['param'] = paramsJson;
    return this;
  }

  /// Set expression presets (name → {paramName: value})
  InpBuilder expressions(Map<String, dynamic> expressionsJson) {
    _puppet['expressions'] = expressionsJson;
    return this;
  }

  /// Add a texture (PNG bytes)
  InpBuilder addTexture(Uint8List pngData) {
    _textures.add(pngData);
    return this;
  }

  /// Build the final INP file bytes
  Uint8List build() {
    final buffer = BytesBuilder();

    // 1. Write TRNSRTS magic (8 bytes)
    buffer.add(_trnsrtsMagic);

    // 2. Write JSON payload
    final jsonStr = jsonEncode(_puppet);
    final jsonBytes = utf8.encode(jsonStr);
    _writeUint32BE(buffer, jsonBytes.length);
    buffer.add(jsonBytes);

    // 3. Write TEX_SECT marker (8 bytes)
    buffer.add(_texSectMagic);

    // 4. Write texture count
    _writeUint32BE(buffer, _textures.length);

    // 5. Write each texture
    for (final texture in _textures) {
      _writeUint32BE(buffer, texture.length); // data length
      buffer.addByte(0); // tex_type: 0=PNG
      buffer.add(texture); // image data
    }

    return buffer.toBytes();
  }

  /// Write a 32-bit unsigned integer in big-endian format
  void _writeUint32BE(BytesBuilder buffer, int value) {
    buffer.addByte((value >> 24) & 0xFF);
    buffer.addByte((value >> 16) & 0xFF);
    buffer.addByte((value >> 8) & 0xFF);
    buffer.addByte(value & 0xFF);
  }
}

/// Helper class to build node trees
class NodeTreeBuilder {
  final Map<String, dynamic> root;
  final List<Map<String, dynamic>> children = [];

  NodeTreeBuilder({
    required int uuid,
    String name = 'Root',
    bool enabled = true,
  }) : root = {
    'uuid': uuid,
    'name': name,
    'type': 'Node',
    'enabled': enabled,
    'zsort': 0.0,
    'lockToRoot': false,
    'transform': {
      'trans': [0.0, 0.0, 0.0],
      'rot': [0.0, 0.0, 0.0],
      'scale': [1.0, 1.0],
    },
  };

  /// Add a child node
  NodeTreeBuilder addChild(Map<String, dynamic> node) {
    children.add(node);
    return this;
  }

  /// Build the node tree JSON.
  ///
  /// Produces inox2d-compatible format: the root node object has `children`
  /// embedded. Also includes `root` key for kokoro2d backward compatibility.
  Map<String, dynamic> build() {
    final result = Map<String, dynamic>.from(root);
    result['children'] = children;
    // kokoro2d backward compat: also include 'root' key
    result['root'] = root;
    return result;
  }
}

/// Helper to create a drawable part node.
///
/// Always emits `transform` and `lockToRoot` for inox2d compatibility.
Map<String, dynamic> createPartNode({
  required int uuid,
  required String name,
  required Map<String, dynamic> mesh,
  int? textureId,
  bool enabled = true,
  double zsort = 0.0,
  List<double>? translation,
  List<double>? rotation,
  List<double>? scale,
  String blendMode = 'Normal',
  double opacity = 1.0,
  int? maskSrc,
  double tint_r = 1.0,
  double tint_g = 1.0,
  double tint_b = 1.0,
  double screenTint_r = 0.0,
  double screenTint_g = 0.0,
  double screenTint_b = 0.0,
  List<Map<String, dynamic>>? children,
}) {
  final node = <String, dynamic>{
    'uuid': uuid,
    'name': name,
    'type': 'Part',
    'enabled': enabled,
    'zsort': zsort,
    'lockToRoot': false,
    'transform': {
      'trans': translation ?? [0.0, 0.0, 0.0],
      'rot': rotation ?? [0.0, 0.0, 0.0],
      'scale': scale ?? [1.0, 1.0],
    },
    'mesh': mesh,
    'blend_mode': blendMode,
    'opacity': opacity,
    'tint': [tint_r, tint_g, tint_b],
    'screen_tint': [screenTint_r, screenTint_g, screenTint_b],
  };

  if (textureId != null) {
    node['textures'] = [textureId];
  }

  if (maskSrc != null) {
    node['mask_threshold'] = 0.5;
    node['masks'] = [
      {'source': maskSrc, 'mode': 'Mask'}
    ];
  }

  if (children != null && children.isNotEmpty) {
    node['children'] = children;
  }

  return node;
}

/// Helper to create a composite node.
///
/// Always emits `transform` and `lockToRoot` for inox2d compatibility.
Map<String, dynamic> createCompositeNode({
  required int uuid,
  required String name,
  bool enabled = true,
  double zsort = 0.0,
  String blendMode = 'Normal',
  double opacity = 1.0,
  List<double>? translation,
  List<Map<String, dynamic>>? children,
}) {
  final node = <String, dynamic>{
    'uuid': uuid,
    'name': name,
    'type': 'Composite',
    'enabled': enabled,
    'zsort': zsort,
    'lockToRoot': false,
    'transform': {
      'trans': translation ?? [0.0, 0.0, 0.0],
      'rot': [0.0, 0.0, 0.0],
      'scale': [1.0, 1.0],
    },
    'blend_mode': blendMode,
    'opacity': opacity,
  };

  if (children != null && children.isNotEmpty) {
    node['children'] = children;
  }

  return node;
}

/// Helper to create a simple physics node.
///
/// Emits keys for both kokoro2d and inox2d parsers:
/// - kokoro2d: `model`, `map_mode` (lowercase), `local_gravity`, `damping_ratio`, `angle_damping_ratio`
/// - inox2d: `model_type`, `map_mode` (PascalCase), `param`, `gravity`, `angle_damping`, `length_damping`
Map<String, dynamic> createPhysicsNode({
  required int uuid,
  required String name,
  bool enabled = true,
  String model = 'spring_pendulum',
  String mapMode = 'xy_projection',
  String? mapParamId,
  List<double>? localGravity,
  double length = 100.0,
  double frequency = 1.0,
  double angleFrequency = 1.0,
  double dampingRatio = 0.5,
  double angleDampingRatio = 0.5,
  double outputScale = 1.0,
  List<Map<String, dynamic>>? children,
}) {
  // Convert model name between formats
  final inox2dModelType = model == 'spring_pendulum' ? 'SpringPendulum' : 'Pendulum';
  final inox2dMapMode = mapMode == 'xy_projection' ? 'XY' : 'AngleLength';

  final node = <String, dynamic>{
    'uuid': uuid,
    'name': name,
    'type': 'SimplePhysics',
    'enabled': enabled,
    'zsort': 0.0,
    'lockToRoot': false,
    'transform': {
      'trans': [0.0, 0.0, 0.0],
      'rot': [0.0, 0.0, 0.0],
      'scale': [1.0, 1.0],
    },
    // kokoro2d keys
    'model': model,
    'map_param_id': mapParamId,
    'local_gravity': localGravity,
    'damping_ratio': dampingRatio,
    'angle_damping_ratio': angleDampingRatio,
    'angle_frequency': angleFrequency,
    // inox2d keys
    'model_type': inox2dModelType,
    'map_mode': inox2dMapMode,
    'param': mapParamId != null ? int.tryParse(mapParamId!) ?? 0 : 0,
    'gravity': localGravity != null ? localGravity[1] : 9.8,
    'angle_damping': angleDampingRatio,
    'length_damping': dampingRatio,
    'local_only': false,
    // shared keys
    'length': length,
    'frequency': frequency,
    'output_scale': [outputScale, 1.0],
  };

  if (children != null && children.isNotEmpty) {
    node['children'] = children;
  }

  return node;
}

/// Helper to create a parameter
Map<String, dynamic> createParam({
  required String name,
  required int uuid,
  bool isTwoD = false,
  double min = 0.0,
  double max = 1.0,
  double defaultValue = 0.0,
  List<List<double>>? axisPoints,
  List<Map<String, dynamic>>? bindings,
}) {
  // Always emit min/max/defaults as [x, y] for inox2d compatibility
  // (inox2d's get_vec2 requires 2-element arrays)
  final param = <String, dynamic>{
    'name': name,
    'uuid': uuid,
    'is_vec2': isTwoD,
    'min': [min, isTwoD ? min : 0.0],
    'max': [max, isTwoD ? max : 0.0],
    'defaults': [defaultValue, isTwoD ? defaultValue : 0.0],
  };

  if (axisPoints != null) {
    // Ensure Y axis points always present (inox2d requires both X and Y)
    if (axisPoints.length < 2) {
      param['axis_points'] = [axisPoints[0], [0.0]];
    } else {
      param['axis_points'] = axisPoints;
    }
  } else {
    param['axis_points'] = [[0.0, 1.0], [0.0]];
  }

  if (bindings != null && bindings.isNotEmpty) {
    param['bindings'] = bindings;
  } else {
    param['bindings'] = <Map<String, dynamic>>[];
  }

  return param;
}

/// Helper to create a parameter binding.
///
/// [values] must be a nested list matching the format expected by
/// `BindingValues.fromJson`: each element is a row (List) in the
/// interpolation grid. For 1D params: `[[val0], [val1], ...]`.
///
/// Automatically generates `isSet` matrix (all true) and `interpolate_mode`
/// for inox2d compatibility.
Map<String, dynamic> createBinding({
  required int node,
  required String paramName,
  required List<List<dynamic>> values,
  String interpolateMode = 'Linear',
}) {
  // Generate isSet: matrix of bools matching values dimensions, all true
  final isSet = values.map((row) {
    if (row is List && row.isNotEmpty && row[0] is List) {
      return (row as List).map((_) => true).toList();
    }
    return row.map((_) => true).toList();
  }).toList();

  return {
    'node': node,
    'param_name': paramName,
    'values': values,
    'isSet': isSet,
    'interpolate_mode': interpolateMode,
  };
}
