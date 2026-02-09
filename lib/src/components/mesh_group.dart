import '../core/node.dart';

/// MeshGroup node that groups multiple child meshes for collective rendering.
///
/// Unlike Composite (which renders to an offscreen buffer), MeshGroup
/// simply groups child drawables for organizational and transform purposes.
/// All child meshes share the group's transform and blend mode settings.
class MeshGroup {
  /// Whether to sort children by z-order for rendering
  bool sortByZOrder;

  /// Cached sorted children (updated each frame)
  List<PuppetNodeUuid> sortedChildren;

  /// Opacity for the entire group (0.0 to 1.0)
  double opacity;

  MeshGroup({
    this.sortByZOrder = true,
    List<PuppetNodeUuid>? sortedChildren,
    this.opacity = 1.0,
  }) : sortedChildren = sortedChildren ?? [];

  factory MeshGroup.fromJson(Map<String, dynamic> json) {
    return MeshGroup(
      sortByZOrder: json['sort_by_z_order'] ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sort_by_z_order': sortByZOrder,
      'opacity': opacity,
    };
  }
}
