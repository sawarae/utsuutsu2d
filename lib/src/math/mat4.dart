import 'dart:math' as math;
import 'dart:typed_data';
import 'vec2.dart';
import 'vec3.dart';

/// 4x4 Matrix class (column-major order)
class Mat4 {
  final Float64List _data;

  Mat4._(this._data);

  factory Mat4.identity() {
    return Mat4._(Float64List.fromList([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]));
  }

  factory Mat4.zero() {
    return Mat4._(Float64List(16));
  }

  factory Mat4.fromList(List<double> values) {
    assert(values.length == 16);
    return Mat4._(Float64List.fromList(values));
  }

  double operator [](int index) => _data[index];
  void operator []=(int index, double value) => _data[index] = value;

  /// Get element at row r, column c (0-indexed)
  double at(int r, int c) => _data[c * 4 + r];

  /// Set element at row r, column c
  void setAt(int r, int c, double value) => _data[c * 4 + r] = value;

  /// Matrix multiplication
  Mat4 operator *(Mat4 other) {
    final result = Mat4.zero();
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 4; r++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += at(r, k) * other.at(k, c);
        }
        result.setAt(r, c, sum);
      }
    }
    return result;
  }

  /// Transform a 3D point
  Vec3 transformPoint(Vec3 point) {
    final w = at(3, 0) * point.x + at(3, 1) * point.y + at(3, 2) * point.z + at(3, 3);
    return Vec3(
      (at(0, 0) * point.x + at(0, 1) * point.y + at(0, 2) * point.z + at(0, 3)) / w,
      (at(1, 0) * point.x + at(1, 1) * point.y + at(1, 2) * point.z + at(1, 3)) / w,
      (at(2, 0) * point.x + at(2, 1) * point.y + at(2, 2) * point.z + at(2, 3)) / w,
    );
  }

  /// Transform a 2D point (z=0, returns x,y)
  Vec2 transformPoint2D(Vec2 point) {
    final result = transformPoint(Vec3(point.x, point.y, 0));
    return Vec2(result.x, result.y);
  }

  /// Create translation matrix
  static Mat4 translation(Vec3 t) {
    return Mat4.fromList([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      t.x, t.y, t.z, 1,
    ]);
  }

  /// Create scale matrix
  static Mat4 scale(Vec3 s) {
    return Mat4.fromList([
      s.x, 0, 0, 0,
      0, s.y, 0, 0,
      0, 0, s.z, 0,
      0, 0, 0, 1,
    ]);
  }

  /// Create rotation matrix from Euler angles (XYZ order)
  static Mat4 rotationEuler(Vec3 angles) {
    final cx = math.cos(angles.x);
    final sx = math.sin(angles.x);
    final cy = math.cos(angles.y);
    final sy = math.sin(angles.y);
    final cz = math.cos(angles.z);
    final sz = math.sin(angles.z);

    // XYZ rotation order
    return Mat4.fromList([
      cy * cz, cx * sz + sx * sy * cz, sx * sz - cx * sy * cz, 0,
      -cy * sz, cx * cz - sx * sy * sz, sx * cz + cx * sy * sz, 0,
      sy, -sx * cy, cx * cy, 0,
      0, 0, 0, 1,
    ]);
  }

  /// Create rotation matrix around Z axis
  static Mat4 rotationZ(double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Mat4.fromList([
      c, s, 0, 0,
      -s, c, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
  }

  /// Get translation component
  Vec3 get translationVec => Vec3(_data[12], _data[13], _data[14]);

  /// Copy this matrix
  Mat4 clone() => Mat4._(Float64List.fromList(_data));

  Float64List get storage => _data;

  @override
  String toString() {
    final sb = StringBuffer('Mat4(\n');
    for (int r = 0; r < 4; r++) {
      sb.write('  ');
      for (int c = 0; c < 4; c++) {
        sb.write('${at(r, c).toStringAsFixed(4)} ');
      }
      sb.write('\n');
    }
    sb.write(')');
    return sb.toString();
  }
}
