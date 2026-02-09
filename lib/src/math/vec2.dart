import 'dart:math' as math;

/// A 2D vector with x and y components.
///
/// [Vec2] is an immutable value type used throughout utsutsu2d for positions,
/// directions, scales, and 2D parameter values.
///
/// ## Basic Usage
///
/// ```dart
/// // Create vectors
/// final v1 = Vec2(3.0, 4.0);
/// final v2 = Vec2.zero(); // (0, 0)
/// final v3 = Vec2.one();  // (1, 1)
///
/// // Vector math
/// final sum = v1 + Vec2(1, 2);        // (4, 6)
/// final scaled = v1 * 2;               // (6, 8)
/// final length = v1.length;            // 5.0
/// final normalized = v1.normalized;    // (0.6, 0.8)
///
/// // Dot and cross products
/// final dot = v1.dot(v2);
/// final cross = v1.cross(v2);
///
/// // Interpolation
/// final mid = v1.lerp(v2, 0.5); // Midpoint between v1 and v2
/// ```
///
/// ## Operators
///
/// Supports standard vector operations:
/// - `+` : Vector addition
/// - `-` : Vector subtraction
/// - `*` : Scalar multiplication
/// - `/` : Scalar division
/// - `-v` : Negation
///
/// See also:
/// - [Vec3] for 3D vectors
/// - [Mat4] for transformation matrices
class Vec2 {
  /// The X component.
  final double x;

  /// The Y component.
  final double y;

  /// Creates a vector with the given x and y components.
  const Vec2(this.x, this.y);

  /// Creates a zero vector (0, 0).
  const Vec2.zero() : x = 0, y = 0;

  /// Creates a unit vector (1, 1).
  const Vec2.one() : x = 1, y = 1;

  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);
  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);
  Vec2 operator *(double scalar) => Vec2(x * scalar, y * scalar);
  Vec2 operator /(double scalar) => Vec2(x / scalar, y / scalar);
  Vec2 operator -() => Vec2(-x, -y);

  /// Computes the dot product with another vector.
  ///
  /// Returns: `x * other.x + y * other.y`
  ///
  /// The dot product measures how much two vectors point in the same direction:
  /// - Result > 0: vectors point in similar directions
  /// - Result = 0: vectors are perpendicular
  /// - Result < 0: vectors point in opposite directions
  double dot(Vec2 other) => x * other.x + y * other.y;

  /// Computes the 2D cross product (Z component of 3D cross product).
  ///
  /// Returns: `x * other.y - y * other.x`
  ///
  /// Useful for determining relative orientation:
  /// - Result > 0: `other` is counter-clockwise from `this`
  /// - Result = 0: vectors are parallel
  /// - Result < 0: `other` is clockwise from `this`
  double cross(Vec2 other) => x * other.y - y * other.x;

  /// The Euclidean length (magnitude) of the vector.
  ///
  /// Calculated as `sqrt(x² + y²)`.
  double get length => math.sqrt(x * x + y * y);

  /// The squared length of the vector.
  ///
  /// Faster than [length] as it avoids the square root.
  /// Useful for length comparisons where the actual value doesn't matter.
  double get lengthSquared => x * x + y * y;

  /// Returns a unit vector in the same direction.
  ///
  /// If the vector has zero length, returns [Vec2.zero].
  ///
  /// Example:
  /// ```dart
  /// Vec2(3, 4).normalized; // Vec2(0.6, 0.8)
  /// ```
  Vec2 get normalized {
    final len = length;
    if (len == 0) return Vec2.zero();
    return this / len;
  }

  /// Linearly interpolates between this vector and another.
  ///
  /// Parameters:
  /// - [other]: The target vector
  /// - [t]: Interpolation parameter (0.0 = this vector, 1.0 = other vector)
  ///
  /// Returns a vector between `this` and `other` based on `t`.
  ///
  /// Example:
  /// ```dart
  /// final start = Vec2(0, 0);
  /// final end = Vec2(10, 10);
  /// final mid = start.lerp(end, 0.5); // Vec2(5, 5)
  /// ```
  Vec2 lerp(Vec2 other, double t) {
    return Vec2(
      x + (other.x - x) * t,
      y + (other.y - y) * t,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Vec2 && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vec2($x, $y)';

  List<double> toList() => [x, y];

  static Vec2 fromList(List<double> list) => Vec2(list[0], list[1]);
}
