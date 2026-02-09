import 'dart:math' show sqrt;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/core.dart';
import '../math/math.dart';
import '../components/drawable.dart' as puppet;
import 'render_ctx.dart';

/// Canvas-based renderer for puppets
class CanvasRenderer {
  final RenderCtx renderCtx;
  Camera camera;

  /// GPU fragment shader for mask thresholding (null = use ColorFilter fallback)
  ui.FragmentProgram? _maskShaderProgram;
  bool _shaderLoadAttempted = false;

  CanvasRenderer({
    required this.renderCtx,
    Camera? camera,
  }) : camera = camera ?? Camera();

  /// Load GPU shaders for improved mask thresholding.
  ///
  /// Falls back to ColorFilter-based thresholding if shader loading fails
  /// (e.g., in unit tests without GPU, or on unsupported platforms).
  Future<void> loadShaders() async {
    if (_shaderLoadAttempted) return;
    _shaderLoadAttempted = true;
    try {
      _maskShaderProgram = await ui.FragmentProgram.fromAsset(
        'packages/utsutsu2d/lib/src/render/shaders/mask_threshold.frag',
      );
      print('[CanvasRenderer] GPU mask threshold shader loaded');
    } catch (e) {
      print('[CanvasRenderer] Shader load failed, using ColorFilter fallback: $e');
      _maskShaderProgram = null;
    }
  }

  /// Render the puppet to a canvas
  void render(Canvas canvas, Size size, Puppet puppet) {
    canvas.save();

    // Apply camera transform
    final viewProjection = camera.viewProjectionMatrix(size.width, size.height);
    _applyMatrix(canvas, viewProjection, size);

    // Draw all drawables
    _drawAllDrawables(canvas, puppet);

    canvas.restore();
  }

  void _applyMatrix(Canvas canvas, Mat4 matrix, Size size) {
    // Center the canvas
    canvas.translate(size.width / 2, size.height / 2);

    // Apply zoom
    canvas.scale(camera.zoom, camera.zoom);

    // Apply rotation
    canvas.rotate(-camera.rotation);

    // Apply camera position
    canvas.translate(-camera.position.x, -camera.position.y);
  }

  /// Draw all drawables with proper blend modes
  /// clipToLower/sliceFromLower use srcATop/srcOut directly against the canvas
  void _drawAllDrawables(Canvas canvas, Puppet puppet) {
    for (final data in renderCtx.drawables) {
      _drawRenderable(canvas, data, puppet);
    }
  }

  void _drawRenderable(Canvas canvas, RenderData data, Puppet puppet) {
    switch (data.kind) {
      case DrawableKind.texturedMesh:
        _drawTexturedMesh(canvas, data);
        break;
      case DrawableKind.composite:
        _drawComposite(canvas, data, puppet);
        break;
      case DrawableKind.meshGroup:
        _drawMeshGroup(canvas, data, puppet);
        break;
    }
  }

  // Debug counter for logging
  static int _debugDrawCount = 0;
  static bool _debugLogged = false;

  void _drawTexturedMesh(Canvas canvas, RenderData data) {
    final mesh = data.mesh;
    final texturedMesh = data.texturedMesh;
    if (mesh == null) {
      if (!_debugLogged) print('[Render] mesh is null');
      return;
    }

    final vertices = data.deformedVertices ?? mesh.vertices;
    if (vertices.isEmpty) {
      if (!_debugLogged) print('[Render] vertices is empty');
      return;
    }

    // Get texture and atlas region if available
    ui.Image? texture;
    List<Vec2>? atlasUvs;
    if (texturedMesh?.albedoTextureId != null) {
      texture = renderCtx.getTexture(texturedMesh!.albedoTextureId!);

      // If using atlas, transform UVs
      final atlasRegion = renderCtx.getAtlasRegion(texturedMesh.albedoTextureId!);
      if (atlasRegion != null && mesh.uvs.isNotEmpty) {
        atlasUvs = mesh.uvs.map((uv) => atlasRegion.transformUV(uv)).toList();
      }
    }

    // Debug log first few draws
    if (_debugDrawCount < 3) {
      print(
          '[Render] Drawing mesh: vertices=${vertices.length}, uvs=${mesh.uvs.length}, indices=${mesh.indices.length}, texId=${texturedMesh?.albedoTextureId}, hasTexture=${texture != null}');
      _debugDrawCount++;
    }

    // Use actual blend mode (clipToLower uses srcATop to clip to previously drawn content)
    final blendMode = _convertBlendMode(data.drawable.blendMode);

    // Texture-aware masking: render mask sources to offscreen image, then
    // composite content against the mask using BlendMode.dstIn.
    // This respects texture alpha and maskThreshold, unlike path-based clipping.
    final hasMasks = data.drawable.hasMasks;
    if (hasMasks) {
      // 1. Compute bounding box of the drawable in world space
      final drawableBounds = _computeTransformedBounds(vertices, data.transform);

      // Expand bounds to include mask sources
      var combinedBounds = drawableBounds;
      for (final mask in data.drawable.masks!) {
        final sourceData = renderCtx.getRenderData(mask.sourceNodeId);
        if (sourceData == null || sourceData.mesh == null) continue;
        final sourceVerts = sourceData.deformedVertices ?? sourceData.mesh!.vertices;
        if (sourceVerts.isEmpty) continue;
        final maskBounds = _computeTransformedBounds(sourceVerts, sourceData.transform);
        combinedBounds = combinedBounds.expandToInclude(maskBounds);
      }

      final width = combinedBounds.width.ceil();
      final height = combinedBounds.height.ceil();
      if (width <= 0 || height <= 0) return;

      // 2. Render combined mask image offscreen
      final maskImage = _renderMaskImage(
        data.drawable.masks!,
        data.drawable.maskThreshold ?? 0.0,
        combinedBounds,
      );
      if (maskImage == null) {
        // No valid mask sources — draw content without masking
        _drawTexturedMeshContent(canvas, data, vertices, texture, atlasUvs, blendMode);
        return;
      }

      // 3. Render the drawable content to a saveLayer, then apply mask via dstIn
      canvas.save();
      final layerPaint = Paint()..blendMode = blendMode;
      canvas.saveLayer(combinedBounds, layerPaint);

      // Draw the actual content
      canvas.save();
      _applyNodeTransform(canvas, data.transform);
      if (texture != null) {
        final uvs = atlasUvs ?? mesh.uvs;
        _drawTexturedMeshWithBlending(
          canvas, vertices, uvs, mesh.indices, texture,
          BlendMode.srcOver, data.drawable.opacity,
        );
      } else {
        _drawWireframe(canvas, vertices, mesh.indices);
      }
      canvas.restore();

      // 4. Apply mask using dstIn (keeps content only where mask is opaque)
      canvas.drawImage(
        maskImage,
        Offset(combinedBounds.left, combinedBounds.top),
        Paint()..blendMode = BlendMode.dstIn,
      );
      canvas.restore(); // restore saveLayer
      canvas.restore(); // restore save

      maskImage.dispose();
    } else {
      _drawTexturedMeshContent(canvas, data, vertices, texture, atlasUvs, blendMode);
    }
  }

  /// Draw textured mesh content without masking
  void _drawTexturedMeshContent(
    Canvas canvas,
    RenderData data,
    List<Vec2> vertices,
    ui.Image? texture,
    List<Vec2>? atlasUvs,
    BlendMode blendMode,
  ) {
    canvas.save();
    _applyNodeTransform(canvas, data.transform);

    if (texture != null) {
      final uvs = atlasUvs ?? data.mesh!.uvs;

      // Fix for Issue #8: Unwanted shadow artifacts from triangle overlap
      //
      // When rendering triangles with blend modes like multiply or screen,
      // overlapping triangles within the same mesh blend with each other,
      // creating unwanted dark areas (shadows) at seams. This is especially
      // visible around mouth, eyes, face edges, and hair patterns.
      //
      // Solution: Always render to offscreen buffer first with normal blending,
      // then composite the entire mesh onto the canvas with the desired blend mode.
      // This ensures triangles don't blend with each other, only with the background.
      if (data.drawable.blendMode != puppet.BlendMode.normal) {
        _drawTexturedMeshWithBlending(
          canvas,
          vertices,
          uvs,
          data.mesh!.indices,
          texture,
          blendMode,
          data.drawable.opacity,
        );
      } else {
        // For normal blend mode without masks, render directly
        final paint = Paint()
          ..blendMode = BlendMode.srcOver
          ..color = Colors.white.withOpacity(data.drawable.opacity)
          ..filterQuality = FilterQuality.high;
        _drawTexturedTriangles(
          canvas,
          vertices,
          uvs,
          data.mesh!.indices,
          texture,
          paint,
        );
      }
    } else {
      _drawWireframe(canvas, vertices, data.mesh!.indices);
      if (!_debugLogged) {
        print(
            '[Render] No texture for texId=${data.texturedMesh?.albedoTextureId}, drawing wireframe');
        _debugLogged = true;
      }
    }

    canvas.restore();
  }

  /// Draw textured mesh with blend mode by rendering to offscreen buffer first.
  ///
  /// This method prevents triangle overlap artifacts by:
  /// 1. Rendering all triangles to an offscreen canvas with normal blending
  /// 2. Converting the result to a picture
  /// 3. Compositing the picture onto the main canvas with the desired blend mode
  ///
  /// This ensures triangles within the mesh don't blend with each other,
  /// eliminating unwanted shadow artifacts at triangle seams.
  void _drawTexturedMeshWithBlending(
    Canvas canvas,
    List<Vec2> vertices,
    List<Vec2> uvs,
    List<int> indices,
    ui.Image texture,
    BlendMode blendMode,
    double opacity,
  ) {
    // Debug: log opacity values to understand the issue
    if (blendMode == BlendMode.multiply && opacity != 1.0) {
      print('[DEBUG] multiply blend with opacity=$opacity');
    }

    // Calculate bounding box for the mesh
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final v in vertices) {
      if (v.x < minX) minX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.x > maxX) maxX = v.x;
      if (v.y > maxY) maxY = v.y;
    }

    final width = (maxX - minX).ceil();
    final height = (maxY - minY).ceil();

    if (width <= 0 || height <= 0) return;

    // Create offscreen picture recorder
    final recorder = ui.PictureRecorder();
    final offscreenCanvas = Canvas(recorder);

    // Translate to make coordinates relative to bounding box
    offscreenCanvas.save();
    offscreenCanvas.translate(-minX, -minY);

    // Render triangles with normal blending to offscreen canvas
    // Do NOT apply opacity here - it will be applied at composite time
    final trianglePaint = Paint()
      ..blendMode = BlendMode.srcOver
      ..filterQuality = FilterQuality.high;

    _drawTexturedTriangles(
      offscreenCanvas,
      vertices,
      uvs,
      indices,
      texture,
      trianglePaint,
    );

    offscreenCanvas.restore();

    // Finish recording
    final picture = recorder.endRecording();

    // Draw the offscreen picture to main canvas with blend mode and opacity
    canvas.save();
    canvas.translate(minX, minY);

    final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

    // Create a paint with blend mode and opacity
    final paint = Paint()
      ..blendMode = blendMode
      ..color = Colors.white.withOpacity(opacity);

    canvas.saveLayer(bounds, paint);
    canvas.drawPicture(picture);
    canvas.restore(); // restore layer
    canvas.restore(); // restore translate

    picture.dispose();
  }

  void _drawTexturedTriangles(
    Canvas canvas,
    List<Vec2> vertices,
    List<Vec2> uvs,
    List<int> indices,
    ui.Image texture,
    Paint paint,
  ) {
    if (indices.length < 3) return;

    // Draw textured mesh using affine-transformed texture per triangle
    for (int i = 0; i < indices.length; i += 3) {
      if (i + 2 >= indices.length) break;

      final i0 = indices[i];
      final i1 = indices[i + 1];
      final i2 = indices[i + 2];

      if (i0 >= vertices.length ||
          i1 >= vertices.length ||
          i2 >= vertices.length) {
        continue;
      }

      _drawTexturedTriangle(
        canvas,
        vertices[i0],
        vertices[i1],
        vertices[i2],
        uvs[i0],
        uvs[i1],
        uvs[i2],
        texture,
        paint,
      );
    }
  }

  void _drawTexturedTriangle(
    Canvas canvas,
    Vec2 v0,
    Vec2 v1,
    Vec2 v2,
    Vec2 uv0,
    Vec2 uv1,
    Vec2 uv2,
    ui.Image texture,
    Paint paint,
  ) {
    canvas.save();

    // Expand clip path vertices by sub-pixel epsilon to close gaps between
    // adjacent triangles. This prevents jagged "tooth" artifacts at triangle
    // seams, especially visible in hair highlights (Issue #118).
    // Only the clip path is expanded — texture coordinates remain unchanged.
    const epsilon = 0.5;
    final cx = (v0.x + v1.x + v2.x) / 3.0;
    final cy = (v0.y + v1.y + v2.y) / 3.0;
    final ev0 = expandVertex(v0.x, v0.y, cx, cy, epsilon);
    final ev1 = expandVertex(v1.x, v1.y, cx, cy, epsilon);
    final ev2 = expandVertex(v2.x, v2.y, cx, cy, epsilon);

    final path = Path();
    path.moveTo(ev0.dx, ev0.dy);
    path.lineTo(ev1.dx, ev1.dy);
    path.lineTo(ev2.dx, ev2.dy);
    path.close();

    canvas.clipPath(path);

    // Calculate affine transform from UV coordinates to screen coordinates
    // We need to solve for the transformation that maps:
    // uv0 -> v0, uv1 -> v1, uv2 -> v2
    // This is done using inverse matrix calculation

    final x0 = v0.x, y0 = v0.y;
    final x1 = v1.x, y1 = v1.y;
    final x2 = v2.x, y2 = v2.y;

    final u0 = uv0.x, v0_ = uv0.y;
    final u1 = uv1.x, v1_ = uv1.y;
    final u2 = uv2.x, v2_ = uv2.y;

    // Compute determinant of UV basis
    final detUV = u0 * (v1_ - v2_) + u1 * (v2_ - v0_) + u2 * (v0_ - v1_);
    if (detUV.abs() < 1e-8) {
      canvas.restore();
      return;
    }

    // Compute transformation coefficients
    // Screen = [ a b c ] [ UV ]
    //          [ d e f ] [ 1  ]
    final a =
        (x0 * (v1_ - v2_) + x1 * (v2_ - v0_) + x2 * (v0_ - v1_)) / detUV;
    final b = (x0 * (u2 - u1) + x1 * (u0 - u2) + x2 * (u1 - u0)) / detUV;
    final c = (x0 * (u1 * v2_ - u2 * v1_) +
            x1 * (u2 * v0_ - u0 * v2_) +
            x2 * (u0 * v1_ - u1 * v0_)) /
        detUV;

    final d =
        (y0 * (v1_ - v2_) + y1 * (v2_ - v0_) + y2 * (v0_ - v1_)) / detUV;
    final e = (y0 * (u2 - u1) + y1 * (u0 - u2) + y2 * (u1 - u0)) / detUV;
    final f = (y0 * (u1 * v2_ - u2 * v1_) +
            y1 * (u2 * v0_ - u0 * v2_) +
            y2 * (u0 * v1_ - u1 * v0_)) /
        detUV;

    // Scale to convert from texture pixel coordinates to UV coordinates
    // The affine matrix transforms UV coordinates (0-1) to screen coordinates
    // Since canvas.drawImage() uses pixel coordinates, we need to normalize them
    // pixel_coord / dimension = UV coordinate (0-1 range)
    // Therefore: a' = a / width, b' = b / height, etc.
    final scaleX = 1.0 / texture.width.toDouble();
    final scaleY = 1.0 / texture.height.toDouble();

    // Build transformation matrix (column-major for Flutter)
    // [0]  [4]  [8]  [12]    [scaleX*a  scaleY*b  0  c]
    // [1]  [5]  [9]  [13] =  [scaleX*d  scaleY*e  0  f]
    // [2]  [6]  [10] [14]    [0         0         1  0]
    // [3]  [7]  [11] [15]    [0         0         0  1]
    final matrix = Float64List(16);
    matrix[0] = a * scaleX;
    matrix[1] = d * scaleX;
    matrix[4] = b * scaleY;
    matrix[5] = e * scaleY;
    matrix[12] = c;
    matrix[13] = f;
    matrix[10] = 1.0;
    matrix[15] = 1.0;

    // Apply transform and draw texture
    canvas.transform(matrix);
    canvas.drawImage(texture, Offset.zero, paint);

    canvas.restore();
  }

  void _drawWireframe(Canvas canvas, List<Vec2> vertices, List<int> indices) {
    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();

    for (int i = 0; i < indices.length; i += 3) {
      if (i + 2 >= indices.length) break;

      final i0 = indices[i];
      final i1 = indices[i + 1];
      final i2 = indices[i + 2];

      if (i0 >= vertices.length ||
          i1 >= vertices.length ||
          i2 >= vertices.length) {
        continue;
      }

      final v0 = vertices[i0];
      final v1 = vertices[i1];
      final v2 = vertices[i2];

      path.moveTo(v0.x, v0.y);
      path.lineTo(v1.x, v1.y);
      path.lineTo(v2.x, v2.y);
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  void _drawComposite(Canvas canvas, RenderData data, Puppet puppet) {
    final children = renderCtx.getCompositeChildDrawables(data.nodeId);
    if (children.isEmpty) return;

    // Compute bounding box of all children
    var bounds = Rect.zero;
    bool hasBounds = false;
    for (final child in children) {
      if (child.mesh == null) continue;
      final verts = child.deformedVertices ?? child.mesh!.vertices;
      if (verts.isEmpty) continue;
      final childBounds = _computeTransformedBounds(verts, child.transform);
      if (!hasBounds) {
        bounds = childBounds;
        hasBounds = true;
      } else {
        bounds = bounds.expandToInclude(childBounds);
      }
    }
    if (!hasBounds) return;

    // Apply composite blend mode and opacity via saveLayer
    final blendMode = _convertBlendMode(data.drawable.blendMode);
    final paint = Paint()
      ..blendMode = blendMode
      ..color = Color.fromRGBO(255, 255, 255, data.drawable.opacity);
    canvas.saveLayer(bounds, paint);

    // Sort children by z-order if composite requests it
    final sortedChildren = List<RenderData>.from(children);
    if (data.composite?.sortByZOrder == true) {
      final zsortCtx = puppet.zsortCtx;
      sortedChildren.sort((a, b) {
        final za = zsortCtx?.getZSort(a.nodeId) ?? 0;
        final zb = zsortCtx?.getZSort(b.nodeId) ?? 0;
        return zb.compareTo(za); // Descending: larger z drawn first
      });
    }

    // Draw each child
    for (final child in sortedChildren) {
      _drawRenderable(canvas, child, puppet);
    }

    canvas.restore();
  }

  /// Draw a MeshGroup node.
  ///
  /// Unlike Composite (which renders to an offscreen buffer via saveLayer),
  /// MeshGroup directly renders child drawables to the canvas. Children
  /// share the group's opacity and are optionally sorted by z-order.
  void _drawMeshGroup(Canvas canvas, RenderData data, Puppet puppet) {
    final children = renderCtx.getMeshGroupChildDrawables(data.nodeId);
    if (children.isEmpty) return;

    final meshGroup = data.meshGroup;
    final groupOpacity = meshGroup?.opacity ?? 1.0;

    // Sort children by z-order if requested
    final sortedChildren = List<RenderData>.from(children);
    if (meshGroup?.sortByZOrder == true) {
      final zsortCtx = puppet.zsortCtx;
      sortedChildren.sort((a, b) {
        final za = zsortCtx?.getZSort(a.nodeId) ?? 0;
        final zb = zsortCtx?.getZSort(b.nodeId) ?? 0;
        return zb.compareTo(za); // Descending: larger z drawn first
      });
    }

    // If group opacity is less than 1.0, use saveLayer to apply it
    if (groupOpacity < 1.0) {
      final paint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, groupOpacity);
      canvas.saveLayer(null, paint);
    }

    // Draw each child directly to the canvas
    for (final child in sortedChildren) {
      _drawRenderable(canvas, child, puppet);
    }

    if (groupOpacity < 1.0) {
      canvas.restore();
    }
  }

  /// Compute axis-aligned bounding box for vertices after applying transform
  Rect _computeTransformedBounds(List<Vec2> vertices, Mat4 transform) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final v in vertices) {
      final t = transform.transformPoint2D(v);
      if (t.x < minX) minX = t.x;
      if (t.y < minY) minY = t.y;
      if (t.x > maxX) maxX = t.x;
      if (t.y > maxY) maxY = t.y;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Render mask sources to an offscreen image that respects texture alpha.
  ///
  /// For each mask source, renders its textured mesh to an offscreen canvas.
  /// The texture's alpha channel naturally provides the mask shape.
  /// Pixels with alpha <= threshold are zeroed out.
  /// For dodge mode, the alpha is inverted (transparent becomes opaque).
  ///
  /// Multiple masks are intersected: the combined mask is opaque only where
  /// ALL mask sources agree.
  ui.Image? _renderMaskImage(
    List<puppet.Mask> masks,
    double threshold,
    Rect bounds,
  ) {
    final width = bounds.width.ceil();
    final height = bounds.height.ceil();
    if (width <= 0 || height <= 0) return null;

    // Render each mask source and combine them via intersection
    ui.Image? combinedMask;

    for (final mask in masks) {
      final sourceData = renderCtx.getRenderData(mask.sourceNodeId);
      if (sourceData == null || sourceData.mesh == null) continue;

      final sourceVertices =
          sourceData.deformedVertices ?? sourceData.mesh!.vertices;
      if (sourceVertices.isEmpty) continue;

      // Get mask source texture
      ui.Image? sourceTexture;
      List<Vec2>? sourceAtlasUvs;
      if (sourceData.texturedMesh?.albedoTextureId != null) {
        sourceTexture =
            renderCtx.getTexture(sourceData.texturedMesh!.albedoTextureId!);
        final atlasRegion = renderCtx
            .getAtlasRegion(sourceData.texturedMesh!.albedoTextureId!);
        if (atlasRegion != null && sourceData.mesh!.uvs.isNotEmpty) {
          sourceAtlasUvs = sourceData.mesh!.uvs
              .map((uv) => atlasRegion.transformUV(uv))
              .toList();
        }
      }
      if (sourceTexture == null) continue;

      final uvs = sourceAtlasUvs ?? sourceData.mesh!.uvs;

      // Render mask source to offscreen canvas
      final recorder = ui.PictureRecorder();
      final offCanvas = Canvas(recorder);

      // Translate so that bounds.topLeft maps to (0,0)
      offCanvas.translate(-bounds.left, -bounds.top);

      // Apply mask source's node transform
      _applyNodeTransform(offCanvas, sourceData.transform);

      // Render the textured mesh with normal blending
      final paint = Paint()
        ..blendMode = BlendMode.srcOver
        ..filterQuality = FilterQuality.high;
      _drawTexturedTriangles(
        offCanvas,
        sourceVertices,
        uvs,
        sourceData.mesh!.indices,
        sourceTexture,
        paint,
      );

      final picture = recorder.endRecording();
      final maskImage = picture.toImageSync(width, height);
      picture.dispose();

      // Apply threshold: zero out pixels where alpha <= threshold.
      // We do this by drawing the mask image into a new canvas and using
      // a color filter that converts the alpha channel into a binary mask.
      //
      // For dodge mode, invert the result.
      final thresholdedImage = _applyThresholdToImage(
        maskImage,
        threshold,
        width,
        height,
        invert: mask.mode == puppet.MaskMode.dodge,
      );
      maskImage.dispose();

      if (combinedMask == null) {
        combinedMask = thresholdedImage;
      } else {
        // Intersect: keep only where both masks are opaque (dstIn)
        final recorder2 = ui.PictureRecorder();
        final combCanvas = Canvas(recorder2);
        combCanvas.drawImage(combinedMask, Offset.zero, Paint());
        combCanvas.drawImage(
          thresholdedImage,
          Offset.zero,
          Paint()..blendMode = BlendMode.dstIn,
        );
        final picture2 = recorder2.endRecording();
        combinedMask.dispose();
        thresholdedImage.dispose();
        combinedMask = picture2.toImageSync(width, height);
        picture2.dispose();
      }
    }

    return combinedMask;
  }

  /// Apply alpha threshold to a mask image.
  ///
  /// Creates a new image where:
  /// - Pixels with alpha > threshold become fully opaque white
  /// - Pixels with alpha <= threshold become fully transparent
  ///
  /// If [invert] is true (dodge mode), the logic is reversed.
  ///
  /// Uses GPU fragment shader when available for sharp step-function cutoff,
  /// falling back to ColorFilter.matrix approximation otherwise.
  ui.Image _applyThresholdToImage(
    ui.Image source,
    double threshold,
    int width,
    int height, {
    bool invert = false,
  }) {
    if (_maskShaderProgram != null) {
      return _applyThresholdWithShader(source, threshold, width, height, invert: invert);
    }
    return _applyThresholdWithColorFilter(source, threshold, width, height, invert: invert);
  }

  /// GPU path: apply threshold using fragment shader with step function.
  ui.Image _applyThresholdWithShader(
    ui.Image source,
    double threshold,
    int width,
    int height, {
    bool invert = false,
  }) {
    final shader = _maskShaderProgram!.fragmentShader();

    // Set uniforms: threshold (0), invert (1), iSize (2, 3)
    shader.setFloat(0, threshold);
    shader.setFloat(1, invert ? 1.0 : 0.0);
    shader.setFloat(2, width.toDouble());
    shader.setFloat(3, height.toDouble());

    // Set sampler: source image at index 0
    shader.setImageSampler(0, source);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..shader = shader,
    );

    final picture = recorder.endRecording();
    final result = picture.toImageSync(width, height);
    picture.dispose();
    shader.dispose();
    return result;
  }

  /// CPU fallback: apply threshold using ColorFilter.matrix approximation.
  ui.Image _applyThresholdWithColorFilter(
    ui.Image source,
    double threshold,
    int width,
    int height, {
    bool invert = false,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (threshold <= 0.0 && !invert) {
      // No threshold needed — just convert to alpha-only mask
      // Use color matrix to set RGB to white, keep alpha as-is
      final paint = Paint()
        ..colorFilter = const ColorFilter.matrix(<double>[
          0, 0, 0, 0, 255, // R = 255
          0, 0, 0, 0, 255, // G = 255
          0, 0, 0, 0, 255, // B = 255
          0, 0, 0, 1, 0, // A = source alpha
        ]);
      canvas.drawImage(source, Offset.zero, paint);
    } else {
      // Apply threshold by boosting alpha contrast.
      // We scale alpha so that values <= threshold map to 0,
      // and values > threshold map toward 1.
      //
      // newAlpha = clamp((oldAlpha - threshold) / (1 - threshold), 0, 1)
      // In color matrix terms: A_out = A_in * scale + offset
      //   scale = 1 / (1 - threshold)
      //   offset = -threshold / (1 - threshold) * 255
      final scale = threshold >= 1.0 ? 255.0 : 1.0 / (1.0 - threshold);
      final offset = threshold >= 1.0 ? -255.0 : -threshold * 255.0 / (1.0 - threshold);

      if (!invert) {
        final paint = Paint()
          ..colorFilter = ColorFilter.matrix(<double>[
            0, 0, 0, 0, 255, // R = 255
            0, 0, 0, 0, 255, // G = 255
            0, 0, 0, 0, 255, // B = 255
            0, 0, 0, scale, offset, // A = scaled + offset
          ]);
        canvas.drawImage(source, Offset.zero, paint);
      } else {
        // Dodge mode: invert alpha
        // newAlpha = clamp(1 - (oldAlpha - threshold) / (1 - threshold), 0, 1)
        //          = clamp((-oldAlpha + 1) / (1 - threshold), 0, 1)
        // A_out = A_in * (-scale) + (255 - offset) effectively
        final invertScale = -scale;
        final invertOffset = 255.0 + offset * -1.0;

        final paint = Paint()
          ..colorFilter = ColorFilter.matrix(<double>[
            0, 0, 0, 0, 255, // R = 255
            0, 0, 0, 0, 255, // G = 255
            0, 0, 0, 0, 255, // B = 255
            0, 0, 0, invertScale, invertOffset, // A = inverted
          ]);
        canvas.drawImage(source, Offset.zero, paint);
      }
    }

    final picture = recorder.endRecording();
    final result = picture.toImageSync(width, height);
    picture.dispose();
    return result;
  }

  void _applyNodeTransform(Canvas canvas, Mat4 transform) {
    // Apply the full transformation matrix using Flutter's Matrix4
    // This correctly handles all transformation components including rotation
    //
    // For sideways rendering (Y-axis rotation), Canvas 2D doesn't support
    // true 3D perspective. We simulate it by applying the transform matrix
    // which includes the rotation, and Canvas will handle it as a 2D affine
    // transformation. The Y-rotation is already encoded in the matrix.
    final matrix4 = Float64List(16);
    for (int i = 0; i < 16; i++) {
      matrix4[i] = transform[i];
    }
    canvas.transform(matrix4);
  }

  /// Expand vertex position away from centroid by [epsilon] pixels.
  ///
  /// Used to close sub-pixel gaps between adjacent clip-path triangles
  /// that cause jagged "tooth" artifacts in hair highlights (Issue #118).
  /// Only the clip path is expanded; texture coordinates remain unchanged.
  @visibleForTesting
  static Offset expandVertex(
      double vx, double vy, double cx, double cy, double epsilon) {
    final dx = vx - cx;
    final dy = vy - cy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1e-10) return Offset(vx, vy);
    return Offset(
      vx + dx / len * epsilon,
      vy + dy / len * epsilon,
    );
  }

  /// Convert blend mode to Flutter BlendMode
  BlendMode _convertBlendMode(puppet.BlendMode mode) {
    switch (mode) {
      case puppet.BlendMode.normal:
        return BlendMode.srcOver;
      case puppet.BlendMode.multiply:
        return BlendMode.multiply;
      case puppet.BlendMode.colorDodge:
        return BlendMode.colorDodge;
      case puppet.BlendMode.linearDodge:
        return BlendMode.plus;
      case puppet.BlendMode.screen:
        return BlendMode.screen;
      case puppet.BlendMode.clipToLower:
        // srcATop: draws source where destination is opaque, preserving destination color beneath
        return BlendMode.srcATop;
      case puppet.BlendMode.sliceFromLower:
        // srcOut: draws source where destination is transparent
        return BlendMode.srcOut;
      case puppet.BlendMode.lighten:
        return BlendMode.lighten;
      case puppet.BlendMode.addGlow:
        return BlendMode.plus;
      case puppet.BlendMode.subtract:
        // Approximation: difference gives a similar visual effect
        return BlendMode.difference;
      case puppet.BlendMode.overlay:
        return BlendMode.overlay;
      case puppet.BlendMode.darken:
        return BlendMode.darken;
      case puppet.BlendMode.difference:
        return BlendMode.difference;
      case puppet.BlendMode.exclusion:
        return BlendMode.exclusion;
      case puppet.BlendMode.colorBurn:
        return BlendMode.colorBurn;
      case puppet.BlendMode.hardLight:
        return BlendMode.hardLight;
      case puppet.BlendMode.softLight:
        return BlendMode.softLight;
      case puppet.BlendMode.inverse:
        // Approximation: xor provides an inverting effect
        return BlendMode.xor;
      case puppet.BlendMode.destinationIn:
        return BlendMode.dstIn;
    }
  }
}
