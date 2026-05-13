import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

class AudioVisualScrubber extends ConsumerStatefulWidget {
  final double height;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;

  const AudioVisualScrubber({
    super.key,
    this.height        = 120,
    required this.progress,
    this.playedColor   = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.onScrub,
    this.onScrubEnd,
  });

  @override
  ConsumerState<AudioVisualScrubber> createState() =>
      _AudioVisualScrubberState();
}

class _AudioVisualScrubberState extends ConsumerState<AudioVisualScrubber>
    with SingleTickerProviderStateMixin {
  late final _BlockNotifier _fftNotifier;
  late final _ScrubNotifier _scrubNotifier;
  late final AnimationController _ticker;
  StreamSubscription<FftFrame>? _fftSub;
  Timer? _silenceTimer;
  Animation<double>? _overlayAnim;
  late final AppLifecycleListener _lifecycle;

  bool _isAppBackground = false;

  bool get _isObscured => (_overlayAnim?.value ?? 0.0) > 0.0;
  bool get _shouldRender => mounted && !_isObscured && !_isAppBackground;

  @override
  void initState() {
    super.initState();
    _fftNotifier   = _BlockNotifier();
    _scrubNotifier = _ScrubNotifier(progress: widget.progress);

    // Stop ticker when app is backgrounded, resume when foregrounded.
    _lifecycle = AppLifecycleListener(
      onPause:  () { _isAppBackground = true;  _ticker.stop(); },
      onResume: () {
        _isAppBackground = false;
        if (_fftNotifier.totalEnergy > 0) _ticker.repeat();
      },
    );

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(() {
        if (mounted) {
          final keepAnimating = _fftNotifier.tick();
          if (!keepAnimating) _ticker.stop();
        }
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fftSub = ref.read(playerServiceProvider).spectrumStream.listen(
        (frame) {
          // Drop FFT data when obscured or backgrounded.
          if (!_shouldRender) return;
          _silenceTimer?.cancel();
          _fftNotifier.ingest(frame.bands);
          if (!_ticker.isAnimating) _ticker.repeat();
          _silenceTimer = Timer(const Duration(milliseconds: 150), () {
            if (mounted && _shouldRender) {
              _fftNotifier.clearTarget();
              if (!_ticker.isAnimating) _ticker.repeat();
            }
          });
        },
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    // Detect when another route (Queue, Lyrics, etc.) covers this screen.
    if (_overlayAnim != route?.secondaryAnimation) {
      _overlayAnim?.removeListener(_onVisibilityChange);
      _overlayAnim = route?.secondaryAnimation;
      _overlayAnim?.addListener(_onVisibilityChange);
    }
  }

  void _onVisibilityChange() {
    if (_isObscured) {
      _ticker.stop();
    } else if (_fftNotifier.totalEnergy > 0.001) {
      _ticker.repeat();
    }
  }

  @override
  void dispose() {
    _overlayAnim?.removeListener(_onVisibilityChange);
    _lifecycle.dispose();
    _silenceTimer?.cancel();
    _fftSub?.cancel();
    _ticker.dispose();
    _fftNotifier.dispose();
    _scrubNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AudioVisualScrubber old) {
    super.didUpdateWidget(old);
    _scrubNotifier.update(widget.progress);
  }

  double _toProgress(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return 0;
    return (dx / box.size.width).clamp(0.0, 1.0);
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    _scrubNotifier.setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_scrubNotifier.dragProgress);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_scrubNotifier.dragProgress);
    _scrubNotifier.setDrag(false, _scrubNotifier.dragProgress);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) {
        HapticFeedback.selectionClick();
        _handleDragUpdate(DragUpdateDetails(
          globalPosition: d.globalPosition,
          localPosition:  d.localPosition,
        ));
      },
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd:    _handleDragEnd,
      onTapDown: (d) {
        HapticFeedback.selectionClick();
        final p = _toProgress(d.localPosition.dx);
        widget.onScrub?.call(p);
        widget.onScrubEnd?.call(p);
      },
      child: SizedBox(
        height: widget.height,
        width:  double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: _CombinedBarPainter(
                  fftNotifier:   _fftNotifier,
                  scrubNotifier: _scrubNotifier,
                  playedColor:   widget.playedColor,
                  unplayedColor: widget.unplayedColor,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: _ScrubOverlayPainter(
                  notifier:      _scrubNotifier,
                  playedColor:   widget.playedColor,
                  unplayedColor: widget.unplayedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifiers
// ─────────────────────────────────────────────────────────────────────────────

class _ScrubNotifier extends ChangeNotifier {
  double _progress;
  bool   _dragging     = false;
  double _dragProgress = 0.0;

  _ScrubNotifier({required double progress}) : _progress = progress;

  double get displayProgress =>
      _dragging ? _dragProgress : _progress.clamp(0.0, 1.0);
  bool   get dragging      => _dragging;
  double get dragProgress  => _dragProgress;

  void update(double progress) {
    _progress = progress;
    notifyListeners();
  }

  void setDrag(bool dragging, double progress) {
    _dragging     = dragging;
    _dragProgress = progress;
    notifyListeners();
  }
}

class _BlockNotifier extends ChangeNotifier {
  static const int bins = 64;

  final Float32List target   = Float32List(bins);
  final Float32List smoothed = Float32List(bins);
  final Float32List velocity = Float32List(bins);

  double totalEnergy = 0.0;

  /// Accepts `frame.bands` directly from the engine. The pipeline
  /// already delivers per-band values that are:
  ///   - log-spaced (20 Hz..20 kHz geometric bands)
  ///   - dB-clipped and normalised to [0, 1]
  ///   - asymmetrically EMA-smoothed (attack 0.5, release 0.1)
  ///
  /// Per the official mpv_audio_kit example: "No AnimationController
  /// needed — painting the values directly produces the bouncy
  /// visualizer feel." We add only a display-layer spring for extra
  /// recoil on decay, but do NOT re-process the signal.
  void ingest(Float32List bands) {
    if (bands.isEmpty) return;
    double energy = 0.0;

    final int n = bands.length < bins ? bands.length : bins;
    for (var i = 0; i < n; i++) {
      final v = bands[i].clamp(0.0, 1.0);
      target[i] = v;
      energy += v;
    }
    for (var i = n; i < bins; i++) {
      target[i] = 0.0;
    }
    totalEnergy = energy / bins;
  }

  void clearTarget() {
    for (var i = 0; i < bins; i++) {
      target[i] = 0.0;
    }
    totalEnergy = 0.0;
  }

  /// Display-layer spring — adds visual recoil on decay without
  /// altering the engine's calibrated amplitude.
  ///
  /// - Rising: lerp 0.5 — matches the engine's attack coefficient so
  ///   the display tracks the signal without adding lag.
  /// - Falling: damped spring with floor bounce. Bars coast down with
  ///   a tiny recoil, settling in 2–3 cycles.
  bool tick() {
    var moving = totalEnergy > 0.001;

    for (var i = 0; i < bins; i++) {
      final diff = target[i] - smoothed[i];
      if (diff > 0) {
        // Rise: track the engine's smoothed output directly.
        smoothed[i] += diff * 0.5;
        velocity[i] = 0.0;
      } else {
        // Fall: spring decay with floor bounce.
        velocity[i] += diff * 0.12;
        velocity[i] *= 0.82;
        smoothed[i] += velocity[i];
        if (smoothed[i] < 0.0) {
          smoothed[i] = 0.0;
          velocity[i] = -velocity[i] * 0.3;
        }
      }
      if (smoothed[i] > 0.001 || velocity[i].abs() > 0.001) moving = true;
    }

    notifyListeners();
    return moving;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────────────────────

class _CombinedBarPainter extends CustomPainter {
  final _BlockNotifier fftNotifier;
  final _ScrubNotifier scrubNotifier;
  final Color playedColor;
  final Color unplayedColor;

  _CombinedBarPainter({
    required this.fftNotifier,
    required this.scrubNotifier,
    required this.playedColor,
    required this.unplayedColor,
  }) : super(repaint: Listenable.merge([fftNotifier, scrubNotifier]));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double midY    = size.height / 2;
    final double slotW   = size.width / _BlockNotifier.bins;
    final double barW    = (slotW * 0.7).clamp(1.0, 8.0);
    final double fillX   = scrubNotifier.displayProgress * size.width;
    final double maxBarH = midY * 0.8;
    final barRadius      = Radius.circular(barW / 2);

    final paint = Paint()..style = PaintingStyle.fill;

    // Path batching: 4 distinct paint states to prevent breaking the
    // Skia pipeline batch. Grouping by color avoids ~128 individual
    // drawRRect calls that thrash the GPU state.
    final topPlayedPath    = Path();
    final topUnplayedPath  = Path();
    final refPlayedPath    = Path();
    final refUnplayedPath  = Path();

    for (var i = 0; i < _BlockNotifier.bins; i++) {
      final level = fftNotifier.smoothed[i];
      if (level < 0.01) continue;

      final cx   = (i + 0.5) * slotW;
      final x    = cx - barW / 2;
      final barH = (level * maxBarH).clamp(2.0, maxBarH);
      final isPlayed = cx <= fillX;

      final topRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, midY - barH, barW, barH),
        barRadius,
      );
      final refRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, midY + 2.0, barW, barH * 0.4),
        barRadius,
      );

      if (isPlayed) {
        topPlayedPath.addRRect(topRect);
        refPlayedPath.addRRect(refRect);
      } else {
        topUnplayedPath.addRRect(topRect);
        refUnplayedPath.addRRect(refRect);
      }
    }

    // Render 4 batched draw calls instead of ~128 individual ones.
    canvas.drawPath(topPlayedPath, paint..color = playedColor);
    canvas.drawPath(topUnplayedPath, paint..color = unplayedColor);
    canvas.drawPath(
        refPlayedPath, paint..color = playedColor.withValues(alpha: 0.35));
    canvas.drawPath(
        refUnplayedPath, paint..color = unplayedColor.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(covariant _CombinedBarPainter old) =>
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}

class _ScrubOverlayPainter extends CustomPainter {
  final _ScrubNotifier notifier;
  final Color playedColor;
  final Color unplayedColor;

  _ScrubOverlayPainter({
    required this.notifier,
    required this.playedColor,
    required this.unplayedColor,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final midY  = size.height / 2;
    final fillW = notifier.displayProgress * size.width;

    // 1. Track background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, midY - 1.5, size.width, 3),
        const Radius.circular(1.5),
      ),
      Paint()..color = unplayedColor.withValues(alpha: 0.20),
    );

    // 2. Tail — fading gradient from transparent to playedColor.
    if (fillW > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, midY - 1.5, fillW, 3),
          const Radius.circular(1.5),
        ),
        Paint()
          ..shader = LinearGradient(
            colors: [
              playedColor.withValues(alpha: 0.0),
              playedColor,
            ],
          ).createShader(Rect.fromLTWH(0, midY - 1.5, fillW, 3)),
      );
    }

    // 3. Playhead flare.
    if (fillW > 0) {
      final cx      = fillW.clamp(0.0, size.width);
      final isDrag  = notifier.dragging;

      // Ambient glow.
      canvas.drawCircle(
        Offset(cx, midY),
        isDrag ? 24.0 : 12.0,
        Paint()
          ..color = playedColor.withValues(alpha: isDrag ? 0.30 : 0.15)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, isDrag ? 12.0 : 8.0),
      );

      // Horizontal light flare — the "star" streak.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, midY),
          width:  isDrag ? 48.0 : 20.0,
          height: 3.0,
        ),
        Paint()
          ..color = playedColor.withValues(alpha: 0.9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );

      // White-hot core during drag.
      if (isDrag) {
        canvas.drawCircle(
          Offset(cx, midY),
          4.0,
          Paint()..color = Colors.white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubOverlayPainter old) =>
      old.playedColor != playedColor || old.unplayedColor != unplayedColor;
}
