/// utsutsu2d - Pure Dart puppet animation library
///
/// A puppet animation library inspired by Inochi2D/inox2d,
/// implemented in pure Dart without requiring native libraries.
///
/// ## Features
/// - INP/INX file format parsing
/// - Node tree and transform hierarchy
/// - Parameter-based animation
/// - Animation playback with interpolation
/// - Physics simulation (rigid and spring pendulums)
/// - Flutter Canvas rendering
/// - Interactive widgets for puppet control
///
/// ## Basic Usage
/// ```dart
/// import 'package:utsutsu2d/utsutsu2d.dart';
///
/// // Load a model
/// final model = await ModelLoader.loadFromFile('puppet.inp');
///
/// // Initialize puppet
/// model.puppet.initAll();
///
/// // Use PuppetController and PuppetWidget for display
/// ```
library utsutsu2d;

// Core
export 'src/core/core.dart';

// Math
export 'src/math/math.dart';

// Parameters
export 'src/params/params.dart';

// Components
export 'src/components/components.dart';

// Physics
export 'src/physics/physics.dart';

// Animation
export 'src/animation/animations.dart';

// Formats
export 'src/formats/formats.dart';

// Rendering
export 'src/render/render.dart';

// Widgets
export 'src/widgets/widgets.dart';
