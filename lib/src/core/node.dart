import '../math/math.dart';
import '../components/components.dart';

/// Unique identifier for nodes
typedef PuppetNodeUuid = int;

/// Base node in the puppet hierarchy
class PuppetNode {
  final PuppetNodeUuid uuid;
  String name;
  bool enabled;
  double zsort;
  TransformOffset transOffset;
  bool lockToRoot;

  /// Optional components attached to this node
  NodeComponents? components;

  PuppetNode({
    required this.uuid,
    required this.name,
    this.enabled = true,
    this.zsort = 0.0,
    TransformOffset? transOffset,
    this.lockToRoot = false,
    this.components,
  }) : transOffset = transOffset ?? TransformOffset();

  /// Determine the node type string from its components.
  String get type {
    if (components == null) return 'node';
    if (components!.isDrawable) return 'part';
    if (components!.isComposite) return 'composite';
    if (components!.isMeshGroup) return 'meshgroup';
    if (components!.hasPhysics) return 'simple_physics';
    if (components!.isPathDeform) return 'pathdeformer';
    return 'node';
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'uuid': uuid,
      'name': name,
      'type': type,
      'enabled': enabled,
      'zsort': zsort,
      'lock_to_root': lockToRoot,
      'transform': {
        'trans': transOffset.translation.toList(),
        'rot': transOffset.rotation.toList(),
        'scale': transOffset.scale.toList(),
        'pixel_snap': transOffset.pixelSnap,
      },
    };

    // Serialize component-specific fields
    if (components != null) {
      if (components!.isDrawable) {
        json.addAll(components!.drawable!.toJson());
        if (components!.mesh != null) {
          json['mesh'] = components!.mesh!.toJson();
        }
        if (components!.texturedMesh?.albedoTextureId != null) {
          json['textures'] = [components!.texturedMesh!.albedoTextureId];
        }
      } else if (components!.isComposite) {
        json.addAll(components!.composite!.toJson());
      } else if (components!.isMeshGroup) {
        json.addAll(components!.meshGroup!.toJson());
      } else if (components!.hasPhysics) {
        json.addAll(components!.simplePhysics!.toJson());
      } else if (components!.isPathDeform) {
        json.addAll(components!.pathDeform!.toJson());
      }
    }

    return json;
  }

  @override
  String toString() => 'PuppetNode(uuid: $uuid, name: $name)';
}

/// Tree node wrapper for PuppetNode
class TreeNode<T> {
  final T data;
  final List<TreeNode<T>> children;
  TreeNode<T>? parent;

  TreeNode(this.data, [List<TreeNode<T>>? children])
      : children = children ?? [];

  void addChild(TreeNode<T> child) {
    child.parent = this;
    children.add(child);
  }

  void removeChild(TreeNode<T> child) {
    child.parent = null;
    children.remove(child);
  }

  /// Pre-order traversal iterator
  Iterable<TreeNode<T>> preOrder() sync* {
    yield this;
    for (final child in children) {
      yield* child.preOrder();
    }
  }

  /// Post-order traversal iterator
  Iterable<TreeNode<T>> postOrder() sync* {
    for (final child in children) {
      yield* child.postOrder();
    }
    yield this;
  }
}

/// Node tree structure
class PuppetNodeTree {
  final TreeNode<PuppetNode> root;
  final Map<PuppetNodeUuid, TreeNode<PuppetNode>> _nodeMap = {};

  PuppetNodeTree._(this.root) {
    _nodeMap[root.data.uuid] = root;
  }

  factory PuppetNodeTree.withRoot(PuppetNode rootNode) {
    final tree = PuppetNodeTree._(TreeNode(rootNode));
    return tree;
  }

  /// Get node by UUID
  TreeNode<PuppetNode>? getNode(PuppetNodeUuid uuid) => _nodeMap[uuid];

  /// Add child node under parent
  void addNode(PuppetNode node, PuppetNodeUuid parentUuid) {
    if (_nodeMap.containsKey(node.uuid)) {
      throw ArgumentError('Duplicate UUID: ${node.uuid}');
    }

    final parent = _nodeMap[parentUuid];
    if (parent == null) {
      throw ArgumentError('Parent node not found: $parentUuid');
    }

    final treeNode = TreeNode(node);
    parent.addChild(treeNode);
    _nodeMap[node.uuid] = treeNode;
  }

  /// Get all nodes (unordered)
  Iterable<PuppetNode> get nodes => _nodeMap.values.map((n) => n.data);

  /// Pre-order iteration
  Iterable<TreeNode<PuppetNode>> preOrder() => root.preOrder();

  /// Get parent of a node
  TreeNode<PuppetNode>? getParent(PuppetNodeUuid uuid) {
    return _nodeMap[uuid]?.parent;
  }

  /// Get children of a node
  List<TreeNode<PuppetNode>> getChildren(PuppetNodeUuid uuid) {
    return _nodeMap[uuid]?.children ?? [];
  }

  /// Count of nodes
  int get nodeCount => _nodeMap.length;

  /// Iterate over all nodes with callback
  void iterateAll(void Function(PuppetNode node) callback) {
    for (final node in nodes) {
      callback(node);
    }
  }

  /// Serialize the node tree to JSON.
  Map<String, dynamic> toJson() {
    return {
      'root': root.data.toJson(),
      'children': _childrenToJson(root),
    };
  }

  static List<Map<String, dynamic>> _childrenToJson(TreeNode<PuppetNode> treeNode) {
    return treeNode.children.map((child) {
      final json = child.data.toJson();
      if (child.children.isNotEmpty) {
        json['children'] = _childrenToJson(child);
      }
      return json;
    }).toList();
  }
}
