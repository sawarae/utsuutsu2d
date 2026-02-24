import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dart_psd_tool/dart_psd_tool.dart';
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

  /// PSDTool-compatible GPU compositor (null = use Flutter built-in BlendMode)
  PsdCanvasCompositor? psdCompositor;

  /// Device pixel ratio for Retina-aware offscreen buffer sizing.
  ///
  /// The PSD compositor creates offscreen images via [toImageSync] which
  /// don't inherit the canvas DPR transform. Set this to the display's
  /// device pixel ratio so buffers are created at full resolution.
  /// Defaults to 1.0 (no scaling).
  double devicePixelRatio = 1.0;

  bool _shaderLoadAttempted = false;

  /// When true, draw a wireframe overlay on top of the rendered puppet.
  bool showMeshOverlay = false;

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
    } catch (e) {
      _maskShaderProgram = null;
    }
    try {
      psdCompositor = await PsdCanvasCompositor.create();
    } catch (e) {
      psdCompositor = null;
    }
  }

  /// Render the puppet to a canvas
  void render(Canvas canvas, Size size, Puppet puppet) {
    canvas.save();

    if (psdCompositor != null) {
      // PSD-accurate compositing: running buffer with shader blending.
      // Camera transform is applied internally per-picture.
      _renderWithPsdCompositor(canvas, size, puppet);
    } else {
      // Fast path: Flutter built-in blend modes (approximate).
      final viewProjection =
          camera.viewProjectionMatrix(size.width, size.height);
      _applyMatrix(canvas, viewProjection, size);

      // Isolate puppet rendering in a transparent compositing layer.
      // Without this, drawables with multiply (or other) blend modes that
      // are not inside a Composite node blend directly against the canvas
      // background (e.g. gray), producing incorrect colors (Issue #4).
      canvas.saveLayer(null, Paint());
      _drawAllDrawables(canvas, puppet);
      canvas.restore();
    }

    canvas.restore();

    if (showMeshOverlay) {
      _drawMeshOverlayPass(canvas, size);
    }
  }

  /// Draw wireframe overlay for all visible drawables.
  void _drawMeshOverlayPass(Canvas canvas, Size size) {
    canvas.save();
    _applyMatrix(
        canvas, camera.viewProjectionMatrix(size.width, size.height), size);
    for (final data in renderCtx.drawables) {
      if (renderCtx.isNodeHidden(data.nodeId)) continue;
      final mesh = data.mesh;
      if (mesh == null) continue;
      final vertices = data.deformedVertices ?? mesh.vertices;
      if (vertices.isEmpty) continue;
      canvas.save();
      _applyNodeTransform(canvas, data.transform);
      _drawWireframe(canvas, vertices, mesh.indices);
      canvas.restore();
    }
    canvas.restore();
  }

  /// PSD-accurate rendering using a running buffer and shader compositing.
  ///
  /// Maintains a screen-space image buffer. Normal-blend drawables are
  /// accumulated in a batch (PictureRecorder). When a non-normal textured
  /// mesh is encountered, the batch is flushed and the mesh is composited
  /// using the PSD fragment shader for exact 3-component alpha blending.
  void _renderWithPsdCompositor(Canvas targetCanvas, Size size, Puppet puppet) {
    final dpr = devicePixelRatio;
    final pw = (size.width * dpr).ceil();
    final ph = (size.height * dpr).ceil();
    if (pw <= 0 || ph <= 0) return;

    // Running destination image (screen space, accumulates composited content).
    // All offscreen images are created at pixel dimensions (logical × DPR)
    // to avoid resolution loss on Retina displays.
    ui.Image? runningDst;

    // Batch management: accumulate normal drawables
    ui.PictureRecorder? batchRec;
    Canvas? batchCvs;
    bool batchDirty = false;

    void startBatch() {
      batchRec = ui.PictureRecorder();
      batchCvs = Canvas(batchRec!);
      // Scale to match display pixel density
      batchCvs!.scale(dpr, dpr);
      // Draw existing content as base so blend modes within the batch
      // interact with all prior content correctly.
      if (runningDst != null) {
        batchCvs!.save();
        batchCvs!.scale(1 / dpr, 1 / dpr);
        batchCvs!.drawImage(runningDst!, Offset.zero, Paint());
        batchCvs!.restore();
      }
      // Apply camera transform for subsequent world-space drawing
      _applyMatrix(batchCvs!,
          camera.viewProjectionMatrix(size.width, size.height), size);
      // Isolate new drawing in a saveLayer (same as fast path) so blend
      // modes don't interact with the runningDst base image directly.
      if (runningDst != null) {
        batchCvs!.saveLayer(null, Paint());
      }
      batchDirty = false;
    }

    void flushBatch() {
      if (batchRec == null) return;
      if (!batchDirty && runningDst != null) {
        // Nothing new was drawn; discard recorder
        if (runningDst != null) batchCvs!.restore(); // saveLayer
        batchRec!.endRecording().dispose();
        batchRec = null;
        batchCvs = null;
        return;
      }
      if (runningDst != null) batchCvs!.restore(); // saveLayer
      final picture = batchRec!.endRecording();
      final batchImage = picture.toImageSync(pw, ph);
      picture.dispose();
      batchRec = null;
      batchCvs = null;
      // The batch already includes runningDst as base → replace
      runningDst?.dispose();
      runningDst = batchImage;
    }

    startBatch();

    for (final data in renderCtx.drawables) {
      if (renderCtx.isNodeHidden(data.nodeId)) continue;

      if (_needsPsdShaderPath(data)) {
        // Flush any accumulated normal drawables
        flushBatch();

        // Render mesh content to image (normal blend, full opacity)
        final srcImage = _renderMeshContentToImage(data, size, pw, ph);
        if (srcImage == null) {
          startBatch();
          continue;
        }

        // Ensure dst exists
        runningDst ??= _createTransparentImage(pw, ph);

        // PSD shader composite
        final compRec = ui.PictureRecorder();
        final compCvs = Canvas(compRec);
        psdCompositor!.composite(
          compCvs,
          srcImage,
          runningDst!,
          Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble()),
          opacity: data.drawable.opacity,
          blendMode: _puppetBlendModeToPsdString(data.drawable.blendMode),
        );
        final compPicture = compRec.endRecording();
        final composited = compPicture.toImageSync(pw, ph);
        compPicture.dispose();
        runningDst!.dispose();
        srcImage.dispose();
        runningDst = composited;

        // Start new batch (with updated runningDst as base)
        startBatch();
      } else {
        // Normal path: draw to batch
        _drawRenderable(batchCvs!, data, puppet);
        batchDirty = true;
      }
    }

    // Flush final batch
    flushBatch();

    // Draw final result to target canvas (screen space).
    // Undo the DPR scale on the target canvas so the pixel-sized image
    // maps 1:1 to actual display pixels.
    if (runningDst != null) {
      targetCanvas.save();
      targetCanvas.scale(1 / dpr, 1 / dpr);
      targetCanvas.drawImage(runningDst!, Offset.zero, Paint());
      targetCanvas.restore();
      runningDst!.dispose();
    }
  }

  /// Whether this drawable should use the PSD shader compositing path.
  bool _needsPsdShaderPath(RenderData data) {
    if (psdCompositor == null) return false;
    if (data.kind != DrawableKind.texturedMesh) return false;
    if (data.drawable.hasMasks) return false;
    final mode = data.drawable.blendMode;
    if (mode == puppet.BlendMode.normal) return false;
    // Inochi2d-specific modes without PSD equivalent — use Flutter built-in
    if (mode == puppet.BlendMode.clipToLower ||
        mode == puppet.BlendMode.sliceFromLower ||
        mode == puppet.BlendMode.destinationIn ||
        mode == puppet.BlendMode.inverse ||
        mode == puppet.BlendMode.exclusion ||
        mode == puppet.BlendMode.addGlow) return false;
    return true;
  }

  /// Render a textured mesh to a screen-space image without blend mode.
  ///
  /// The mesh is drawn with normal blending and full opacity. The PSD shader
  /// handles blend mode and opacity during compositing.
  ui.Image? _renderMeshContentToImage(
      RenderData data, Size size, int pw, int ph) {
    final mesh = data.mesh;
    if (mesh == null) return null;
    final vertices = data.deformedVertices ?? mesh.vertices;
    if (vertices.isEmpty) return null;

    // Get texture and atlas UVs
    ui.Image? texture;
    List<Vec2>? atlasUvs;
    if (data.texturedMesh?.albedoTextureId != null) {
      texture = renderCtx.getTexture(data.texturedMesh!.albedoTextureId!);
      final atlasRegion =
          renderCtx.getAtlasRegion(data.texturedMesh!.albedoTextureId!);
      if (atlasRegion != null && mesh.uvs.isNotEmpty) {
        atlasUvs = mesh.uvs.map((uv) => atlasRegion.transformUV(uv)).toList();
      }
    }
    if (texture == null) return null;

    final uvs = atlasUvs ?? mesh.uvs;

    // Render to offscreen image with camera + node transform.
    // Scale by DPR so the image matches pixel dimensions.
    final dpr = devicePixelRatio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr, dpr);
    _applyMatrix(
        canvas, camera.viewProjectionMatrix(size.width, size.height), size);
    canvas.save();
    _applyNodeTransform(canvas, data.transform);

    // Use offscreen buffer path to prevent triangle overlap,
    // with normal blend and full opacity (shader handles these)
    _drawTexturedMeshWithBlending(
      canvas,
      vertices,
      uvs,
      mesh.indices,
      texture,
      BlendMode.srcOver,
      1.0,
    );

    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(pw, ph);
    picture.dispose();
    return image;
  }

  /// Create a transparent image of the given dimensions.
  static ui.Image _createTransparentImage(int w, int h) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder); // empty canvas → transparent
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    return image;
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
    // Skip rendering if the node is hidden via visibility override.
    if (renderCtx.isNodeHidden(data.nodeId)) return;
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

  void _drawTexturedMesh(Canvas canvas, RenderData data) {
    final mesh = data.mesh;
    final texturedMesh = data.texturedMesh;
    if (mesh == null) return;

    final vertices = data.deformedVertices ?? mesh.vertices;
    if (vertices.isEmpty) return;

    // Get texture and atlas region if available
    ui.Image? texture;
    List<Vec2>? atlasUvs;
    if (texturedMesh?.albedoTextureId != null) {
      texture = renderCtx.getTexture(texturedMesh!.albedoTextureId!);

      // If using atlas, transform UVs
      final atlasRegion =
          renderCtx.getAtlasRegion(texturedMesh.albedoTextureId!);
      if (atlasRegion != null && mesh.uvs.isNotEmpty) {
        atlasUvs = mesh.uvs.map((uv) => atlasRegion.transformUV(uv)).toList();
      }
    }

    // Use actual blend mode (clipToLower uses srcATop to clip to previously drawn content)
    final blendMode = _convertBlendMode(data.drawable.blendMode);

    // Texture-aware masking: render mask sources to offscreen image, then
    // composite content against the mask using BlendMode.dstIn.
    // This respects texture alpha and maskThreshold, unlike path-based clipping.
    final hasMasks = data.drawable.hasMasks;
    if (hasMasks) {
      // 1. Compute bounding box of the drawable in world space
      final drawableBounds =
          _computeTransformedBounds(vertices, data.transform);

      // Expand bounds to include mask sources
      var combinedBounds = drawableBounds;
      for (final mask in data.drawable.masks!) {
        final sourceData = renderCtx.getRenderData(mask.sourceNodeId);
        if (sourceData == null || sourceData.mesh == null) continue;
        final sourceVerts =
            sourceData.deformedVertices ?? sourceData.mesh!.vertices;
        if (sourceVerts.isEmpty) continue;
        final maskBounds =
            _computeTransformedBounds(sourceVerts, sourceData.transform);
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
        _drawTexturedMeshContent(
            canvas, data, vertices, texture, atlasUvs, blendMode);
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
          canvas,
          vertices,
          uvs,
          mesh.indices,
          texture,
          BlendMode.srcOver,
          data.drawable.opacity,
        );
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
      _drawTexturedMeshContent(
          canvas, data, vertices, texture, atlasUvs, blendMode);
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
        // For normal blend mode without masks, render directly.
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

    // Add padding so filtered samples near triangle edges are not clipped by
    // the temporary offscreen layer bounds.
    const pad = 2.0;
    minX -= pad;
    minY -= pad;
    maxX += pad;
    maxY += pad;

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

  /// Draw textured triangles using GPU-accelerated [Canvas.drawVertices].
  ///
  /// This delegates triangle rasterization to the GPU, which guarantees
  /// pixel-perfect edge coverage (top-left rule) and eliminates both gap
  /// artifacts (epsilon=0) and dark line artifacts (epsilon>0 overlap)
  /// that plagued the old clip+affine+drawImage approach (Issue #8).
  ///
  /// Opacity is applied via vertex colors with [BlendMode.modulate] when
  /// the paint's color alpha is less than 1.0.
  void _drawTexturedTriangles(
    Canvas canvas,
    List<Vec2> vertices,
    List<Vec2> uvs,
    List<int> indices,
    ui.Image texture,
    Paint paint,
  ) {
    if (indices.length < 3) return;

    // Vertices.raw requires Uint16List indices (max vertex index 65535).
    // Typical puppet meshes have <1000 vertices; assert to catch anomalies.
    assert(vertices.length <= 65536,
        'drawVertices requires <= 65536 vertices, got ${vertices.length}');

    final shader = ImageShader(
      texture,
      TileMode.clamp,
      TileMode.clamp,
      _identityMatrix4,
      filterQuality: FilterQuality.high,
    );

    // Build vertex positions (x, y pairs in canvas coordinate space)
    final positions = Float32List(vertices.length * 2);
    for (int i = 0; i < vertices.length; i++) {
      positions[i * 2] = vertices[i].x;
      positions[i * 2 + 1] = vertices[i].y;
    }

    // Build texture coordinates in pixel space (UV × texture dimensions)
    final texWidth = texture.width.toDouble();
    final texHeight = texture.height.toDouble();
    final texCoords = Float32List(uvs.length * 2);
    for (int i = 0; i < uvs.length; i++) {
      texCoords[i * 2] = uvs[i].x * texWidth;
      texCoords[i * 2 + 1] = uvs[i].y * texHeight;
    }

    // Validate indices per-triangle so we never break triangle grouping.
    // Dropping invalid indices element-wise can stitch unrelated vertices
    // together and create long stray triangles (visible as black bars).
    final safeTriangleIndices = <int>[];
    for (int i = 0; i + 2 < indices.length; i += 3) {
      final i0 = indices[i];
      final i1 = indices[i + 1];
      final i2 = indices[i + 2];
      if (i0 < 0 ||
          i1 < 0 ||
          i2 < 0 ||
          i0 >= vertices.length ||
          i1 >= vertices.length ||
          i2 >= vertices.length) {
        continue;
      }
      safeTriangleIndices.add(i0);
      safeTriangleIndices.add(i1);
      safeTriangleIndices.add(i2);
    }
    if (safeTriangleIndices.length < 3) return;
    final indexList = Uint16List.fromList(safeTriangleIndices);

    // Handle opacity via vertex colors with modulate blending.
    // paint.color.opacity carries the drawable's opacity (set by callers).
    // For drawVertices, we apply it through vertex colors instead.
    final opacity = paint.color.a;
    Int32List? colorList;
    BlendMode vertexBlendMode = BlendMode.srcOver;
    if (opacity < 1.0) {
      final alpha = (opacity * 255).round().clamp(0, 255);
      final colorValue = alpha << 24 | 0x00FFFFFF; // ARGB white with alpha
      colorList = Int32List(vertices.length);
      for (int i = 0; i < vertices.length; i++) {
        colorList[i] = colorValue;
      }
      vertexBlendMode = BlendMode.modulate;
    }

    final verts = ui.Vertices.raw(
      VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      indices: indexList,
      colors: colorList,
    );

    final drawPaint = Paint()
      ..shader = shader
      ..blendMode = paint.blendMode;

    canvas.drawVertices(verts, vertexBlendMode, drawPaint);

    verts.dispose();
    shader.dispose();
  }

  /// Identity matrix for [ImageShader] (shared, never mutated).
  static final _identityMatrix4 = Float64List(16)
    ..[0] = 1.0
    ..[5] = 1.0
    ..[10] = 1.0
    ..[15] = 1.0;

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
        final zCmp = zb.compareTo(za);
        if (zCmp != 0) return zCmp;
        return a.nodeId.compareTo(b.nodeId);
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
        final zCmp = zb.compareTo(za);
        if (zCmp != 0) return zCmp;
        return a.nodeId.compareTo(b.nodeId);
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
        final atlasRegion =
            renderCtx.getAtlasRegion(sourceData.texturedMesh!.albedoTextureId!);
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
      return _applyThresholdWithShader(source, threshold, width, height,
          invert: invert);
    }
    return _applyThresholdWithColorFilter(source, threshold, width, height,
        invert: invert);
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
      final offset =
          threshold >= 1.0 ? -255.0 : -threshold * 255.0 / (1.0 - threshold);

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

  /// Convert puppet blend mode to Flutter BlendMode.
  ///
  /// Uses [PsdCanvasCompositor.toFlutterBlendMode] for PSD-compatible modes.
  /// Inochi2d-specific modes (clipToLower, sliceFromLower, etc.) are mapped
  /// directly to their Flutter equivalents.
  BlendMode _convertBlendMode(puppet.BlendMode mode) {
    switch (mode) {
      // Inochi2d-specific modes (no PSD equivalent)
      case puppet.BlendMode.clipToLower:
        return BlendMode.srcATop;
      case puppet.BlendMode.sliceFromLower:
        return BlendMode.srcOut;
      case puppet.BlendMode.addGlow:
        return BlendMode.plus;
      case puppet.BlendMode.inverse:
        return BlendMode.xor;
      case puppet.BlendMode.destinationIn:
        return BlendMode.dstIn;
      case puppet.BlendMode.exclusion:
        return BlendMode.exclusion;
      // PSD-compatible modes → delegate to dart_psd_tool
      default:
        return PsdCanvasCompositor.toFlutterBlendMode(
          _puppetBlendModeToPsdString(mode),
        );
    }
  }

  /// Convert puppet BlendMode enum to PSD blend mode string.
  static String _puppetBlendModeToPsdString(puppet.BlendMode mode) {
    switch (mode) {
      case puppet.BlendMode.normal:
        return 'Normal';
      case puppet.BlendMode.multiply:
        return 'Multiply';
      case puppet.BlendMode.screen:
        return 'Screen';
      case puppet.BlendMode.overlay:
        return 'Overlay';
      case puppet.BlendMode.darken:
        return 'Darken';
      case puppet.BlendMode.lighten:
        return 'Lighten';
      case puppet.BlendMode.colorDodge:
        return 'ColorDodge';
      case puppet.BlendMode.colorBurn:
        return 'ColorBurn';
      case puppet.BlendMode.hardLight:
        return 'HardLight';
      case puppet.BlendMode.softLight:
        return 'SoftLight';
      case puppet.BlendMode.difference:
        return 'Difference';
      case puppet.BlendMode.subtract:
        return 'Subtract';
      case puppet.BlendMode.linearDodge:
        return 'LinearDodge';
      default:
        return 'Normal';
    }
  }
}
