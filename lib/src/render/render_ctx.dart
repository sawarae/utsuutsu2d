import 'dart:ui' as ui;
import '../core/core.dart';
import '../components/components.dart';
import '../math/math.dart';
import 'texture_atlas.dart';

/// Drawable kind for rendering
enum DrawableKind {
  texturedMesh,
  composite,
  meshGroup,
}

/// Render data for a drawable node
class RenderData {
  final PuppetNodeUuid nodeId;
  final DrawableKind kind;
  final Mat4 transform;
  final Drawable drawable;
  final Mesh? mesh;
  final TexturedMesh? texturedMesh;
  final Composite? composite;
  final MeshGroup? meshGroup;
  final List<Vec2>? deformedVertices;

  RenderData({
    required this.nodeId,
    required this.kind,
    required this.transform,
    required this.drawable,
    this.mesh,
    this.texturedMesh,
    this.composite,
    this.meshGroup,
    this.deformedVertices,
  });
}

/// Render context for managing rendering state
class RenderCtx {
  final List<RenderData> _drawables = [];
  final Map<PuppetNodeUuid, RenderData> _renderDataMap = {};
  final Map<PuppetNodeUuid, List<PuppetNodeUuid>> _compositeChildren = {};
  Set<PuppetNodeUuid> _compositeChildSet = {};
  final Map<PuppetNodeUuid, List<PuppetNodeUuid>> _meshGroupChildren = {};
  Set<PuppetNodeUuid> _meshGroupChildSet = {};
  final Map<int, ui.Image> _textureCache = {};

  /// RenderData for composite children (not in main _drawables list)
  final List<RenderData> _compositeChildDrawables = [];

  /// RenderData for mesh group children (not in main _drawables list)
  final List<RenderData> _meshGroupChildDrawables = [];

  /// Optional texture atlas
  TextureAtlas? _atlas;

  RenderCtx();

  /// Initialize render context from puppet
  void initialize(Puppet puppet) {
    _drawables.clear();
    _renderDataMap.clear();
    _compositeChildren.clear();
    _compositeChildSet = {};
    _compositeChildDrawables.clear();
    _meshGroupChildren.clear();
    _meshGroupChildSet = {};
    _meshGroupChildDrawables.clear();

    _collectDrawables(puppet);
  }

  /// Recursively collect all descendant UUIDs of a tree node
  void _collectDescendants(TreeNode<PuppetNode> node, List<PuppetNodeUuid> result) {
    for (final child in node.children) {
      result.add(child.data.uuid);
      _collectDescendants(child, result);
    }
  }

  void _collectDrawables(Puppet puppet) {
    final transformCtx = puppet.transformCtx;
    final zsortCtx = puppet.zsortCtx;

    // Pass 1: Identify all composite and mesh group nodes and collect all their descendant UUIDs
    for (final treeNode in puppet.nodes.preOrder()) {
      final node = treeNode.data;
      final components = node.components;
      if (components == null || !node.enabled) continue;

      if (components.isComposite) {
        final descendants = <PuppetNodeUuid>[];
        _collectDescendants(treeNode, descendants);
        _compositeChildren[node.uuid] = descendants;
        for (final d in descendants) {
          _compositeChildSet.add(d);
        }
      } else if (components.isMeshGroup) {
        final descendants = <PuppetNodeUuid>[];
        _collectDescendants(treeNode, descendants);
        _meshGroupChildren[node.uuid] = descendants;
        for (final d in descendants) {
          _meshGroupChildSet.add(d);
        }
      }
    }

    // Pass 2: Collect drawables, skipping composite and mesh group children
    for (final treeNode in puppet.nodes.preOrder()) {
      final node = treeNode.data;
      final components = node.components;
      if (components == null || !node.enabled) continue;

      // Skip nodes that are children of a composite — they render via their composite parent
      if (_compositeChildSet.contains(node.uuid)) {
        // Still create RenderData for composite children so they can be drawn by the composite
        final transform =
            transformCtx?.getStore(node.uuid)?.absolute ?? Mat4.identity();

        if (components.isComposite) {
          // Nested composite: create composite RenderData so the outer composite
          // can delegate rendering to the inner composite via _drawComposite()
          final renderData = RenderData(
            nodeId: node.uuid,
            kind: DrawableKind.composite,
            transform: transform,
            drawable: components.drawable ?? Drawable(),
            composite: components.composite,
          );
          _compositeChildDrawables.add(renderData);
          _renderDataMap[node.uuid] = renderData;
        } else if (components.isDrawable) {
          List<Vec2>? deformedVertices;
          if (components.mesh != null && components.deformStack != null) {
            deformedVertices = components.deformStack!.applyTo(
              components.mesh!.vertices,
            );
          }

          final renderData = RenderData(
            nodeId: node.uuid,
            kind: DrawableKind.texturedMesh,
            transform: transform,
            drawable: components.drawable!,
            mesh: components.mesh,
            texturedMesh: components.texturedMesh,
            deformedVertices: deformedVertices,
          );
          _compositeChildDrawables.add(renderData);
          _renderDataMap[node.uuid] = renderData;
        }
        continue;
      }

      // Skip nodes that are children of a mesh group — they render via their mesh group parent
      if (_meshGroupChildSet.contains(node.uuid)) {
        final transform =
            transformCtx?.getStore(node.uuid)?.absolute ?? Mat4.identity();

        if (components.isMeshGroup) {
          // Nested mesh group
          final renderData = RenderData(
            nodeId: node.uuid,
            kind: DrawableKind.meshGroup,
            transform: transform,
            drawable: components.drawable ?? Drawable(),
            meshGroup: components.meshGroup,
          );
          _meshGroupChildDrawables.add(renderData);
          _renderDataMap[node.uuid] = renderData;
        } else if (components.isDrawable) {
          List<Vec2>? deformedVertices;
          if (components.mesh != null && components.deformStack != null) {
            deformedVertices = components.deformStack!.applyTo(
              components.mesh!.vertices,
            );
          }

          final renderData = RenderData(
            nodeId: node.uuid,
            kind: DrawableKind.texturedMesh,
            transform: transform,
            drawable: components.drawable!,
            mesh: components.mesh,
            texturedMesh: components.texturedMesh,
            deformedVertices: deformedVertices,
          );
          _meshGroupChildDrawables.add(renderData);
          _renderDataMap[node.uuid] = renderData;
        }
        continue;
      }

      final transform =
          transformCtx?.getStore(node.uuid)?.absolute ?? Mat4.identity();

      if (components.isDrawable) {
        // Get deformed vertices
        List<Vec2>? deformedVertices;
        if (components.mesh != null && components.deformStack != null) {
          deformedVertices = components.deformStack!.applyTo(
            components.mesh!.vertices,
          );
        }

        final renderData = RenderData(
          nodeId: node.uuid,
          kind: DrawableKind.texturedMesh,
          transform: transform,
          drawable: components.drawable!,
          mesh: components.mesh,
          texturedMesh: components.texturedMesh,
          deformedVertices: deformedVertices,
        );
        _drawables.add(renderData);
        _renderDataMap[node.uuid] = renderData;
      } else if (components.isComposite) {
        final renderData = RenderData(
          nodeId: node.uuid,
          kind: DrawableKind.composite,
          transform: transform,
          drawable: components.drawable ?? Drawable(),
          composite: components.composite,
        );
        _drawables.add(renderData);
        _renderDataMap[node.uuid] = renderData;
      } else if (components.isMeshGroup) {
        final renderData = RenderData(
          nodeId: node.uuid,
          kind: DrawableKind.meshGroup,
          transform: transform,
          drawable: components.drawable ?? Drawable(),
          meshGroup: components.meshGroup,
        );
        _drawables.add(renderData);
        _renderDataMap[node.uuid] = renderData;
      }
    }
  }

  /// Update render data (call each frame after puppet update)
  void update(Puppet puppet) {
    final transformCtx = puppet.transformCtx;
    final zsortCtx = puppet.zsortCtx;

    // Update transforms and deformations for main drawables
    for (int i = 0; i < _drawables.length; i++) {
      final data = _drawables[i];
      final node = puppet.nodes.getNode(data.nodeId)?.data;
      if (node == null) continue;

      final components = node.components;
      final transform =
          transformCtx?.getStore(node.uuid)?.absolute ?? Mat4.identity();

      // Get deformed vertices
      List<Vec2>? deformedVertices;
      if (components?.mesh != null && components?.deformStack != null) {
        deformedVertices = components!.deformStack!.applyTo(
          components.mesh!.vertices,
        );
      }

      final newData = RenderData(
        nodeId: data.nodeId,
        kind: data.kind,
        transform: transform,
        drawable: data.drawable,
        mesh: data.mesh,
        texturedMesh: data.texturedMesh,
        composite: data.composite,
        meshGroup: data.meshGroup,
        deformedVertices: deformedVertices ?? data.deformedVertices,
      );
      _drawables[i] = newData;
      _renderDataMap[data.nodeId] = newData;
    }

    // Update transforms and deformations for composite child drawables
    for (int i = 0; i < _compositeChildDrawables.length; i++) {
      final data = _compositeChildDrawables[i];
      final node = puppet.nodes.getNode(data.nodeId)?.data;
      if (node == null) continue;

      final components = node.components;
      final transform =
          transformCtx?.getStore(node.uuid)?.absolute ?? Mat4.identity();

      List<Vec2>? deformedVertices;
      if (components?.mesh != null && components?.deformStack != null) {
        deformedVertices = components!.deformStack!.applyTo(
          components.mesh!.vertices,
        );
      }

      final newData = RenderData(
        nodeId: data.nodeId,
        kind: data.kind,
        transform: transform,
        drawable: data.drawable,
        mesh: data.mesh,
        texturedMesh: data.texturedMesh,
        composite: data.composite,
        meshGroup: data.meshGroup,
        deformedVertices: deformedVertices ?? data.deformedVertices,
      );
      _compositeChildDrawables[i] = newData;
      _renderDataMap[data.nodeId] = newData;
    }

    // Update transforms and deformations for mesh group child drawables
    for (int i = 0; i < _meshGroupChildDrawables.length; i++) {
      final data = _meshGroupChildDrawables[i];
      final node = puppet.nodes.getNode(data.nodeId)?.data;
      if (node == null) continue;

      final components = node.components;
      final transform =
          transformCtx?.getStore(node.uuid)?.absolute ?? Mat4.identity();

      List<Vec2>? deformedVertices;
      if (components?.mesh != null && components?.deformStack != null) {
        deformedVertices = components!.deformStack!.applyTo(
          components.mesh!.vertices,
        );
      }

      final newData = RenderData(
        nodeId: data.nodeId,
        kind: data.kind,
        transform: transform,
        drawable: data.drawable,
        mesh: data.mesh,
        texturedMesh: data.texturedMesh,
        composite: data.composite,
        meshGroup: data.meshGroup,
        deformedVertices: deformedVertices ?? data.deformedVertices,
      );
      _meshGroupChildDrawables[i] = newData;
      _renderDataMap[data.nodeId] = newData;
    }

    // Sort by z-order (larger z = further back = draw first)
    _drawables.sort((a, b) {
      final za = zsortCtx?.getZSort(a.nodeId) ?? 0;
      final zb = zsortCtx?.getZSort(b.nodeId) ?? 0;
      return zb.compareTo(za); // Descending: larger z drawn first (back to front)
    });
  }

  /// Get sorted drawables
  List<RenderData> get drawables => _drawables;

  /// Get render data by node ID
  RenderData? getRenderData(PuppetNodeUuid nodeId) => _renderDataMap[nodeId];

  /// Get composite children UUIDs
  List<PuppetNodeUuid>? getCompositeChildren(PuppetNodeUuid compositeId) {
    return _compositeChildren[compositeId];
  }

  /// Get ordered RenderData for all drawable descendants of a composite node
  List<RenderData> getCompositeChildDrawables(PuppetNodeUuid compositeId) {
    final childUuids = _compositeChildren[compositeId];
    if (childUuids == null || childUuids.isEmpty) return [];

    final childUuidSet = childUuids.toSet();
    final result = <RenderData>[];
    for (final data in _compositeChildDrawables) {
      if (childUuidSet.contains(data.nodeId)) {
        result.add(data);
      }
    }
    return result;
  }

  /// Get mesh group children UUIDs
  List<PuppetNodeUuid>? getMeshGroupChildren(PuppetNodeUuid meshGroupId) {
    return _meshGroupChildren[meshGroupId];
  }

  /// Get ordered RenderData for all drawable descendants of a mesh group node
  List<RenderData> getMeshGroupChildDrawables(PuppetNodeUuid meshGroupId) {
    final childUuids = _meshGroupChildren[meshGroupId];
    if (childUuids == null || childUuids.isEmpty) return [];

    final childUuidSet = childUuids.toSet();
    final result = <RenderData>[];
    for (final data in _meshGroupChildDrawables) {
      if (childUuidSet.contains(data.nodeId)) {
        result.add(data);
      }
    }
    return result;
  }

  /// Set texture for texture ID
  void setTexture(int textureId, ui.Image image) {
    _textureCache[textureId] = image;
  }

  /// Get texture for texture ID
  /// Returns atlas texture if available, otherwise returns individual texture
  ui.Image? getTexture(int textureId) {
    if (_atlas != null && _atlas!.containsTexture(textureId)) {
      return _atlas!.atlasImage;
    }
    return _textureCache[textureId];
  }

  /// Get atlas region for a texture ID (if using atlas)
  AtlasRegion? getAtlasRegion(int textureId) {
    return _atlas?.getRegion(textureId);
  }

  /// Check if using texture atlas
  bool get hasAtlas => _atlas != null;

  /// Get the texture atlas
  TextureAtlas? get atlas => _atlas;

  /// Set texture atlas
  /// When set, getTexture() will return the atlas image for textures in the atlas
  void setAtlas(TextureAtlas? atlas) {
    _atlas?.dispose();
    _atlas = atlas;
  }

  /// Build texture atlas from current textures
  /// Returns true if atlas was successfully created
  Future<bool> buildAtlas([TextureAtlasConfig? config]) async {
    if (_textureCache.isEmpty) return false;

    final inputs = _textureCache.entries
        .map((e) => TextureInput(textureId: e.key, image: e.value))
        .toList();

    final builder = TextureAtlasBuilder(config ?? const TextureAtlasConfig());
    final atlas = await builder.build(inputs);

    if (atlas != null) {
      setAtlas(atlas);
      return true;
    }

    return false;
  }

  /// Dispose cached textures
  void dispose() {
    for (final image in _textureCache.values) {
      image.dispose();
    }
    _textureCache.clear();
    _atlas?.dispose();
    _atlas = null;
  }
}
