/// Animation playback system
library;

import 'animation.dart';
import '../core/puppet.dart';

/// Playback state for a single animation
class AnimationPlayback {
  /// The animation being played
  final Animation animation;

  /// Parent player
  final AnimationPlayer player;

  /// Current playback time in seconds
  double _time = 0.0;

  /// Whether the animation is currently playing
  bool _playing = false;

  /// Whether the animation is paused
  bool _paused = false;

  /// Whether the animation is stopping (playing lead-out)
  bool _stopping = false;

  /// Whether the animation should loop
  bool _looping = false;

  /// Whether to play the lead-out when stopping
  bool _playLeadOut = false;

  /// Playback speed multiplier (1.0 = normal speed)
  double _speed = 1.0;

  /// Animation strength/weight (0.0 to 1.0)
  double _strength = 1.0;

  /// Number of times the animation has looped
  int _looped = 0;

  /// Whether this playback instance is still valid
  bool valid = true;

  AnimationPlayback(this.player, this.animation);

  /// Get current frame number (integer)
  int get frame => (_time / animation.timestep).round();

  /// Get current frame number (floating point, for smooth interpolation)
  double get hframe => _time / animation.timestep;

  /// Total number of frames
  int get frames => animation.length;

  /// Get loop end point
  int get loopPointEnd =>
      animation.hasLeadOut ? animation.leadOut : animation.length;

  /// Get loop begin point
  int get loopPointBegin => animation.hasLeadIn ? animation.leadIn : 0;

  /// Whether animation has reached the end
  bool get eof => frame >= animation.length;

  /// Whether currently playing
  bool get isPlaying => _playing;

  /// Whether currently paused
  bool get isPaused => _paused;

  /// Whether currently stopping
  bool get isStopping => _stopping;

  /// Whether looping is enabled
  bool get isLooping => _looping;

  /// Number of times looped
  int get looped => _looped;

  /// Playback speed multiplier
  double get speed => _speed;
  set speed(double value) => _speed = value.clamp(0.1, 10.0);

  /// Animation strength/weight
  double get strength => _strength;
  set strength(double value) => _strength = value.clamp(0.0, 1.0);

  /// Current time in seconds
  double get seconds => _time.floor().toDouble();

  /// Current time in milliseconds (fractional part)
  int get milliseconds => ((_time - seconds) * 1000).round();

  /// Whether playing the lead-out section
  bool get isPlayingLeadOut =>
      ((_playing && !_looping) || _stopping) && _playLeadOut && frame < animation.length;

  /// Whether currently running (playing or in lead-out)
  bool get isRunning => _playing || isPlayingLeadOut;

  /// Play the animation
  void play({bool loop = false, bool playLeadOut = true}) {
    if (_paused) {
      // Resume from pause
      _paused = false;
    } else {
      // Start from beginning
      _time = 0.0;
      _looped = 0;
      _stopping = false;
      _playing = true;
      _looping = loop;
      _playLeadOut = playLeadOut;
    }
  }

  /// Pause the animation
  void pause() {
    _paused = true;
  }

  /// Stop the animation
  void stop({bool immediate = false}) {
    if (_stopping) return;

    final shouldStopImmediate = immediate ||
        frame == 0 ||
        _paused ||
        !animation.hasLeadOut;

    _stopping = !shouldStopImmediate;
    _looping = false;
    _paused = false;
    _playing = false;
    _playLeadOut = !shouldStopImmediate;

    if (shouldStopImmediate) {
      _time = 0.0;
      _looped = 0;
    }
  }

  /// Seek to a specific frame
  void seek(int targetFrame) {
    final clampedFrame = targetFrame.clamp(0, frames);
    _time = clampedFrame * animation.timestep;
    _looped = 0;
  }

  /// Update animation state
  void update(double deltaTime) {
    if (!valid || !isRunning) return;

    if (_paused) {
      render();
      return;
    }

    // Update time with speed multiplier
    _time += deltaTime * _speed;

    // Handle looping
    if (!isPlayingLeadOut && _looping && frame >= loopPointEnd) {
      _time = loopPointBegin * animation.timestep;
      _looped++;
    }

    // Clamp to last frame
    if (frame + 1 >= frames) {
      _time = (frames - 1) * animation.timestep;
    }

    render();

    // Handle stopping animation completely when finished
    if (!_looping && !_stopping) {
      if (frame + 1 >= frames) {
        _playing = false;
        // Don't reset time - stay at the end
      }
    }

    // Handle stopping animation completely on lead-out end
    if (!_looping && isPlayingLeadOut) {
      if (frame + 1 >= animation.length) {
        _playing = false;
        _playLeadOut = false;
        _stopping = false;
        // Don't reset time - stay at the end
        _looped = 0;
      }
    }
  }

  /// Render current frame to puppet parameters
  void render() {
    final realStrength = _strength.clamp(0.0, 1.0);

    for (final lane in animation.lanes) {
      final value = lane.getValue(hframe, snapSubframes: player.snapToFramerate);
      final adjustedValue = value * realStrength;

      // Apply to puppet parameter
      player.puppet.setParamAxis(
        lane.paramRef.paramId,
        lane.paramRef.targetAxis,
        adjustedValue,
        mergeMode: lane.mergeMode,
      );
    }
  }

  @override
  String toString() => 'AnimationPlayback(${animation.name}, '
      'frame: $frame/$frames, playing: $_playing, looping: $_looping)';
}

/// Manages animation playback for a puppet
class AnimationPlayer {
  /// The puppet being animated
  final Puppet puppet;

  /// Map of animation name to animation data
  final Map<String, Animation> animations = {};

  /// Currently playing animations
  final List<AnimationPlayback> _playingAnimations = [];

  /// Whether to snap to animation framerate (disable smooth interpolation)
  bool snapToFramerate = false;

  AnimationPlayer(this.puppet);

  /// Load an animation
  void loadAnimation(Animation animation) {
    animations[animation.name] = animation;
  }

  /// Load multiple animations
  void loadAnimations(Iterable<Animation> anims) {
    for (final anim in anims) {
      loadAnimation(anim);
    }
  }

  /// Get or create playback for an animation
  AnimationPlayback? createOrGet(String name) {
    // Check if already playing
    for (final playback in _playingAnimations) {
      if (playback.animation.name == name) {
        return playback;
      }
    }

    // Create new playback
    final animation = animations[name];
    if (animation == null) return null;

    final playback = AnimationPlayback(this, animation);
    _playingAnimations.add(playback);
    return playback;
  }

  /// Play an animation
  AnimationPlayback? play(String name, {bool loop = false, bool playLeadOut = true}) {
    final playback = createOrGet(name);
    if (playback != null) {
      playback.play(loop: loop, playLeadOut: playLeadOut);
    }
    return playback;
  }

  /// Stop an animation
  void stop(String name, {bool immediate = false}) {
    for (final playback in _playingAnimations) {
      if (playback.animation.name == name) {
        playback.stop(immediate: immediate);
        break;
      }
    }
  }

  /// Stop all animations
  void stopAll({bool immediate = false}) {
    for (final playback in _playingAnimations) {
      playback.stop(immediate: immediate);
    }
  }

  /// Pause an animation
  void pause(String name) {
    for (final playback in _playingAnimations) {
      if (playback.animation.name == name) {
        playback.pause();
        break;
      }
    }
  }

  /// Update all playing animations
  void update(double deltaTime) {
    // Remove invalid playbacks
    _playingAnimations.removeWhere((p) => !p.valid);

    // Update all animations
    for (final playback in _playingAnimations) {
      if (playback.valid) {
        playback.update(deltaTime);
      }
    }
  }

  /// Pre-render all animations
  void prerenderAll() {
    for (final playback in _playingAnimations) {
      playback.render();
    }
  }

  /// Destroy all animations
  void destroyAll() {
    for (final playback in _playingAnimations) {
      playback.valid = false;
    }
    _playingAnimations.clear();
  }

  /// Get playback for an animation
  AnimationPlayback? getPlayback(String name) {
    for (final playback in _playingAnimations) {
      if (playback.animation.name == name) {
        return playback;
      }
    }
    return null;
  }

  /// Check if an animation is playing
  bool isPlaying(String name) {
    final playback = getPlayback(name);
    return playback?.isPlaying ?? false;
  }

  /// Get list of all playing animations
  List<String> get playingAnimationNames =>
      _playingAnimations.map((p) => p.animation.name).toList();

  @override
  String toString() => 'AnimationPlayer(${animations.length} loaded, '
      '${_playingAnimations.length} playing)';
}
