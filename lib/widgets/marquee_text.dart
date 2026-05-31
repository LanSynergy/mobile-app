import 'package:flutter/material.dart';

/// Auto-scrolling marquee text that animates when content overflows.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.speedPxPerSec = 30.0,
    this.minDurationMs = 4000,
    this.maxDurationMs = 20000,
  });

  final String text;
  final TextStyle style;

  /// Pixels per second for scroll speed calculation.
  final double speedPxPerSec;

  /// Minimum animation duration in milliseconds.
  final int minDurationMs;

  /// Maximum animation duration in milliseconds.
  final int maxDurationMs;

  @override
  State<MarqueeText> createState() => MarqueeTextState();
}

class MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _offset = 0.0;
  bool _shouldScroll = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.stop();
      _controller.value = 0;
      _shouldScroll = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        if (tp.width <= maxWidth) {
          if (_shouldScroll) {
            _controller.stop();
            _controller.value = 0;
            _shouldScroll = false;
          }
          return Text(widget.text, maxLines: 1, style: widget.style);
        }

        if (!_shouldScroll) {
          _shouldScroll = true;
          _offset = tp.width + 32.0;
          final durationMs = (_offset / widget.speedPxPerSec * 1000)
              .round()
              .clamp(widget.minDurationMs, widget.maxDurationMs);
          _controller.duration = Duration(milliseconds: durationMs);
          _controller.repeat();
        }

        final totalWidth = _offset + tp.width;
        return ClipRect(
          child: SizedBox(
            width: maxWidth,
            height: tp.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return Transform.translate(
                      offset: Offset(-_offset * _controller.value, 0),
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: totalWidth,
                        maxWidth: totalWidth,
                        minHeight: tp.height,
                        maxHeight: tp.height,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.text, maxLines: 1, style: widget.style),
                            const SizedBox(width: 32),
                            Text(widget.text, maxLines: 1, style: widget.style),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
