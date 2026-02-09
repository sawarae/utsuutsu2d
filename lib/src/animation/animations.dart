/// Animation system for utsutsu2d
///
/// This module provides animation playback functionality for Live2D models.
///
/// ## Features
/// - Frame-based animation with multiple interpolation modes
/// - Loop and reverse playback support
/// - Playback speed adjustment
/// - Animation blending with additive animations
/// - Lead-in/lead-out sections for smooth transitions
///
/// ## Usage
/// ```dart
/// // Create animation player
/// final player = AnimationPlayer(puppet);
///
/// // Load animations
/// final animation = Animation.fromJson('idle', animationData);
/// player.loadAnimation(animation);
///
/// // Play animation
/// player.play('idle', loop: true);
///
/// // Update in game loop
/// player.update(deltaTime);
/// ```
library;

export 'animation.dart';
export 'player.dart';
