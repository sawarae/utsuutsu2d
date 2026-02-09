import '../math/math.dart';

/// Mesh data structure
class Mesh {
  /// Original vertex positions
  final List<Vec2> vertices;

  /// UV coordinates for texturing
  final List<Vec2> uvs;

  /// Triangle indices
  final List<int> indices;

  /// Origin point for transformations
  final Vec2 origin;

  Mesh({
    required this.vertices,
    required this.uvs,
    required this.indices,
    this.origin = const Vec2.zero(),
  });

  /// Number of vertices
  int get vertexCount => vertices.length;

  /// Number of triangles
  int get triangleCount => indices.length ~/ 3;

  Map<String, dynamic> toJson() {
    // Flatten vertices to [x, y, x, y, ...] format
    final verts = <double>[];
    for (final v in vertices) {
      verts.add(v.x);
      verts.add(v.y);
    }

    // Flatten UVs to [u, v, u, v, ...] format
    final uvsFlat = <double>[];
    for (final uv in uvs) {
      uvsFlat.add(uv.x);
      uvsFlat.add(uv.y);
    }

    final json = <String, dynamic>{
      'verts': verts,
      'uvs': uvsFlat,
      'indices': indices,
    };

    if (origin != const Vec2.zero()) {
      json['origin'] = [origin.x, origin.y];
    }

    return json;
  }

  factory Mesh.fromJson(Map<String, dynamic> json) {
    // Inochi2D uses 'verts' but we also support 'vertices' for compatibility
    final verticesRaw = json['verts'] as List? ?? json['vertices'] as List? ?? [];
    final uvsRaw = json['uvs'] as List? ?? [];
    final indicesRaw = json['indices'] as List? ?? [];

    // Parse vertices (x, y pairs)
    final vertices = <Vec2>[];
    for (int i = 0; i < verticesRaw.length; i += 2) {
      vertices.add(Vec2(
        (verticesRaw[i] as num).toDouble(),
        (verticesRaw[i + 1] as num).toDouble(),
      ));
    }

    // Parse UVs (u, v pairs)
    final uvs = <Vec2>[];
    for (int i = 0; i < uvsRaw.length; i += 2) {
      uvs.add(Vec2(
        (uvsRaw[i] as num).toDouble(),
        (uvsRaw[i + 1] as num).toDouble(),
      ));
    }

    // Parse indices
    final indices = indicesRaw.map((i) => (i as num).toInt()).toList();

    // Parse origin
    Vec2 origin = const Vec2.zero();
    if (json['origin'] != null) {
      final originRaw = json['origin'] as List;
      origin = Vec2(
        (originRaw[0] as num).toDouble(),
        (originRaw[1] as num).toDouble(),
      );
    }

    return Mesh(
      vertices: vertices,
      uvs: uvs,
      indices: indices,
      origin: origin,
    );
  }
}

/// Textured mesh with texture references
class TexturedMesh {
  /// Albedo (color) texture ID
  final int? albedoTextureId;

  /// Emissive texture ID
  final int? emissiveTextureId;

  /// Bump map texture ID
  final int? bumpTextureId;

  TexturedMesh({
    this.albedoTextureId,
    this.emissiveTextureId,
    this.bumpTextureId,
  });

  factory TexturedMesh.fromJson(Map<String, dynamic> json) {
    return TexturedMesh(
      albedoTextureId: json['albedo_texture'],
      emissiveTextureId: json['emissive_texture'],
      bumpTextureId: json['bump_texture'],
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (albedoTextureId != null) json['albedo_texture'] = albedoTextureId;
    if (emissiveTextureId != null) json['emissive_texture'] = emissiveTextureId;
    if (bumpTextureId != null) json['bump_texture'] = bumpTextureId;
    return json;
  }
}
