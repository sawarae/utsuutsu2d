import '../core/node.dart';

/// Composite node that renders all children
class Composite {
  /// Whether to sort children by z-order
  bool sortByZOrder;

  /// Cached sorted children (updated each frame)
  List<PuppetNodeUuid> sortedChildren;

  Composite({
    this.sortByZOrder = true,
    List<PuppetNodeUuid>? sortedChildren,
  }) : sortedChildren = sortedChildren ?? [];

  factory Composite.fromJson(Map<String, dynamic> json) {
    return Composite(
      sortByZOrder: json['sort_by_z_order'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sort_by_z_order': sortByZOrder,
    };
  }
}
