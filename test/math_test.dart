import 'package:flutter_test/flutter_test.dart';
import 'package:utsutsu2d/utsutsu2d.dart';

void main() {
  group('Vec2', () {
    test('basic operations', () {
      const a = Vec2(1, 2);
      const b = Vec2(3, 4);

      expect(a + b, const Vec2(4, 6));
      expect(a - b, const Vec2(-2, -2));
      expect(a * 2, const Vec2(2, 4));
      expect(a.dot(b), 11);
    });

    test('length and normalize', () {
      const v = Vec2(3, 4);
      expect(v.length, 5);

      final normalized = v.normalized;
      expect(normalized.x, closeTo(0.6, 0.001));
      expect(normalized.y, closeTo(0.8, 0.001));
    });

    test('lerp', () {
      const a = Vec2(0, 0);
      const b = Vec2(10, 10);

      final mid = a.lerp(b, 0.5);
      expect(mid, const Vec2(5, 5));
    });
  });

  group('Vec3', () {
    test('basic operations', () {
      const a = Vec3(1, 2, 3);
      const b = Vec3(4, 5, 6);

      expect(a + b, const Vec3(5, 7, 9));
      expect(a.dot(b), 32);
    });

    test('cross product', () {
      const i = Vec3(1, 0, 0);
      const j = Vec3(0, 1, 0);

      final k = i.cross(j);
      expect(k.x, 0);
      expect(k.y, 0);
      expect(k.z, 1);
    });
  });

  group('Mat4', () {
    test('identity', () {
      final identity = Mat4.identity();
      expect(identity[0], 1);
      expect(identity[5], 1);
      expect(identity[10], 1);
      expect(identity[15], 1);
    });

    test('translation', () {
      final t = Mat4.translation(const Vec3(10, 20, 30));
      final point = t.transformPoint(const Vec3(0, 0, 0));

      expect(point.x, 10);
      expect(point.y, 20);
      expect(point.z, 30);
    });

    test('scale', () {
      final s = Mat4.scale(const Vec3(2, 3, 4));
      final point = s.transformPoint(const Vec3(1, 1, 1));

      expect(point.x, 2);
      expect(point.y, 3);
      expect(point.z, 4);
    });

    test('matrix multiplication', () {
      final t = Mat4.translation(const Vec3(10, 0, 0));
      final s = Mat4.scale(const Vec3(2, 2, 2));

      // Scale first, then translate
      final combined = t * s;
      final point = combined.transformPoint(const Vec3(1, 0, 0));

      expect(point.x, 12); // 1 * 2 + 10
      expect(point.y, 0);
    });

    test('Y-axis rotation (sideways)', () {
      final rotY = Mat4.rotationEuler(const Vec3(0, 0.5, 0));
      final point = rotY.transformPoint(const Vec3(1, 0, 0));

      expect(point.x, closeTo(0.877, 0.01));
      expect(point.y, closeTo(0, 0.01));
      expect(point.z.abs(), closeTo(0.479, 0.01));
    });

    test('Combined XYZ rotation (Euler)', () {
      final rot = Mat4.rotationEuler(const Vec3(0.1, 0.3, 0.2));
      final point = rot.transformPoint(const Vec3(1, 0, 0));

      expect(point.x, isNot(1.0));
      expect(point.length, closeTo(1.0, 0.01));
    });
  });

  group('Transform', () {
    test('TransformOffset to matrix', () {
      final offset = TransformOffset(
        translation: const Vec3(10, 20, 0),
        scale: const Vec2(2, 2),
      );

      final matrix = offset.toMatrix();
      final point = matrix.transformPoint(const Vec3(1, 1, 0));

      expect(point.x, closeTo(12, 0.001));
      expect(point.y, closeTo(22, 0.001));
    });

    test('TransformOffset with Y-axis rotation', () {
      final offset = TransformOffset(
        translation: const Vec3(0, 0, 0),
        rotation: const Vec3(0, 0.5, 0),
        scale: const Vec2(1, 1),
      );

      final matrix = offset.toMatrix();
      final point = matrix.transformPoint(const Vec3(1, 0, 0));

      expect(point.x, closeTo(0.877, 0.01));
      expect(point.y, closeTo(0, 0.01));
    });
  });

  group('Interpolation', () {
    test('linear interpolation', () {
      final result = interpolateF32(
        0.5,
        const InterpRange(0, 1),
        const InterpRange(0, 100),
        InterpolateMode.linear,
      );

      expect(result, 50);
    });

    test('nearest interpolation', () {
      final result1 = interpolateF32(
        0.3,
        const InterpRange(0, 1),
        const InterpRange(0, 100),
        InterpolateMode.nearest,
      );

      final result2 = interpolateF32(
        0.7,
        const InterpRange(0, 1),
        const InterpRange(0, 100),
        InterpolateMode.nearest,
      );

      expect(result1, 0);
      expect(result2, 100);
    });

    test('bilinear interpolation', () {
      final result = biInterpolateF32(
        const Vec2(0.5, 0.5),
        const InterpRange(0, 1),
        const InterpRange(0, 1),
        0,
        100,
        0,
        100,
        InterpolateMode.linear,
      );

      expect(result, 50);
    });
  });
}
