import '../math/math.dart';
import '../core/node.dart';
import '../core/puppet.dart';
import 'param.dart';

/// Parameter context for managing parameter state
class ParamCtx {
  final List<Param> params;
  final Map<String, Vec2> _values = {};
  final Map<String, String> _nameToId = {};
  final Set<String> _appliedThisFrame = {};

  ParamCtx(this.params) {
    // Initialize with default values
    for (final param in params) {
      _values[param.id] = param.defaultValue;
      _nameToId[param.name] = param.id;
    }
  }

  /// Set parameter value by ID
  void setValue(String paramId, Vec2 value) {
    _values[paramId] = value;
  }

  /// Get parameter value by ID
  Vec2? getValue(String paramId) => _values[paramId];

  /// Set parameter value by name
  void setValueByName(String name, Vec2 value) {
    final id = _nameToId[name];
    if (id != null) {
      _values[id] = value;
    }
  }

  /// Get parameter value by name
  Vec2? getValueByName(String name) {
    final id = _nameToId[name];
    return id != null ? _values[id] : null;
  }

  /// Reset for new frame
  void beginFrame() {
    _appliedThisFrame.clear();
  }

  /// Apply all parameters to the puppet
  void apply(
    PuppetNodeTree nodes,
    TransformCtx? transformCtx,
    ZSortCtx? zsortCtx,
  ) {
    beginFrame();

    for (final param in params) {
      if (_appliedThisFrame.contains(param.id)) continue;
      _appliedThisFrame.add(param.id);

      final value = _values[param.id] ?? param.defaultValue;
      _applyParam(param, value, nodes, transformCtx, zsortCtx);
    }
  }

  void _applyParam(
    Param param,
    Vec2 value,
    PuppetNodeTree nodes,
    TransformCtx? transformCtx,
    ZSortCtx? zsortCtx,
  ) {
    // reference-compatible: clamp to min/max before normalization
    final clamped = Vec2(
      value.x.clamp(param.minValue.x, param.maxValue.x),
      value.y.clamp(param.minValue.y, param.maxValue.y),
    );
    final normalized = param.normalize(clamped);

    // Find interpolation indices
    final (xLow, xHigh, xT) =
        param.findInterpIndices(normalized.x, param.axisPointsX);
    final (yLow, yHigh, yT) =
        param.findInterpIndices(normalized.y, param.axisPointsY);

    for (final binding in param.bindings) {
      _applyBinding(
        param.id,
        binding,
        xLow,
        xHigh,
        xT,
        yLow,
        yHigh,
        yT,
        nodes,
        transformCtx,
        zsortCtx,
      );
    }
  }

  void _applyBinding(
    String paramId,
    Binding binding,
    int xLow,
    int xHigh,
    double xT,
    int yLow,
    int yHigh,
    double yT,
    PuppetNodeTree nodes,
    TransformCtx? transformCtx,
    ZSortCtx? zsortCtx,
  ) {
    final values = binding.values;
    final type = values.type;

    // Get the four corner values for bilinear interpolation
    final topLeft = values.getValue(xLow, yLow);
    final topRight = values.getValue(xHigh, yLow);
    final bottomLeft = values.getValue(xLow, yHigh);
    final bottomRight = values.getValue(xHigh, yHigh);

    if (topLeft == null) return;

    // Apply based on binding type
    switch (type) {
      case BindingValueType.transformTX:
      case BindingValueType.transformTY:
      case BindingValueType.transformSX:
      case BindingValueType.transformSY:
      case BindingValueType.transformRX:
      case BindingValueType.transformRY:
      case BindingValueType.transformRZ:
        _applyTransformBinding(
          binding.nodeId,
          type,
          _bilinearInterpolate(
            topLeft as num,
            topRight as num? ?? topLeft,
            bottomLeft as num? ?? topLeft,
            bottomRight as num? ?? topLeft,
            xT,
            yT,
          ),
          nodes,
          transformCtx,
        );
        break;
      case BindingValueType.zSort:
        _applyZSortBinding(
          binding.nodeId,
          _bilinearInterpolate(
            topLeft as num,
            topRight as num? ?? topLeft,
            bottomLeft as num? ?? topLeft,
            bottomRight as num? ?? topLeft,
            xT,
            yT,
          ),
          zsortCtx,
        );
        break;
      case BindingValueType.deform:
        _applyDeformBinding(
          binding.nodeId,
          paramId,
          topLeft,
          topRight ?? topLeft,
          bottomLeft ?? topLeft,
          bottomRight ?? topLeft,
          xT,
          yT,
          nodes,
        );
        break;
      case BindingValueType.opacity:
        _applyOpacityBinding(
          binding.nodeId,
          _bilinearInterpolate(
            topLeft as num,
            topRight as num? ?? topLeft,
            bottomLeft as num? ?? topLeft,
            bottomRight as num? ?? topLeft,
            xT,
            yT,
          ),
          nodes,
        );
        break;
    }
  }

  double _bilinearInterpolate(
    num topLeft,
    num topRight,
    num bottomLeft,
    num bottomRight,
    double xT,
    double yT,
  ) {
    // Safety: clamp t values to [0, 1]
    xT = xT.clamp(0.0, 1.0);
    yT = yT.clamp(0.0, 1.0);

    // Bilinear interpolation following inox2d reference implementation:
    // 1. First interpolate along Y axis (left and right columns)
    // 2. Then interpolate along X axis (between the two interpolated values)
    // This matches: p0 = p00.lerp(p01, offset.y); p1 = p10.lerp(p11, offset.y); return p0.lerp(p1, offset.x);
    final left = topLeft + (bottomLeft - topLeft) * yT;
    final right = topRight + (bottomRight - topRight) * yT;
    return left + (right - left) * xT;
  }

  void _applyTransformBinding(
    PuppetNodeUuid nodeId,
    BindingValueType type,
    double value,
    PuppetNodeTree nodes,
    TransformCtx? transformCtx,
  ) {
    if (transformCtx == null) return;

    final store = transformCtx.getStore(nodeId);
    if (store == null) return;

    // Accumulate directly into store.relative (already reset to base offset in beginFrame)
    switch (type) {
      case BindingValueType.transformTX:
        store.relative.translation = Vec3(
          store.relative.translation.x + value,
          store.relative.translation.y,
          store.relative.translation.z,
        );
        break;
      case BindingValueType.transformTY:
        store.relative.translation = Vec3(
          store.relative.translation.x,
          store.relative.translation.y + value,
          store.relative.translation.z,
        );
        break;
      case BindingValueType.transformSX:
        store.relative.scale = Vec2(
          store.relative.scale.x * value,
          store.relative.scale.y,
        );
        break;
      case BindingValueType.transformSY:
        store.relative.scale = Vec2(
          store.relative.scale.x,
          store.relative.scale.y * value,
        );
        break;
      case BindingValueType.transformRX:
        store.relative.rotation = Vec3(
          store.relative.rotation.x + value,
          store.relative.rotation.y,
          store.relative.rotation.z,
        );
        break;
      case BindingValueType.transformRY:
        store.relative.rotation = Vec3(
          store.relative.rotation.x,
          store.relative.rotation.y + value,
          store.relative.rotation.z,
        );
        break;
      case BindingValueType.transformRZ:
        store.relative.rotation = Vec3(
          store.relative.rotation.x,
          store.relative.rotation.y,
          store.relative.rotation.z + value,
        );
        break;
      default:
        break;
    }
  }

  void _applyZSortBinding(
    PuppetNodeUuid nodeId,
    double value,
    ZSortCtx? zsortCtx,
  ) {
    if (zsortCtx == null) return;
    final current = zsortCtx.getZSort(nodeId) ?? 0;
    zsortCtx.setZSort(nodeId, current + value);
  }

  void _applyOpacityBinding(
    PuppetNodeUuid nodeId,
    double value,
    PuppetNodeTree nodes,
  ) {
    final node = nodes.getNode(nodeId)?.data;
    if (node == null) return;

    final drawable = node.components?.drawable;
    if (drawable == null) return;

    drawable.opacity = value.clamp(0.0, 1.0);
  }

  void _applyDeformBinding(
    PuppetNodeUuid nodeId,
    String paramId,
    dynamic topLeft,
    dynamic topRight,
    dynamic bottomLeft,
    dynamic bottomRight,
    double xT,
    double yT,
    PuppetNodeTree nodes,
  ) {
    final node = nodes.getNode(nodeId)?.data;
    if (node == null) return;

    final components = node.components;
    if (components == null || components.deformStack == null) return;

    // Parse deform data (list of Vec2 displacements)
    final tl = _parseDeformData(topLeft);
    final tr = _parseDeformData(topRight);
    final bl = _parseDeformData(bottomLeft);
    final br = _parseDeformData(bottomRight);

    if (tl == null) return;

    final vertexCount = tl.length;
    final result = List<Vec2>.generate(vertexCount, (_) => const Vec2.zero());

    // Bilinear interpolate each vertex displacement
    // Following inox2d reference: interpolate Y first, then X
    for (int i = 0; i < vertexCount; i++) {
      final tlV = tl[i];
      final trV = i < (tr?.length ?? 0) ? tr![i] : tlV;
      final blV = i < (bl?.length ?? 0) ? bl![i] : tlV;
      final brV = i < (br?.length ?? 0) ? br![i] : tlV;

      final left = tlV.lerp(blV, yT);
      final right = trV.lerp(brV, yT);
      result[i] = left.lerp(right, xT);
    }

    components.deformStack!.setDeform(
      ParamDeformSource(paramId),
      result,
    );
  }

  List<Vec2>? _parseDeformData(dynamic data) {
    if (data == null) return null;
    if (data is! List) return null;
    if (data.isEmpty) return null;

    final result = <Vec2>[];

    // Check if data is nested list format [[x1,y1], [x2,y2], ...] or flat [x1,y1,x2,y2,...]
    if (data[0] is List) {
      // Nested format: [[x, y], [x, y], ...]
      for (final item in data) {
        if (item is List && item.length >= 2) {
          result.add(Vec2(
            (item[0] as num).toDouble(),
            (item[1] as num).toDouble(),
          ));
        }
      }
    } else {
      // Flat format: [x1, y1, x2, y2, ...]
      for (int i = 0; i < data.length; i += 2) {
        if (i + 1 < data.length) {
          result.add(Vec2(
            (data[i] as num).toDouble(),
            (data[i + 1] as num).toDouble(),
          ));
        }
      }
    }
    return result;
  }
}
