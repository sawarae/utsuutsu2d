import 'vec2.dart';

/// Interpolation mode
enum InterpolateMode {
  nearest,
  linear,
}

/// Range for interpolation
class InterpRange<T> {
  final T begin;
  final T end;

  const InterpRange(this.begin, this.end);
}

/// Interpolate a single float value
double interpolateF32(
  double t,
  InterpRange<double> rangeIn,
  InterpRange<double> rangeOut,
  InterpolateMode mode,
) {
  switch (mode) {
    case InterpolateMode.nearest:
      // Return the nearest value
      final mid = (rangeIn.begin + rangeIn.end) / 2;
      return t < mid ? rangeOut.begin : rangeOut.end;
    case InterpolateMode.linear:
      if (rangeIn.end == rangeIn.begin) return rangeOut.begin;
      final normalizedT = (t - rangeIn.begin) / (rangeIn.end - rangeIn.begin);
      return rangeOut.begin + normalizedT * (rangeOut.end - rangeOut.begin);
  }
}

/// Interpolate a Vec2 value
Vec2 interpolateVec2(
  double t,
  InterpRange<double> rangeIn,
  InterpRange<Vec2> rangeOut,
  InterpolateMode mode,
) {
  switch (mode) {
    case InterpolateMode.nearest:
      final mid = (rangeIn.begin + rangeIn.end) / 2;
      return t < mid ? rangeOut.begin : rangeOut.end;
    case InterpolateMode.linear:
      if (rangeIn.end == rangeIn.begin) return rangeOut.begin;
      final normalizedT = (t - rangeIn.begin) / (rangeIn.end - rangeIn.begin);
      return rangeOut.begin.lerp(rangeOut.end, normalizedT);
  }
}

/// Additive interpolation for float arrays
void interpolateF32sAdditive(
  double t,
  InterpRange<double> rangeIn,
  List<double> valuesOut,
  List<double> result,
  InterpolateMode mode,
) {
  assert(valuesOut.length >= 2);
  final interpValue = interpolateF32(
    t,
    rangeIn,
    InterpRange(valuesOut.first, valuesOut.last),
    mode,
  );
  for (int i = 0; i < result.length; i++) {
    result[i] += interpValue;
  }
}

/// Additive interpolation for Vec2 arrays
void interpolateVec2sAdditive(
  double t,
  InterpRange<double> rangeIn,
  List<Vec2> beginValues,
  List<Vec2> endValues,
  List<Vec2> result,
  InterpolateMode mode,
) {
  assert(beginValues.length == endValues.length);
  assert(result.length == beginValues.length);

  for (int i = 0; i < result.length; i++) {
    final interpValue = interpolateVec2(
      t,
      rangeIn,
      InterpRange(beginValues[i], endValues[i]),
      mode,
    );
    result[i] = result[i] + interpValue;
  }
}

/// Bilinear interpolation for float
double biInterpolateF32(
  Vec2 t,
  InterpRange<double> rangeInX,
  InterpRange<double> rangeInY,
  double topLeft,
  double topRight,
  double bottomLeft,
  double bottomRight,
  InterpolateMode mode,
) {
  // Interpolate along X for top and bottom
  final top = interpolateF32(
    t.x,
    rangeInX,
    InterpRange(topLeft, topRight),
    mode,
  );
  final bottom = interpolateF32(
    t.x,
    rangeInX,
    InterpRange(bottomLeft, bottomRight),
    mode,
  );

  // Interpolate along Y between top and bottom
  return interpolateF32(
    t.y,
    rangeInY,
    InterpRange(top, bottom),
    mode,
  );
}

/// Bilinear interpolation for Vec2
Vec2 biInterpolateVec2(
  Vec2 t,
  InterpRange<double> rangeInX,
  InterpRange<double> rangeInY,
  Vec2 topLeft,
  Vec2 topRight,
  Vec2 bottomLeft,
  Vec2 bottomRight,
  InterpolateMode mode,
) {
  // Interpolate along X for top and bottom
  final top = interpolateVec2(
    t.x,
    rangeInX,
    InterpRange(topLeft, topRight),
    mode,
  );
  final bottom = interpolateVec2(
    t.x,
    rangeInX,
    InterpRange(bottomLeft, bottomRight),
    mode,
  );

  // Interpolate along Y between top and bottom
  return interpolateVec2(
    t.y,
    rangeInY,
    InterpRange(top, bottom),
    mode,
  );
}

/// Bilinear additive interpolation for Vec2 arrays
void biInterpolateVec2sAdditive(
  Vec2 t,
  InterpRange<double> rangeInX,
  InterpRange<double> rangeInY,
  List<Vec2> topLeft,
  List<Vec2> topRight,
  List<Vec2> bottomLeft,
  List<Vec2> bottomRight,
  List<Vec2> result,
  InterpolateMode mode,
) {
  assert(topLeft.length == topRight.length);
  assert(topLeft.length == bottomLeft.length);
  assert(topLeft.length == bottomRight.length);
  assert(topLeft.length == result.length);

  for (int i = 0; i < result.length; i++) {
    final interpValue = biInterpolateVec2(
      t,
      rangeInX,
      rangeInY,
      topLeft[i],
      topRight[i],
      bottomLeft[i],
      bottomRight[i],
      mode,
    );
    result[i] = result[i] + interpValue;
  }
}
