/// Blend modes for drawing
enum BlendMode {
  normal,
  multiply,
  colorDodge,
  linearDodge,
  screen,
  clipToLower,
  sliceFromLower,
  lighten,
  addGlow,
  subtract,
  overlay,
  darken,
  difference,
  exclusion,
  colorBurn,
  hardLight,
  softLight,
  inverse,
  destinationIn,
}

/// Mask mode
enum MaskMode {
  mask,
  dodge,
}

/// Mask definition
class Mask {
  final int sourceNodeId;
  final MaskMode mode;

  const Mask({
    required this.sourceNodeId,
    this.mode = MaskMode.mask,
  });
}

/// Drawable component for renderable nodes
class Drawable {
  BlendMode blendMode;
  double opacity;
  List<Mask>? masks;
  double? maskThreshold;

  Drawable({
    this.blendMode = BlendMode.normal,
    this.opacity = 1.0,
    this.masks,
    this.maskThreshold,
  });

  bool get hasMasks => masks != null && masks!.isNotEmpty;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'blend_mode': _blendModeToString(blendMode),
      'opacity': opacity,
    };
    if (masks != null && masks!.isNotEmpty) {
      json['masks'] = masks!
          .map((m) => {
                'source': m.sourceNodeId,
                'mode': m.mode == MaskMode.dodge ? 'dodge' : 'mask',
              })
          .toList();
    }
    if (maskThreshold != null) {
      json['mask_threshold'] = maskThreshold;
    }
    return json;
  }

  static String _blendModeToString(BlendMode mode) {
    switch (mode) {
      case BlendMode.normal:
        return 'normal';
      case BlendMode.multiply:
        return 'multiply';
      case BlendMode.colorDodge:
        return 'color_dodge';
      case BlendMode.linearDodge:
        return 'linear_dodge';
      case BlendMode.screen:
        return 'screen';
      case BlendMode.clipToLower:
        return 'clip_to_lower';
      case BlendMode.sliceFromLower:
        return 'slice_from_lower';
      case BlendMode.lighten:
        return 'lighten';
      case BlendMode.addGlow:
        return 'add_glow';
      case BlendMode.subtract:
        return 'subtract';
      case BlendMode.overlay:
        return 'overlay';
      case BlendMode.darken:
        return 'darken';
      case BlendMode.difference:
        return 'difference';
      case BlendMode.exclusion:
        return 'exclusion';
      case BlendMode.colorBurn:
        return 'color_burn';
      case BlendMode.hardLight:
        return 'hard_light';
      case BlendMode.softLight:
        return 'soft_light';
      case BlendMode.inverse:
        return 'inverse';
      case BlendMode.destinationIn:
        return 'destination_in';
    }
  }

  factory Drawable.fromJson(Map<String, dynamic> json) {
    return Drawable(
      blendMode: _parseBlendMode(json['blend_mode']),
      opacity: (json['opacity'] ?? 1.0).toDouble(),
      masks: json['masks'] != null
          ? (json['masks'] as List)
              .map((m) => Mask(
                    sourceNodeId: m['source'],
                    mode: m['mode'] == 'dodge' ? MaskMode.dodge : MaskMode.mask,
                  ))
              .toList()
          : null,
      maskThreshold: json['mask_threshold']?.toDouble(),
    );
  }

  static BlendMode _parseBlendMode(dynamic value) {
    if (value == null) return BlendMode.normal;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'multiply':
          return BlendMode.multiply;
        case 'color_dodge':
        case 'colordodge':
          return BlendMode.colorDodge;
        case 'linear_dodge':
        case 'lineardodge':
          return BlendMode.linearDodge;
        case 'screen':
          return BlendMode.screen;
        case 'clip_to_lower':
        case 'cliptolower':
          return BlendMode.clipToLower;
        case 'slice_from_lower':
        case 'slicefromlower':
          return BlendMode.sliceFromLower;
        case 'lighten':
          return BlendMode.lighten;
        case 'add_glow':
        case 'addglow':
          return BlendMode.addGlow;
        case 'subtract':
          return BlendMode.subtract;
        case 'overlay':
          return BlendMode.overlay;
        case 'darken':
          return BlendMode.darken;
        case 'difference':
          return BlendMode.difference;
        case 'exclusion':
          return BlendMode.exclusion;
        case 'color_burn':
        case 'colorburn':
          return BlendMode.colorBurn;
        case 'hard_light':
        case 'hardlight':
          return BlendMode.hardLight;
        case 'soft_light':
        case 'softlight':
          return BlendMode.softLight;
        case 'inverse':
          return BlendMode.inverse;
        case 'destination_in':
        case 'destinationin':
          return BlendMode.destinationIn;
        default:
          return BlendMode.normal;
      }
    }
    return BlendMode.normal;
  }
}
