import 'vec2.dart';
import 'vec3.dart';
import 'mat4.dart';

/// 2D Camera for viewing puppets
class Camera {
  Vec2 position;
  double zoom;
  double rotation;

  Camera({
    this.position = const Vec2.zero(),
    this.zoom = 1.0,
    this.rotation = 0.0,
  });

  /// Get view matrix
  Mat4 get viewMatrix {
    // Translate to camera position
    final t = Mat4.translation(
      Vec3(-position.x, -position.y, 0),
    );

    // Rotate around Z
    final r = Mat4.rotationZ(-rotation);

    // Scale by zoom
    final s = Mat4.scale(Vec3(zoom, zoom, 1.0));

    return s * r * t;
  }

  /// Get projection matrix for given viewport size
  Mat4 projectionMatrix(double width, double height) {
    final halfW = width / 2;
    final halfH = height / 2;

    // Orthographic projection
    return Mat4.fromList([
      1 / halfW, 0, 0, 0,
      0, -1 / halfH, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
  }

  /// Get combined view-projection matrix
  Mat4 viewProjectionMatrix(double width, double height) {
    return projectionMatrix(width, height) * viewMatrix;
  }

  /// Convert screen coordinates to world coordinates
  Vec2 screenToWorld(Vec2 screenPos, double width, double height) {
    // Normalize screen position
    final normalizedX = (screenPos.x / width - 0.5) * 2;
    final normalizedY = (screenPos.y / height - 0.5) * 2;

    // Apply inverse transforms
    final worldX = normalizedX * (width / 2) / zoom + position.x;
    final worldY = -normalizedY * (height / 2) / zoom + position.y;

    return Vec2(worldX, worldY);
  }

  /// Convert world coordinates to screen coordinates
  Vec2 worldToScreen(Vec2 worldPos, double width, double height) {
    final relX = (worldPos.x - position.x) * zoom;
    final relY = (worldPos.y - position.y) * zoom;

    final screenX = (relX / (width / 2) + 1) * width / 2;
    final screenY = (-relY / (height / 2) + 1) * height / 2;

    return Vec2(screenX, screenY);
  }
}
