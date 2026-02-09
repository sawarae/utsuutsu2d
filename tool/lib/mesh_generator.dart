/// Utilities for generating mesh geometry
class MeshGenerator {
  /// Generate a simple quad mesh
  ///
  /// Creates a rectangular mesh with 4 vertices and 2 triangles
  static Map<String, dynamic> quad(
    double width,
    double height, {
    double centerX = 0.0,
    double centerY = 0.0,
  }) {
    final halfW = width / 2;
    final halfH = height / 2;

    final verts = [
      // Top-left
      centerX - halfW, centerY - halfH,
      // Top-right
      centerX + halfW, centerY - halfH,
      // Bottom-right
      centerX + halfW, centerY + halfH,
      // Bottom-left
      centerX - halfW, centerY + halfH,
    ];

    return {
      'vertices': verts,
      'verts': verts, // inox2d compat
      'uvs': [
        0.0, 0.0, // Top-left
        1.0, 0.0, // Top-right
        1.0, 1.0, // Bottom-right
        0.0, 1.0, // Bottom-left
      ],
      'indices': [
        0, 1, 2, // First triangle
        2, 3, 0, // Second triangle
      ],
    };
  }

  /// Generate a grid mesh for deformation tests
  ///
  /// Creates a rectangular mesh subdivided into a grid of cells
  static Map<String, dynamic> grid(
    double width,
    double height,
    int cols,
    int rows, {
    double centerX = 0.0,
    double centerY = 0.0,
  }) {
    final vertices = <double>[];
    final uvs = <double>[];
    final indices = <int>[];

    final halfW = width / 2;
    final halfH = height / 2;

    // Generate vertices and UVs
    for (int row = 0; row <= rows; row++) {
      for (int col = 0; col <= cols; col++) {
        // Position (interpolate from -halfW to +halfW, -halfH to +halfH)
        final x = centerX - halfW + (col / cols) * width;
        final y = centerY - halfH + (row / rows) * height;
        vertices.add(x);
        vertices.add(y);

        // UV coordinates (0 to 1)
        final u = col / cols;
        final v = row / rows;
        uvs.add(u);
        uvs.add(v);
      }
    }

    // Generate indices for triangles
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final topLeft = row * (cols + 1) + col;
        final topRight = topLeft + 1;
        final bottomLeft = (row + 1) * (cols + 1) + col;
        final bottomRight = bottomLeft + 1;

        // First triangle (top-left, top-right, bottom-right)
        indices.add(topLeft);
        indices.add(topRight);
        indices.add(bottomRight);

        // Second triangle (bottom-right, bottom-left, top-left)
        indices.add(bottomRight);
        indices.add(bottomLeft);
        indices.add(topLeft);
      }
    }

    return {
      'vertices': vertices,
      'verts': vertices, // inox2d compat
      'uvs': uvs,
      'indices': indices,
    };
  }

  /// Generate a circle mesh
  static Map<String, dynamic> circle(
    double radius,
    int segments, {
    double centerX = 0.0,
    double centerY = 0.0,
  }) {
    final vertices = <double>[centerX, centerY]; // Center vertex
    final uvs = <double>[0.5, 0.5]; // Center UV
    final indices = <int>[];

    // Generate circle vertices
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * 3.14159265359;
      final x = centerX + radius * cos(angle);
      final y = centerY + radius * sin(angle);
      vertices.add(x);
      vertices.add(y);

      // UV coordinates
      final u = 0.5 + 0.5 * cos(angle);
      final v = 0.5 + 0.5 * sin(angle);
      uvs.add(u);
      uvs.add(v);
    }

    // Generate triangles (fan from center)
    for (int i = 1; i <= segments; i++) {
      indices.add(0); // Center
      indices.add(i);
      indices.add(i + 1);
    }

    return {
      'vertices': vertices,
      'verts': vertices, // inox2d compat
      'uvs': uvs,
      'indices': indices,
    };
  }

  /// Simple cos function (approximation)
  static double cos(double radians) {
    // Use Taylor series approximation for cos
    // cos(x) ≈ 1 - x²/2! + x⁴/4! - x⁶/6!
    final x2 = radians * radians;
    final x4 = x2 * x2;
    final x6 = x4 * x2;
    return 1 - x2 / 2 + x4 / 24 - x6 / 720;
  }

  /// Simple sin function (approximation)
  static double sin(double radians) {
    // Use Taylor series approximation for sin
    // sin(x) ≈ x - x³/3! + x⁵/5! - x⁷/7!
    final x2 = radians * radians;
    final x3 = x2 * radians;
    final x5 = x3 * x2;
    final x7 = x5 * x2;
    return radians - x3 / 6 + x5 / 120 - x7 / 5040;
  }
}
