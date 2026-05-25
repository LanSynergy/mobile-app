import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import 'eq_preset.dart';

// ── EQ Curve ────────────────────────────────────────────────────────────────

const _kBandHz = <String, double>{
  '1b': 65,
  '2b': 92,
  '3b': 131,
  '4b': 185,
  '5b': 262,
  '6b': 370,
  '7b': 523,
  '8b': 740,
  '9b': 1000,
  '10b': 1500,
  '11b': 2100,
  '12b': 2900,
  '13b': 4200,
  '14b': 5900,
  '15b': 8300,
  '16b': 11800,
  '17b': 16700,
  '18b': 20000,
};
const _kMinFreq = 40.0;
const _kMaxFreq = 22000.0;

class EqCurveWidget extends StatelessWidget {
  const EqCurveWidget({super.key, required this.bands, this.height = 200});

  final Map<String, double> bands;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: BorderRadius.circular(AfRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _EqCurvePainter(bands: bands),
        size: Size.infinite,
      ),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  _EqCurvePainter({required this.bands});
  final Map<String, double> bands;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final w = size.width, h = size.height;
    const padL = 8.0, padR = 8.0, padT = 12.0, padB = 28.0;
    final plotW = w - padL - padR, plotH = h - padT - padB;
    if (plotW <= 0 || plotH <= 0) return;

    double freqToX(double f) =>
        padL +
        (math.log(f / _kMinFreq) / math.log(_kMaxFreq / _kMinFreq)).clamp(
              0,
              1,
            ) *
            plotW;
    double gainToY(double g) => padT + (1 - (g / 4).clamp(0, 1)) * plotH;

    // Grid
    final gridPaint = Paint()
      ..color = AfColors.textTertiary.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    for (final f in [65, 131, 262, 523, 1000, 2000, 4000, 8000, 16000, 20000]) {
      final x = freqToX(f.toDouble());
      canvas.drawLine(Offset(x, padT), Offset(x, padT + plotH), gridPaint);
    }

    // Flat line
    final flatY = gainToY(1);
    canvas.drawLine(
      Offset(padL, flatY),
      Offset(w - padR, flatY),
      Paint()
        ..color = AfColors.textTertiary.withValues(alpha: 0.15)
        ..strokeWidth = 1,
    );

    // Half markers
    final half = Paint()
      ..color = AfColors.textTertiary.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(padL, gainToY(2)),
      Offset(w - padR, gainToY(2)),
      half,
    );
    canvas.drawLine(
      Offset(padL, gainToY(3)),
      Offset(w - padR, gainToY(3)),
      half,
    );

    // Points
    final pts = <Offset>[];
    for (final e in kEqBands.entries) {
      pts.add(
        Offset(freqToX(_kBandHz[e.key] ?? 65), gainToY(bands[e.key] ?? 1)),
      );
    }
    if (pts.isEmpty) return;

    // Gradient fill
    final fillPath = Path()..moveTo(pts.first.dx, padT + plotH);
    for (final p in pts) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(pts.last.dx, padT + plotH);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AfColors.indigo500.withValues(alpha: 0.25),
            AfColors.indigo500.withValues(alpha: 0.05),
          ],
        ).createShader(Rect.fromLTWH(0, padT, w, plotH)),
    );

    // Curve
    final curvePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final cx = (pts[i - 1].dx + pts[i].dx) / 2;
      curvePath.cubicTo(cx, pts[i - 1].dy, cx, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = AfColors.indigo400
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots
    final dotFill = Paint()..color = AfColors.surfaceBase;
    final dotStroke = Paint()
      ..color = AfColors.indigo400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final p in pts) {
      canvas.drawCircle(p, 4, dotFill);
      canvas.drawCircle(p, 4, dotStroke);
    }

    // Freq labels
    final fls = TextStyle(
      color: AfColors.textTertiary.withValues(alpha: 0.3),
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );
    for (final f in [65, 131, 262, 523, 1000, 2000, 4000, 8000, 16000, 20000]) {
      final x = freqToX(f.toDouble());
      final tp = TextPainter(
        text: TextSpan(text: f >= 1000 ? '${f ~/ 1000}k' : '$f', style: fls),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, padT + plotH + 6));
    }

    // Gain labels
    final gls = TextStyle(
      color: AfColors.textTertiary.withValues(alpha: 0.3),
      fontSize: 8,
    );
    for (final g in [4.0, 2.0, 1.0]) {
      final y = gainToY(g);
      final tp = TextPainter(
        text: TextSpan(text: g == 1.0 ? '1x' : '${g.toInt()}x', style: gls),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w - padR + 4, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter o) {
    if (o.bands.length != bands.length) return true;
    for (final e in bands.entries) {
      if (o.bands[e.key] != e.value) return true;
    }
    return false;
  }
}

// ── Effect Card (expandable section) ────────────────────────────────────────

class EqEffectCard extends StatefulWidget {
  const EqEffectCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onToggle,
    this.children = const [],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final List<Widget> children;

  @override
  State<EqEffectCard> createState() => _EqEffectCardState();
}

class _EqEffectCardState extends State<EqEffectCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: BorderRadius.circular(AfRadii.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header tap target
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(AfRadii.lg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.enabled
                          ? AfColors.indigo500.withValues(alpha: 0.15)
                          : AfColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: widget.enabled
                          ? AfColors.indigo400
                          : AfColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: AfTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (widget.subtitle.isNotEmpty)
                          Text(
                            widget.subtitle,
                            style: AfTypography.bodySmall.copyWith(
                              color: AfColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: widget.enabled,
                    activeTrackColor: AfColors.indigo500,
                    onChanged: (v) {
                      widget.onToggle(v);
                      if (!v && _expanded) {
                        setState(() => _expanded = false);
                        _ctrl.reverse();
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AfColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          AnimatedBuilder(
            animation: _anim,
            builder: (context, child) {
              return ClipRect(
                child: Align(heightFactor: _anim.value, child: child),
              );
            },
            child: widget.children.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: widget.children,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Compact slider row ──

Widget compactSlider(
  String label,
  double value,
  double min,
  double max,
  int divisions,
  ValueChanged<double> onChanged,
  VoidCallback onChangeEnd, {
  String? suffix,
  int precision = 0,
}) {
  final display = value >= 0 && suffix == 'dB'
      ? '+${value.toStringAsFixed(precision)}'
      : value.toStringAsFixed(precision);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Text(label, style: AfTypography.bodySmall.copyWith(fontSize: 12)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AfColors.surfaceHigh.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              suffix != null ? '$display $suffix' : display,
              style: AfTypography.mono.copyWith(
                fontSize: 11,
                color: AfColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        activeColor: AfColors.indigo400,
        inactiveColor: AfColors.surfaceHigh,
        onChanged: onChanged,
        onChangeEnd: (_) => onChangeEnd(),
      ),
    ],
  );
}

// ── Compact text field ──

Widget compactTextField(
  BuildContext context,
  String label,
  String value,
  String hint,
  ValueChanged<String> onSubmitted,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: AfTypography.bodySmall.copyWith(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: value,
            style: AfTypography.mono.copyWith(fontSize: 12),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AfTypography.mono.copyWith(
                fontSize: 11,
                color: AfColors.textTertiary,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AfColors.surfaceHigh),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AfColors.surfaceHigh),
              ),
              filled: true,
              fillColor: AfColors.surfaceHigh.withValues(alpha: 0.3),
            ),
            onFieldSubmitted: onSubmitted,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
      ],
    ),
  );
}

// ── Section divider inside cards ──

Widget sectionDivider() => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Divider(height: 1, color: AfColors.surfaceHigh.withValues(alpha: 0.4)),
);
