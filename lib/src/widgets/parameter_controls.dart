import 'package:flutter/material.dart';
import '../params/param.dart';
import '../math/vec2.dart';
import 'puppet_widget.dart';

/// Slider for controlling a 1D parameter
class ParameterSlider extends StatelessWidget {
  final PuppetController controller;
  final Param param;
  final String? label;

  const ParameterSlider({
    super.key,
    required this.controller,
    required this.param,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final value = controller.puppet?.getParamValue(param.name);
        final currentX = value?.x ?? param.defaultValue.x;
        final min = param.minValue.x;
        final max = param.maxValue.x;
        final clamped = currentX.clamp(min, max);

        // Snap to integers when min and max are both integers
        final isIntParam = min == min.roundToDouble() &&
            max == max.roundToDouble() &&
            max > min;
        final divisions = isIntParam ? (max - min).round() : null;

        final valueLabel = isIntParam
            ? clamped.round().toString()
            : clamped.toStringAsFixed(2);

        final smallStyle = Theme.of(context).textTheme.bodySmall;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label ?? param.name,
                    style: smallStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  valueLabel,
                  style: smallStyle?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  isIntParam ? min.round().toString() : min.toStringAsFixed(1),
                  style: smallStyle,
                ),
                Expanded(
                  child: Slider(
                    value: clamped,
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: (value) {
                      controller.setParameter(param.name, value);
                    },
                  ),
                ),
                Text(
                  isIntParam ? max.round().toString() : max.toStringAsFixed(1),
                  style: smallStyle,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 2D pad for controlling a 2D parameter
class Parameter2DPad extends StatefulWidget {
  final PuppetController controller;
  final Param param;
  final String? label;
  final double size;

  const Parameter2DPad({
    super.key,
    required this.controller,
    required this.param,
    this.label,
    this.size = 150,
  });

  @override
  State<Parameter2DPad> createState() => _Parameter2DPadState();
}

class _Parameter2DPadState extends State<Parameter2DPad> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final value =
            widget.controller.puppet?.getParamValue(widget.param.name);
        final currentValue = value ?? widget.param.defaultValue;

        // Normalize to 0-1 range
        final normalizedX = (currentValue.x - widget.param.minValue.x) /
            (widget.param.maxValue.x - widget.param.minValue.x);
        final normalizedY = (currentValue.y - widget.param.minValue.y) /
            (widget.param.maxValue.y - widget.param.minValue.y);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null || widget.param.name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  widget.label ?? widget.param.name,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.grey.shade200,
                ),
                child: CustomPaint(
                  painter: _PadPainter(
                    normalizedX: normalizedX.clamp(0, 1),
                    normalizedY: normalizedY.clamp(0, 1),
                  ),
                  size: Size(widget.size, widget.size),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onPanStart(DragStartDetails details) {
    _updateValue(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _updateValue(details.localPosition);
  }

  void _updateValue(Offset position) {
    final param = widget.param;

    // Convert position to normalized value (0-1)
    final normalizedX = (position.dx / widget.size).clamp(0.0, 1.0);
    final normalizedY = (position.dy / widget.size).clamp(0.0, 1.0);

    // Convert to parameter value
    final valueX =
        param.minValue.x + normalizedX * (param.maxValue.x - param.minValue.x);
    final valueY =
        param.minValue.y + normalizedY * (param.maxValue.y - param.minValue.y);

    widget.controller.setParameter(param.name, valueX, valueY);
  }
}

class _PadPainter extends CustomPainter {
  final double normalizedX;
  final double normalizedY;

  _PadPainter({
    required this.normalizedX,
    required this.normalizedY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;

    // Draw crosshairs
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      paint,
    );

    // Draw indicator
    final indicatorX = normalizedX * size.width;
    final indicatorY = normalizedY * size.height;

    final indicatorPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(indicatorX, indicatorY),
      8,
      indicatorPaint,
    );

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(
      Offset(indicatorX, indicatorY),
      8,
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(_PadPainter oldDelegate) {
    return normalizedX != oldDelegate.normalizedX ||
        normalizedY != oldDelegate.normalizedY;
  }
}

/// Parameter list widget showing all parameters
class ParameterList extends StatelessWidget {
  final PuppetController controller;
  final bool show2DPads;

  const ParameterList({
    super.key,
    required this.controller,
    this.show2DPads = true,
  });

  @override
  Widget build(BuildContext context) {
    final params = controller.puppet?.params ?? [];

    if (params.isEmpty) {
      return const Center(
        child: Text('No parameters'),
      );
    }

    return ListView.builder(
      itemCount: params.length,
      itemBuilder: (context, index) {
        final param = params[index];

        if (param.is2D && show2DPads) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Parameter2DPad(
              controller: controller,
              param: param,
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ParameterSlider(
              controller: controller,
              param: param,
            ),
          );
        }
      },
    );
  }
}
