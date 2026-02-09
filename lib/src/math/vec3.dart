import 'dart:math' as math;

/// A 3D vector with x, y, and z components.
///
/// [Vec3] is used for 3D positions, rotations, scales, and transformations
/// in the puppet system.
///
/// ## Basic Usage
///
/// ```dart
/// // Create vectors
/// final v1 = Vec3(1.0, 2.0, 3.0);
/// final v2 = Vec3.zero(); // (0, 0, 0)
/// final v3 = Vec3.one();  // (1, 1, 1)
///
/// // Vector math
/// final sum = v1 + Vec3(1, 1, 1);     // (2, 3, 4)
/// final scaled = v1 * 2;               // (2, 4, 6)
/// final length = v1.length;            // ~3.74
/// final normalized = v1.normalized;
///
/// // Dot and cross products
/// final dot = v1.dot(v2);
/// final cross = v1.cross(v2); // Returns perpendicular vector
/// ```
///
/// ## Common Uses in utsutsu2d
///
/// - **Translation**: Node position offsets
/// - **Rotation**: Euler angles (roll, pitch, yaw)
/// - **Scale**: Non-uniform scaling per axis
///
/// See also:
/// - [Vec2] for 2D vectors
/// - [Mat4] for transformation matrices
/// - [Transform] for complete node transformations
class Vec3 {
  /// The X component.
  final double x;

  /// The Y component.
  final double y;

  /// The Z component.
  final double z;

  /// Creates a vector with the given x, y, and z components.
  const Vec3(this.x, this.y, this.z);

  /// Creates a zero vector (0, 0, 0).
  const Vec3.zero() : x = 0, y = 0, z = 0;

  /// Creates a unit vector (1, 1, 1).
  const Vec3.one() : x = 1, y = 1, z = 1;

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);
  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);
  Vec3 operator *(double scalar) => Vec3(x * scalar, y * scalar, z * scalar);
  Vec3 operator /(double scalar) => Vec3(x / scalar, y / scalar, z / scalar);
  Vec3 operator -() => Vec3(-x, -y, -z);

  /// Computes the dot product with another vector.
  ///
  /// Returns: `x * other.x + y * other.y + z * other.z`
  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  /// Computes the cross product with another vector.
  ///
  /// Returns a vector perpendicular to both input vectors.
  /// The magnitude equals the area of the parallelogram formed by the vectors.
  ///
  /// Order matters: `a.cross(b)` points in the opposite direction from `b.cross(a)`.
  Vec3 cross(Vec3 other) => Vec3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  double get length => math.sqrt(x * x + y * y + z * z);
  double get lengthSquared => x * x + y * y + z * z;

  Vec3 get normalized {
    final len = length;
    if (len == 0) return Vec3.zero();
    return this / len;
  }

  Vec3 lerp(Vec3 other, double t) {
    return Vec3(
      x + (other.x - x) * t,
      y + (other.y - y) * t,
      z + (other.z - z) * t,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Vec3 && other.x == x && other.y == y && other.z == z;
  }

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vec3($x, $y, $z)';

  List<double> toList() => [x, y, z];

  static Vec3 fromList(List<double> list) => Vec3(list[0], list[1], list[2]);
}
