import 'vec2.dart';

/// Deformation type
abstract class Deform {
  List<Vec2> apply(List<Vec2> vertices);
}

/// Direct deformation - stores displacement vectors for each vertex
class DirectDeform implements Deform {
  final List<Vec2> displacements;

  DirectDeform(this.displacements);

  @override
  List<Vec2> apply(List<Vec2> vertices) {
    assert(displacements.length == vertices.length,
        'Deformation dimensions must match vertex count');

    return List.generate(vertices.length, (i) {
      return vertices[i] + displacements[i];
    });
  }

  static DirectDeform zero(int vertexCount) {
    return DirectDeform(List.generate(vertexCount, (_) => const Vec2.zero()));
  }
}

/// Deformation source identifier
abstract class DeformSource {}

/// Deformation from a parameter
class ParamDeformSource implements DeformSource {
  final String paramId;

  ParamDeformSource(this.paramId);

  @override
  bool operator ==(Object other) =>
      other is ParamDeformSource && other.paramId == paramId;

  @override
  int get hashCode => paramId.hashCode;
}

/// Deformation from a node
class NodeDeformSource implements DeformSource {
  final int nodeId;

  NodeDeformSource(this.nodeId);

  @override
  bool operator ==(Object other) =>
      other is NodeDeformSource && other.nodeId == nodeId;

  @override
  int get hashCode => nodeId.hashCode;
}

/// Stack of deformations to be combined
class DeformStack {
  final Map<DeformSource, List<Vec2>> _deforms = {};
  final int vertexCount;

  DeformStack(this.vertexCount);

  /// Add or update deformation for a source
  void setDeform(DeformSource source, List<Vec2> deformation) {
    assert(deformation.length == vertexCount,
        'Deformation must match vertex count');
    _deforms[source] = deformation;
  }

  /// Remove deformation from a source
  void removeDeform(DeformSource source) {
    _deforms.remove(source);
  }

  /// Clear all deformations
  void clear() {
    _deforms.clear();
  }

  /// Combine all deformations linearly
  List<Vec2> combine() {
    final result = List<Vec2>.generate(vertexCount, (_) => const Vec2.zero());

    for (final deform in _deforms.values) {
      for (int i = 0; i < vertexCount; i++) {
        result[i] = result[i] + deform[i];
      }
    }

    return result;
  }

  /// Apply combined deformations to vertices
  List<Vec2> applyTo(List<Vec2> vertices) {
    assert(vertices.length == vertexCount);
    final combined = combine();

    return List.generate(vertexCount, (i) {
      return vertices[i] + combined[i];
    });
  }
}
