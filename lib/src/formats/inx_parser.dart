import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../core/core.dart';
import '../math/math.dart';
import '../params/param.dart';
import '../components/components.dart';
import 'binary_reader.dart';

/// INX file format parser (binary Inochi2D format)
class InxParser {
  static const _magic = [0x49, 0x4E, 0x4F, 0x58]; // "INOX"

  /// Load model from INX file
  static Future<Model> loadFromFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    return parse(bytes);
  }

  /// Load model from bytes
  static Model parse(Uint8List bytes) {
    final reader = BinaryReader(bytes);

    // Check magic
    final magic = reader.readBytes(4);
    if (magic[0] != _magic[0] ||
        magic[1] != _magic[1] ||
        magic[2] != _magic[2] ||
        magic[3] != _magic[3]) {
      throw FormatException('Invalid INX magic');
    }

    // Read version
    final version = reader.readUint32BE();
    if (version > 1) {
      throw FormatException('Unsupported INX version: $version');
    }

    // Read sections
    Map<String, dynamic>? puppetJson;
    final textures = <ModelTexture>[];
    final vendorData = <VendorData>[];

    while (reader.hasMore) {
      final sectionType = reader.readUint32BE();
      final sectionLength = reader.readUint32BE();

      switch (sectionType) {
        case 0x50555050: // "PUPP" - Puppet data
          final puppetBytes = reader.readBytes(sectionLength);
          final puppetStr = utf8.decode(puppetBytes);
          puppetJson = jsonDecode(puppetStr) as Map<String, dynamic>;
          break;

        case 0x54455854: // "TEXT" - Textures
          final textureBytes = reader.readBytes(sectionLength);
          textures.add(ModelTexture.fromBytes(textureBytes));
          break;

        case 0x56454E44: // "VEND" - Vendor data
          final vendorBytes = reader.readBytes(sectionLength);
          final vendorStr = utf8.decode(vendorBytes);
          final json = jsonDecode(vendorStr) as Map<String, dynamic>;
          vendorData.add(VendorData.fromJson(json));
          break;

        default:
          // Skip unknown section
          reader.skip(sectionLength);
      }
    }

    if (puppetJson == null) {
      throw FormatException('No puppet data found in INX file');
    }

    final puppet = _parsePuppet(puppetJson);
    return Model(puppet: puppet, textures: textures, vendorData: vendorData);
  }

  static Puppet _parsePuppet(Map<String, dynamic> json) {
    // Parse metadata
    final meta = PuppetMeta.fromJson(json['meta'] ?? {});

    // Parse physics
    final physics = PuppetPhysics.fromJson(json['physics'] ?? {});

    // Parse nodes — support both utsutsu-builder format (Map) and
    // official Inochi2D INX format (List where [0] is the root node).
    final nodesRaw = json['nodes'];
    final PuppetNodeTree nodes;
    if (nodesRaw is Map<String, dynamic>) {
      nodes = _parseNodes(nodesRaw);
    } else if (nodesRaw is List && nodesRaw.isNotEmpty) {
      nodes = _parseNodesFromRoot(nodesRaw[0] as Map<String, dynamic>);
    } else {
      nodes = _parseNodes({});
    }

    // Parse parameters
    final paramsJson = json['params'] as List? ?? [];
    final params = paramsJson
        .map((p) => Param.fromJson(p as Map<String, dynamic>))
        .toList();

    return Puppet(
      meta: meta,
      physics: physics,
      nodes: nodes,
      params: params,
    );
  }

  static PuppetNodeTree _parseNodes(Map<String, dynamic> json) {
    // Parse root node
    final rootJson = json['root'] as Map<String, dynamic>? ??
        {'uuid': 0, 'name': 'root'};
    final rootNode = _parseNode(rootJson);
    final tree = PuppetNodeTree.withRoot(rootNode);

    // Parse children
    final childrenJson = json['children'] as List? ?? [];
    for (final child in childrenJson) {
      _parseNodeRecursive(child as Map<String, dynamic>, rootNode.uuid, tree);
    }

    return tree;
  }

  /// Parse nodes from official Inochi2D format where the root node is
  /// provided directly (e.g. nodes[0]).
  static PuppetNodeTree _parseNodesFromRoot(Map<String, dynamic> rootJson) {
    final rootNode = _parseNode(rootJson);
    final tree = PuppetNodeTree.withRoot(rootNode);

    final childrenJson = rootJson['children'] as List? ?? [];
    for (final child in childrenJson) {
      _parseNodeRecursive(child as Map<String, dynamic>, rootNode.uuid, tree);
    }

    return tree;
  }

  static void _parseNodeRecursive(
    Map<String, dynamic> json,
    PuppetNodeUuid parentUuid,
    PuppetNodeTree tree,
  ) {
    final node = _parseNode(json);
    tree.addNode(node, parentUuid);

    final childrenJson = json['children'] as List? ?? [];
    for (final child in childrenJson) {
      _parseNodeRecursive(child as Map<String, dynamic>, node.uuid, tree);
    }
  }

  static PuppetNode _parseNode(Map<String, dynamic> json) {
    final uuid = json['uuid'] as int? ?? 0;
    final name = json['name'] as String? ?? '';
    final enabled = json['enabled'] as bool? ?? true;
    final zsort = (json['zsort'] as num?)?.toDouble() ?? 0.0;
    final lockToRoot = json['lock_to_root'] as bool? ?? false;

    TransformOffset? transOffset;
    if (json['transform'] != null) {
      final t = json['transform'] as Map<String, dynamic>;
      transOffset = TransformOffset(
        translation: _parseVec3(t['trans']),
        rotation: _parseVec3(t['rot']),
        scale: _parseVec2(t['scale'], const Vec2.one()),
        pixelSnap: t['pixel_snap'] as bool? ?? false,
      );
    }

    NodeComponents? components;
    final type = json['type'] as String? ?? 'node';
    final typeLower = type.toLowerCase();

    if (typeLower == 'part' || typeLower == 'drawable') {
      final drawable = Drawable.fromJson(json);
      final mesh = json['mesh'] != null
          ? Mesh.fromJson(json['mesh'] as Map<String, dynamic>)
          : null;
      final texturedMesh = TexturedMesh(
        albedoTextureId: json['texture_id'] as int?,
      );

      components = NodeComponents(
        drawable: drawable,
        mesh: mesh,
        texturedMesh: texturedMesh,
        deformStack: mesh != null ? DeformStack(mesh.vertexCount) : null,
      );
    } else if (typeLower == 'composite') {
      components = NodeComponents(
        composite: Composite.fromJson(json),
      );
    } else if (typeLower == 'simple_physics' || typeLower == 'simplephysics') {
      components = NodeComponents(
        simplePhysics: SimplePhysics.fromJson(json),
      );
    } else if (typeLower == 'pathdeformer' || typeLower == 'bezierdeformer') {
      components = NodeComponents(
        pathDeform: PathDeform.fromJson(json),
      );
    }

    return PuppetNode(
      uuid: uuid,
      name: name,
      enabled: enabled,
      zsort: zsort,
      transOffset: transOffset,
      lockToRoot: lockToRoot,
      components: components,
    );
  }

  static Vec3 _parseVec3(dynamic value) {
    if (value == null) return const Vec3.zero();
    if (value is List && value.length >= 3) {
      return Vec3(
        (value[0] as num).toDouble(),
        (value[1] as num).toDouble(),
        (value[2] as num).toDouble(),
      );
    }
    return const Vec3.zero();
  }

  static Vec2 _parseVec2(dynamic value, Vec2 defaultVal) {
    if (value == null) return defaultVal;
    if (value is List && value.length >= 2) {
      return Vec2(
        (value[0] as num).toDouble(),
        (value[1] as num).toDouble(),
      );
    }
    return defaultVal;
  }
}
