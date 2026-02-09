import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../core/core.dart';
import '../math/math.dart';
import '../params/param.dart';
import '../components/components.dart';
import 'bc7_decoder.dart';
import 'binary_reader.dart';

/// INP file format parser
class InpParser {
  // TRNSRTS binary format magic constants
  static const _trnsrtsMagic = [0x54, 0x52, 0x4E, 0x53, 0x52, 0x54, 0x53, 0x00]; // "TRNSRTS\0"
  static const _texSectMagic = [0x54, 0x45, 0x58, 0x5F, 0x53, 0x45, 0x43, 0x54]; // "TEX_SECT"
  static const _extSectMagic = [0x45, 0x58, 0x54, 0x5F, 0x53, 0x45, 0x43, 0x54]; // "EXT_SECT"

  /// Load model from bytes
  static Model parse(Uint8List bytes) {
    // Check if it's a TRNSRTS binary format (INP/INX)
    if (_isTrnsrtsFormat(bytes)) {
      return _parseTrnsrts(bytes);
    }

    // Check if it's a ZIP archive (older INP format)
    if (_isZipArchive(bytes)) {
      return _parseInpZip(bytes);
    }

    throw FormatException('Unsupported file format: not TRNSRTS or ZIP');
  }

  static bool _isTrnsrtsFormat(Uint8List bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 0x54 &&
        bytes[1] == 0x52 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x53 &&
        bytes[4] == 0x52 &&
        bytes[5] == 0x54 &&
        bytes[6] == 0x53 &&
        bytes[7] == 0x00;
  }

  static Model _parseTrnsrts(Uint8List bytes) {
    final reader = BinaryReader(bytes);

    // Validate TRNSRTS magic (8 bytes)
    final magic = reader.readBytes(8);
    if (!_bytesEqual(magic, Uint8List.fromList(_trnsrtsMagic))) {
      throw FormatException('Invalid TRNSRTS magic');
    }

    // Read JSON payload length (big-endian u32)
    final jsonLength = reader.readUint32BE();
    final jsonBytes = reader.readBytes(jsonLength);
    final jsonStr = utf8.decode(jsonBytes);
    final puppetJson = jsonDecode(jsonStr) as Map<String, dynamic>;

    // Validate TEX_SECT section marker (8 bytes)
    final texSect = reader.readBytes(8);
    if (!_bytesEqual(texSect, Uint8List.fromList(_texSectMagic))) {
      throw FormatException('TEX_SECT section not found');
    }

    // Read texture count (big-endian u32)
    final texCount = reader.readUint32BE();
    final textures = <ModelTexture>[];

    // Parse each texture
    for (int i = 0; i < texCount; i++) {
      final texLength = reader.readUint32BE();
      final texEncoding = reader.readUint8();
      final texData = reader.readBytes(texLength);

      // Decode texture format: 0=PNG, 1=TGA, 2=BC7
      final format = _decodeTextureFormat(texEncoding);
      if (format == ImageFormat.bc7) {
        // BC7 data blob: first 4 bytes = width (BE), next 4 bytes = height (BE),
        // remaining bytes = raw BC7 block data.
        if (texData.length < 8) {
          throw FormatException(
            'BC7 texture data too small: need at least 8 bytes for '
            'width/height header, got ${texData.length}',
          );
        }
        final texReader = BinaryReader(texData);
        final width = texReader.readUint32BE();
        final height = texReader.readUint32BE();
        final bc7Data = Uint8List.sublistView(texData, 8);
        final decoded = decodeBc7(bc7Data, width, height);
        textures.add(ModelTexture(
          format: ImageFormat.bc7,
          data: decoded,
          width: width,
          height: height,
        ));
      } else {
        textures.add(ModelTexture(format: format, data: texData));
      }
    }

    // Optionally read EXT_SECT for vendor data
    final vendorData = <VendorData>[];
    if (reader.hasMore) {
      try {
        final extSect = reader.readBytes(8);
        if (_bytesEqual(extSect, Uint8List.fromList(_extSectMagic))) {
          final vendorCount = reader.readUint32BE();
          for (int i = 0; i < vendorCount; i++) {
            // Read vendor name
            final nameLength = reader.readUint32BE();
            final nameBytes = reader.readBytes(nameLength);
            final name = utf8.decode(nameBytes);

            // Read vendor payload
            final payloadLength = reader.readUint32BE();
            final payloadBytes = reader.readBytes(payloadLength);
            final payloadStr = utf8.decode(payloadBytes);
            final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

            vendorData.add(VendorData.fromJson({'name': name, 'payload': payload}));
          }
        }
      } catch (_) {
        // If EXT_SECT parsing fails, just ignore vendor data
      }
    }

    // Parse puppet from JSON
    final puppet = _parsePuppet(puppetJson);
    return Model(puppet: puppet, textures: textures, vendorData: vendorData);
  }

  static ImageFormat _decodeTextureFormat(int encoding) {
    switch (encoding) {
      case 0:
        return ImageFormat.png;
      case 1:
        return ImageFormat.tga;
      case 2:
        return ImageFormat.bc7;
      default:
        throw FormatException('Invalid texture encoding: $encoding');
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _isZipArchive(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // ZIP magic: PK\x03\x04
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  static Model _parseInpZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find and parse puppet.json
    Map<String, dynamic>? puppetJson;
    final textures = <ModelTexture>[];
    final vendorData = <VendorData>[];

    for (final file in archive.files) {
      final name = file.name;

      if (name == 'puppet.json' || name.endsWith('/puppet.json')) {
        final content = utf8.decode(file.content as List<int>);
        puppetJson = jsonDecode(content) as Map<String, dynamic>;
      } else if (name.startsWith('textures/') || name.contains('/textures/')) {
        // Load texture
        final textureData = Uint8List.fromList(file.content as List<int>);
        textures.add(ModelTexture.fromBytes(textureData));
      } else if (name.startsWith('vendor/') || name.contains('/vendor/')) {
        // Load vendor data
        try {
          final content = utf8.decode(file.content as List<int>);
          final json = jsonDecode(content) as Map<String, dynamic>;
          vendorData.add(VendorData.fromJson(json));
        } catch (_) {
          // Ignore invalid vendor data
        }
      }
    }

    if (puppetJson == null) {
      throw FormatException('puppet.json not found in INP file');
    }

    final puppet = _parsePuppet(puppetJson);
    return Model(puppet: puppet, textures: textures, vendorData: vendorData);
  }

  static Puppet _parsePuppet(Map<String, dynamic> json) {
    // Parse metadata
    final meta = PuppetMeta.fromJson(json['meta'] ?? {});

    // Parse physics
    final physics = PuppetPhysics.fromJson(json['physics'] ?? {});

    // Parse nodes
    final nodesJson = json['nodes'] as Map<String, dynamic>? ?? {};
    final nodes = _parseNodes(nodesJson);

    // Parse parameters (note: actual format uses 'param' not 'params')
    final paramsJson = json['param'] as List? ?? [];
    final params = paramsJson
        .map((p) => Param.fromJson(p as Map<String, dynamic>))
        .toList();

    // Parse expression presets
    final expressionsJson =
        json['expressions'] as Map<String, dynamic>? ?? {};
    final expressions = <String, Map<String, double>>{};
    for (final entry in expressionsJson.entries) {
      final values = entry.value as Map<String, dynamic>? ?? {};
      expressions[entry.key] = values.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      );
    }

    return Puppet(
      meta: meta,
      physics: physics,
      nodes: nodes,
      params: params,
      expressions: expressions,
    );
  }

  static PuppetNodeTree _parseNodes(Map<String, dynamic> json) {
    // Create root node
    final rootJson = json['root'] as Map<String, dynamic>? ??
        {'uuid': 0, 'name': 'root'};
    final rootNode = _parseNode(rootJson);
    final tree = PuppetNodeTree.withRoot(rootNode);

    // Parse children recursively
    final childrenJson = json['children'] as List? ?? [];
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

    // Parse children
    final childrenJson = json['children'] as List? ?? [];
    for (final child in childrenJson) {
      _parseNodeRecursive(child as Map<String, dynamic>, node.uuid, tree);
    }
  }

  static bool _nodeTypeLogged = false;
  static final Map<String, int> _nodeTypeCounts = {};

  static PuppetNode _parseNode(Map<String, dynamic> json) {
    final uuid = json['uuid'] as int? ?? 0;
    final name = json['name'] as String? ?? '';
    final enabled = json['enabled'] as bool? ?? true;
    final zsort = (json['zsort'] as num?)?.toDouble() ?? 0.0;
    final lockToRoot = json['lock_to_root'] as bool? ?? false;

    // Parse transform
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

    // Parse components
    NodeComponents? components;
    final type = json['type'] as String? ?? 'node';

    // Debug: count node types
    _nodeTypeCounts[type] = (_nodeTypeCounts[type] ?? 0) + 1;
    if (!_nodeTypeLogged && _nodeTypeCounts.values.fold(0, (a, b) => a + b) >= 100) {
      print('[Parser] Node type counts: $_nodeTypeCounts');
      _nodeTypeLogged = true;
    }

    final typeLower = type.toLowerCase();
    if (typeLower == 'part' || typeLower == 'drawable') {
      final drawable = Drawable.fromJson(json);
      final mesh = json['mesh'] != null
          ? Mesh.fromJson(json['mesh'] as Map<String, dynamic>)
          : null;

      // Parse texture IDs - format uses 'textures' array where first is albedo
      int? albedoTextureId;
      final texturesArray = json['textures'] as List?;
      if (texturesArray != null && texturesArray.isNotEmpty) {
        albedoTextureId = (texturesArray[0] as num?)?.toInt();
      }
      // Fallback to legacy 'texture_id' field
      albedoTextureId ??= json['texture_id'] as int?;

      final texturedMesh = TexturedMesh(
        albedoTextureId: albedoTextureId,
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
    } else if (typeLower == 'meshgroup' || typeLower == 'mesh_group') {
      components = NodeComponents(
        meshGroup: MeshGroup.fromJson(json),
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
