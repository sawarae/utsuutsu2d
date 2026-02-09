import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../math/vec2.dart';

/// Configuration for texture atlas generation
class TextureAtlasConfig {
  /// Maximum atlas texture size (default: 4096x4096)
  /// Mobile GPUs typically support 4096x4096, some support up to 8192x8192
  final int maxAtlasSize;

  /// Padding between textures in pixels (default: 2)
  /// Prevents texture bleeding, especially important for mipmapping
  final int padding;

  /// Whether to force power-of-2 atlas dimensions (default: false)
  /// Some older platforms prefer power-of-2 textures
  final bool forcePowerOfTwo;

  /// Packing algorithm to use
  final PackingAlgorithm algorithm;

  const TextureAtlasConfig({
    this.maxAtlasSize = 4096,
    this.padding = 2,
    this.forcePowerOfTwo = false,
    this.algorithm = PackingAlgorithm.shelf,
  });
}

/// Packing algorithms for texture atlas
enum PackingAlgorithm {
  /// Shelf packing: Simple, fast, good for similar-sized textures
  shelf,

  /// MaxRects: More efficient space usage, better for varied sizes
  maxRects,
}

/// A region within a texture atlas
class AtlasRegion {
  /// Texture ID this region represents
  final int textureId;

  /// Position in atlas (pixels)
  final int x;
  final int y;

  /// Size of the region (pixels)
  final int width;
  final int height;

  /// UV coordinates in atlas (0.0 to 1.0)
  final Vec2 uvMin;
  final Vec2 uvMax;

  AtlasRegion({
    required this.textureId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.uvMin,
    required this.uvMax,
  });

  /// Transform original UV coordinate to atlas UV coordinate
  Vec2 transformUV(Vec2 originalUV) {
    // Original UV is in 0-1 range for the individual texture
    // We need to map it to the region within the atlas
    final u = uvMin.x + originalUV.x * (uvMax.x - uvMin.x);
    final v = uvMin.y + originalUV.y * (uvMax.y - uvMin.y);
    return Vec2(u, v);
  }

  @override
  String toString() =>
      'AtlasRegion(id=$textureId, x=$x, y=$y, w=$width, h=$height, uv=($uvMin to $uvMax))';
}

/// Input texture information for atlas packing
class TextureInput {
  final int textureId;
  final ui.Image image;

  TextureInput({
    required this.textureId,
    required this.image,
  });

  int get width => image.width;
  int get height => image.height;
}

/// Result of texture atlas packing
class TextureAtlas {
  /// The combined atlas image
  final ui.Image atlasImage;

  /// Regions mapping texture IDs to their locations in the atlas
  final Map<int, AtlasRegion> regions;

  /// Configuration used to generate this atlas
  final TextureAtlasConfig config;

  /// Actual atlas dimensions
  final int width;
  final int height;

  TextureAtlas({
    required this.atlasImage,
    required this.regions,
    required this.config,
    required this.width,
    required this.height,
  });

  /// Get region for a texture ID
  AtlasRegion? getRegion(int textureId) => regions[textureId];

  /// Check if a texture is in this atlas
  bool containsTexture(int textureId) => regions.containsKey(textureId);

  /// Dispose the atlas image
  void dispose() {
    atlasImage.dispose();
  }

  @override
  String toString() =>
      'TextureAtlas(size=${width}x$height, textures=${regions.length})';
}

/// Rectangle for packing algorithm
class _PackRect {
  int x;
  int y;
  int width;
  int height;
  int textureId;

  _PackRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.textureId,
  });
}

/// Builder for creating texture atlases
class TextureAtlasBuilder {
  final TextureAtlasConfig config;

  TextureAtlasBuilder([this.config = const TextureAtlasConfig()]);

  /// Build a texture atlas from a list of textures
  Future<TextureAtlas?> build(List<TextureInput> textures) async {
    if (textures.isEmpty) return null;

    // Validate config
    if (config.maxAtlasSize <= 0) {
      throw ArgumentError('maxAtlasSize must be positive: ${config.maxAtlasSize}');
    }
    if (config.padding < 0) {
      throw ArgumentError('padding must be non-negative: ${config.padding}');
    }

    // Validate individual textures
    for (final texture in textures) {
      if (texture.width <= 0 || texture.height <= 0) {
        throw ArgumentError(
          'Texture ${texture.textureId} has invalid dimensions: '
          '${texture.width}x${texture.height}');
      }
      final paddedWidth = texture.width + config.padding * 2;
      final paddedHeight = texture.height + config.padding * 2;
      if (paddedWidth > config.maxAtlasSize || paddedHeight > config.maxAtlasSize) {
        throw ArgumentError(
          'Texture ${texture.textureId} (${texture.width}x${texture.height}) '
          'exceeds max atlas size ${config.maxAtlasSize} with padding ${config.padding}');
      }
    }

    // Check for duplicate IDs
    final seen = <int>{};
    final duplicates = <int>{};
    for (final t in textures) {
      if (!seen.add(t.textureId)) duplicates.add(t.textureId);
    }
    if (duplicates.isNotEmpty) {
      throw ArgumentError('Duplicate texture IDs detected: $duplicates');
    }

    // Sort textures by height (descending) for better packing
    final sortedTextures = List<TextureInput>.from(textures)
      ..sort((a, b) => b.height.compareTo(a.height));

    // Pack textures
    final packedRects = _packTextures(sortedTextures);
    if (packedRects == null) {
      throw StateError(
        'Failed to pack ${textures.length} textures into '
        '${config.maxAtlasSize}x${config.maxAtlasSize} atlas');
    }

    // Calculate required atlas size
    int atlasWidth = 0;
    int atlasHeight = 0;
    for (final rect in packedRects) {
      atlasWidth = math.max(atlasWidth, rect.x + rect.width);
      atlasHeight = math.max(atlasHeight, rect.y + rect.height);
    }

    // Adjust to power of 2 if required
    if (config.forcePowerOfTwo) {
      atlasWidth = _nextPowerOfTwo(atlasWidth);
      atlasHeight = _nextPowerOfTwo(atlasHeight);
    }

    // Create atlas image
    final atlasImage = await _createAtlasImage(
      sortedTextures,
      packedRects,
      atlasWidth,
      atlasHeight,
    );

    // Create regions with UV coordinates
    final regions = <int, AtlasRegion>{};
    for (final rect in packedRects) {
      final uvMin = Vec2(
        rect.x / atlasWidth,
        rect.y / atlasHeight,
      );
      final uvMax = Vec2(
        (rect.x + rect.width) / atlasWidth,
        (rect.y + rect.height) / atlasHeight,
      );

      regions[rect.textureId] = AtlasRegion(
        textureId: rect.textureId,
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        uvMin: uvMin,
        uvMax: uvMax,
      );
    }

    return TextureAtlas(
      atlasImage: atlasImage,
      regions: regions,
      config: config,
      width: atlasWidth,
      height: atlasHeight,
    );
  }

  /// Pack textures using configured algorithm
  List<_PackRect>? _packTextures(List<TextureInput> textures) {
    switch (config.algorithm) {
      case PackingAlgorithm.shelf:
        return _packShelf(textures);
      case PackingAlgorithm.maxRects:
        return _packMaxRects(textures);
    }
  }

  /// Shelf packing algorithm
  /// Simple and fast: places textures on horizontal shelves
  List<_PackRect>? _packShelf(List<TextureInput> textures) {
    final rects = <_PackRect>[];
    final padding = config.padding;

    int currentX = padding;
    int currentY = padding;
    int shelfHeight = 0;

    for (final texture in textures) {
      final textureWidth = texture.width;
      final textureHeight = texture.height;

      // Check if texture fits on current shelf
      if (currentX + textureWidth + padding > config.maxAtlasSize) {
        // Move to next shelf
        currentX = padding;
        currentY += shelfHeight + padding;
        shelfHeight = 0;
      }

      // Check if we've exceeded vertical space
      if (currentY + textureHeight + padding > config.maxAtlasSize) {
        return null; // Failed to pack
      }

      // Place texture
      rects.add(_PackRect(
        x: currentX,
        y: currentY,
        width: textureWidth,
        height: textureHeight,
        textureId: texture.textureId,
      ));

      currentX += textureWidth + padding;
      shelfHeight = math.max(shelfHeight, textureHeight);
    }

    return rects;
  }

  /// MaxRects packing algorithm
  /// More complex but better space utilization
  /// Simplified guillotine-based approach for better reliability
  List<_PackRect>? _packMaxRects(List<TextureInput> textures) {
    final rects = <_PackRect>[];
    final freeRectangles = <_FreeRect>[
      _FreeRect(0, 0, config.maxAtlasSize, config.maxAtlasSize),
    ];
    final padding = config.padding;

    for (final texture in textures) {
      final width = texture.width + padding * 2;
      final height = texture.height + padding * 2;

      // Find best free rectangle using best area fit
      int bestIndex = -1;
      int bestAreaFit = config.maxAtlasSize * config.maxAtlasSize + 1;
      int bestShortSideFit = config.maxAtlasSize + 1;

      for (int i = 0; i < freeRectangles.length; i++) {
        final freeRect = freeRectangles[i];
        if (freeRect.width >= width && freeRect.height >= height) {
          final areaFit = freeRect.width * freeRect.height - width * height;
          final leftoverHoriz = freeRect.width - width;
          final leftoverVert = freeRect.height - height;
          final shortSideFit = math.min(leftoverHoriz, leftoverVert);

          if (areaFit < bestAreaFit ||
              (areaFit == bestAreaFit && shortSideFit < bestShortSideFit)) {
            bestIndex = i;
            bestAreaFit = areaFit;
            bestShortSideFit = shortSideFit;
          }
        }
      }

      if (bestIndex == -1) {
        return null; // Failed to pack
      }

      final bestRect = freeRectangles[bestIndex];

      // Place texture
      rects.add(_PackRect(
        x: bestRect.x + padding,
        y: bestRect.y + padding,
        width: texture.width,
        height: texture.height,
        textureId: texture.textureId,
      ));

      // Split the free rectangle using guillotine split
      // Remove the used rectangle
      freeRectangles.removeAt(bestIndex);

      // Add remaining space as new free rectangles
      // Right side
      final rightWidth = bestRect.width - width;
      if (rightWidth > 0) {
        freeRectangles.add(_FreeRect(
          bestRect.x + width,
          bestRect.y,
          rightWidth,
          height,
        ));
      }

      // Bottom side
      final bottomHeight = bestRect.height - height;
      if (bottomHeight > 0) {
        freeRectangles.add(_FreeRect(
          bestRect.x,
          bestRect.y + height,
          bestRect.width,
          bottomHeight,
        ));
      }
    }

    return rects;
  }

  /// Create the actual atlas image by compositing textures
  Future<ui.Image> _createAtlasImage(
    List<TextureInput> textures,
    List<_PackRect> rects,
    int atlasWidth,
    int atlasHeight,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Clear background
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, atlasWidth.toDouble(), atlasHeight.toDouble()),
      ui.Paint()..color = const ui.Color(0x00000000), // Transparent
    );

    // Draw each texture at its packed position
    final textureMap = <int, ui.Image>{};
    for (final texture in textures) {
      textureMap[texture.textureId] = texture.image;
    }

    for (final rect in rects) {
      final texture = textureMap[rect.textureId];
      if (texture != null) {
        canvas.drawImage(
          texture,
          ui.Offset(rect.x.toDouble(), rect.y.toDouble()),
          ui.Paint(),
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(atlasWidth, atlasHeight);
    picture.dispose();

    return image;
  }

  /// Get next power of 2
  int _nextPowerOfTwo(int value) {
    int result = 1;
    while (result < value) {
      result *= 2;
    }
    return result;
  }
}

/// Free rectangle for MaxRects algorithm
class _FreeRect {
  int x;
  int y;
  int width;
  int height;

  _FreeRect(this.x, this.y, this.width, this.height);
}
