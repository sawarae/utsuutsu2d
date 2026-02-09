import 'dart:typed_data';
import 'puppet.dart';

/// Supported image formats for puppet textures.
///
/// Supports common image formats used in puppet models.
/// The format is automatically detected from the image data signature.
enum ImageFormat {
  png,
  jpeg,
  webp,
  tga,
  bc7,
  unknown,
}

/// Represents a texture used by a puppet model.
///
/// Contains the raw image data and format information. The texture data
/// must be decoded into a Flutter [ui.Image] before rendering.
///
/// Example:
/// ```dart
/// final model = await loadFromFile('puppet.inx');
/// for (final texture in model.textures) {
///   print('Format: ${texture.format}');
///   print('Size: ${texture.data.length} bytes');
///
///   // Decode to Flutter Image
///   final codec = await ui.instantiateImageCodec(texture.data);
///   final frame = await codec.getNextFrame();
///   final image = frame.image;
/// }
/// ```
class ModelTexture {
  /// The detected image format (PNG, JPEG, WebP, or TGA).
  final ImageFormat format;

  /// Raw image data bytes.
  final Uint8List data;

  /// Image width in pixels (optional, may not be available until decoded).
  final int? width;

  /// Image height in pixels (optional, may not be available until decoded).
  final int? height;

  ModelTexture({
    required this.format,
    required this.data,
    this.width,
    this.height,
  });

  factory ModelTexture.fromBytes(Uint8List data) {
    final format = _detectFormat(data);
    return ModelTexture(format: format, data: data);
  }

  static ImageFormat _detectFormat(Uint8List data) {
    if (data.length < 8) return ImageFormat.unknown;

    // PNG signature: 89 50 4E 47 0D 0A 1A 0A
    if (data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return ImageFormat.png;
    }

    // JPEG signature: FF D8 FF
    if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) {
      return ImageFormat.jpeg;
    }

    // WebP signature: RIFF....WEBP
    if (data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46 &&
        data.length >= 12 &&
        data[8] == 0x57 &&
        data[9] == 0x45 &&
        data[10] == 0x42 &&
        data[11] == 0x50) {
      return ImageFormat.webp;
    }

    // TGA (no standard signature, check by extension)
    return ImageFormat.unknown;
  }
}

/// Contains vendor-specific custom data embedded in the model.
///
/// Some puppet editing tools may embed custom data for their own use.
/// This data is preserved during loading but not used by the
/// core functionality.
class VendorData {
  /// Vendor or tool name (e.g., "Inochi Creator", "nijigenerate").
  final String name;

  /// Arbitrary JSON-compatible data payload.
  final Map<String, dynamic> payload;

  VendorData({
    required this.name,
    required this.payload,
  });

  factory VendorData.fromJson(Map<String, dynamic> json) {
    return VendorData(
      name: json['name'] ?? '',
      payload: json['payload'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'payload': payload,
    };
  }

  @override
  String toString() => 'VendorData(name: $name)';
}

/// A complete puppet model loaded from an INP/INX file.
///
/// [Model] is the top-level container for all puppet data, including:
/// - The puppet rig (nodes, parameters, physics)
/// - Texture assets
/// - Optional vendor-specific metadata
///
/// ## Loading a Model
///
/// ```dart
/// import 'package:utsutsu2d/utsutsu2d.dart';
///
/// final model = await loadFromFile('puppet.inx');
/// print('Loaded: ${model.puppet.meta.name}');
/// print('Textures: ${model.textures.length}');
/// print('Nodes: ${model.puppet.nodes.nodeCount}');
/// print('Parameters: ${model.puppet.params.length}');
/// ```
///
/// ## Initializing for Use
///
/// Before rendering or animating, the puppet must be initialized:
///
/// ```dart
/// model.puppet.initAll(); // Initialize transforms, params, and physics
/// ```
///
/// Or initialize subsystems individually:
/// ```dart
/// model.puppet.initTransforms(); // Required first
/// model.puppet.initParams();     // After transforms
/// model.puppet.initPhysics();    // After params
/// ```
///
/// See also:
/// - [Puppet] for the puppet rig structure
/// - [ModelTexture] for texture data
/// - [loadFromFile] for loading models from files
class Model {
  /// The puppet rig containing nodes, parameters, and physics.
  final Puppet puppet;

  /// List of texture assets used by the puppet's mesh parts.
  final List<ModelTexture> textures;

  /// Optional vendor-specific data (preserved but not used by core).
  final List<VendorData> vendorData;

  Model({
    required this.puppet,
    required this.textures,
    this.vendorData = const [],
  });

  @override
  String toString() =>
      'Model(puppet: ${puppet.meta.name}, textures: ${textures.length})';
}
