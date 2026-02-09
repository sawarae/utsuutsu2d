import 'vec2.dart';
import 'vec3.dart';
import 'mat4.dart';

/// Transform offset for nodes (relative transform)
class TransformOffset {
  Vec3 translation;
  Vec3 rotation;
  Vec2 scale;
  bool pixelSnap;

  TransformOffset({
    Vec3? translation,
    Vec3? rotation,
    Vec2? scale,
    this.pixelSnap = false,
  })  : translation = translation ?? const Vec3.zero(),
        rotation = rotation ?? const Vec3.zero(),
        scale = scale ?? const Vec2.one();

  /// Convert to transformation matrix (TRS order)
  Mat4 toMatrix() {
    // Translation
    final t = Mat4.translation(translation);

    // Rotation (Euler XYZ)
    final r = Mat4.rotationEuler(rotation);

    // Scale (2D with Z=1)
    final s = Mat4.scale(Vec3(scale.x, scale.y, 1.0));

    return t * r * s;
  }

  TransformOffset clone() {
    return TransformOffset(
      translation: Vec3(translation.x, translation.y, translation.z),
      rotation: Vec3(rotation.x, rotation.y, rotation.z),
      scale: Vec2(scale.x, scale.y),
      pixelSnap: pixelSnap,
    );
  }

  @override
  String toString() {
    return 'TransformOffset(t: $translation, r: $rotation, s: $scale, snap: $pixelSnap)';
  }
}

/// Transform storage for nodes (relative and absolute transforms)
class TransformStore {
  TransformOffset relative;
  Mat4 absolute;

  TransformStore()
      : relative = TransformOffset(),
        absolute = Mat4.identity();

  void reset(TransformOffset offset) {
    relative = offset.clone();
    absolute = Mat4.identity();
  }

  TransformStore clone() {
    final store = TransformStore();
    store.relative = relative.clone();
    store.absolute = absolute.clone();
    return store;
  }
}
