import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

class AudioVisualScrubber extends ConsumerStatefulWidget {

  const AudioVisualScrubber({
    super.key,
    this.height        = 120,
    required this.progress,
    this.playedColor   = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.onScrub,
    this.onScrubEnd,
  });
  final double height;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;

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

    _lifecycle = AppLifecycleListener(
      onPause:  () { _isAppBackground = true; _ticker.stop(); },
      onResume: () {
        _isAppBackground = false;
        if (_fftNotifier.hasEnergy) _ticker.repeat();
      },
    );

    // Ticker drives repaints at vsync (60 fps). Stream events just update
    // data; the ticker ensures frame-aligned rendering so the visualizer
    // doesn't stutter from async stream timing misalignment.
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(() {
        if (mounted) _fftNotifier.flush();
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fftSub = ref.read(playerServiceProvider).spectrumStream.listen(
        (frame) {
          if (!_shouldRender) return;
          _silenceTimer?.cancel();
          // Update data only — ticker handles the repaint on vsync.
          _fftNotifier.ingest(frame.bands);
          if (!_ticker.isAnimating) _ticker.repeat();
          _silenceTimer = Timer(const Duration(milliseconds: 300), () {
            if (mounted && _shouldRender) {
              _fftNotifier.startFadeOut();
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

  _ScrubNotifier({required double progress}) : _progress = progress;
  double _progress;
  bool   _dragging     = false;
  double _dragProgress = 0.0;

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
  static const int _lutSize = 1024;

  static final Float32List _pow10Lut = Float32List(_lutSize);
  static bool _lutReady = false;

  static void _initLut() {
    if (_lutReady) return;
    for (var i = 0; i < _lutSize; i++) {
      _pow10Lut[i] = math.pow(i / (_lutSize - 1), 10.0).toDouble();
    }
    _lutReady = true;
  }

  final Float32List smoothed = Float32List(bins);

  double totalEnergy = 0.0;
  bool _fadingOut = false;
  bool _dirty = false;

  bool get hasEnergy => totalEnergy > 0.001;

  /// Updates bar data from engine bands. Does NOT call notifyListeners —
  /// the ticker calls flush() on vsync to trigger the repaint at a
  /// steady frame rate regardless of stream event timing.
  void ingest(Float32List bands) {
    _fadingOut = false;
    if (bands.isEmpty) return;
    if (!_lutReady) _initLut();

    double energy = 0.0;
    final int n = bands.length < bins ? bands.length : bins;
    for (var i = 0; i < n; i++) {
      final idx = (bands[i].clamp(0.0, 1.0) * (_lutSize - 1)).round();
      final v = _pow10Lut[idx];
      smoothed[i] = v;
      energy += v;
    }
    for (var i = n; i < bins; i++) {
      smoothed[i] = 0.0;
    }
    totalEnergy = energy / bins;
    _dirty = true;
  }

  /// Called by the ticker on every vsync. Fires notifyListeners only if
  /// data changed since last flush — guarantees frame-aligned repaints
  /// at a steady 60 fps regardless of stream event timing.
  void flush() {
    if (_fadingOut) {
      _tickFadeOut();
      return;
    }
    if (_dirty) {
      _dirty = false;
      notifyListeners();
    }
  }

  /// Start the fade-out animation (called when audio goes silent).
  void startFadeOut() {
    _fadingOut = true;
    _dirty = false;
  }

  void _tickFadeOut() {
    bool moving = false;
    double energy = 0.0;

    for (var i = 0; i < bins; i++) {
      if (smoothed[i] > 0.001) {
        smoothed[i] *= 0.85;
        moving = true;
      } else {
        smoothed[i] = 0.0;
      }
      energy += smoothed[i];
    }
    totalEnergy = energy / bins;
    notifyListeners();

    if (!moving) _fadingOut = false;
  }

  void clearTarget() {
    for (var i = 0; i < bins; i++) {
      smoothed[i] = 0.0;
    }
    totalEnergy = 0.0;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────────────────────

class _CombinedBarPainter extends CustomPainter {

  _CombinedBarPainter({
    required this.fftNotifier,
    required this.scrubNotifier,
    required this.playedColor,
    required this.unplayedColor,
  }) : super(repaint: Listenable.merge([fftNotifier, scrubNotifier]));
  final _BlockNotifier fftNotifier;
  final _ScrubNotifier scrubNotifier;
  final Color playedColor;
  final Color unplayedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double midY    = size.height / 2;
    final double slotW   = size.width / _BlockNotifier.bins;
    final double barW    = (slotW * 0.7).clamp(1.0, 8.0);
    final double rawFillX = scrubNotifier.displayProgress * size.width;
    // When FFT bars are active (music is playing), ensure at least the
    // first bar slot is colored so the visualizer doesn't go fully grey
    // when position briefly resets to 0 during track transitions.
    final double fillX   = fftNotifier.hasEnergy
        ? math.max(rawFillX, slotW * 0.75)
        : (fftNotifier.totalEnergy > 0 ? rawFillX : 0.0);
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
      
      // Fix: Calculates play state natively by comparing bar center to scrub position
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

  _ScrubOverlayPainter({
    required this.notifier,
    required this.playedColor,
    required this.unplayedColor,
  }) : super(repaint: notifier);
  final _ScrubNotifier notifier;
  final Color playedColor;
  final Color unplayedColor;

  double? _cachedFillW;
  Color? _cachedPlayedColor;
  Shader? _cachedShader;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final midY  = size.height / 2;
    final fillW = (notifier.displayProgress * size.width).clamp(0.0, size.width);

    // 1. Track background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, midY - 1.5, size.width, 3),
        const Radius.circular(1.5),
      ),
      Paint()..color = unplayedColor.withValues(alpha: 0.20),
    );

    // 2. Tail — fading gradient from transparent to playedColor.
    // Only draw if there's actually a filled portion (fillW > 1 px).
    if (fillW > 1) {
      if (_cachedShader == null ||
          _cachedFillW != fillW ||
          _cachedPlayedColor != playedColor) {
        _cachedFillW = fillW;
        _cachedPlayedColor = playedColor;
        _cachedShader = LinearGradient(
          colors: [
            playedColor.withValues(alpha: 0.0),
            playedColor,
          ],
        ).createShader(Rect.fromLTWH(0, midY - 1.5, fillW, 3));
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, midY - 1.5, fillW, 3),
          const Radius.circular(1.5),
        ),
        Paint()..shader = _cachedShader,
      );
    }

    // 3. Playhead shine — bright star-like point that reads as "shining"
    // rather than just a soft glow. Layers: outer glow → horizontal
    // streak → vertical cross-streak → white-hot core.
    {
      // Ensure the playhead center is at least the core radius from the
      // left edge so glow effects aren't clipped by Stack.hardEdge.
      final cx     = math.max(fillW, 2.5);
      final isDrag = notifier.dragging;

      // Outer ambient glow (soft, wide).
      canvas.drawCircle(
        Offset(cx, midY),
        isDrag ? 28.0 : 16.0,
        Paint()
          ..color = playedColor.withValues(alpha: isDrag ? 0.35 : 0.20)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, isDrag ? 14.0 : 10.0),
      );

      // Horizontal light streak — the main "shine" ray.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, midY),
          width: isDrag ? 56.0 : 28.0,
          height: 2.5,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
      );

      // Vertical cross-streak — gives the star/diamond shape.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, midY),
          width: 2.5,
          height: isDrag ? 24.0 : 14.0,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
      );

      // White-hot core — always visible, brighter during drag.
      canvas.drawCircle(
        Offset(cx, midY),
        isDrag ? 4.0 : 2.5,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubOverlayPainter old) =>
      old.playedColor != playedColor || old.unplayedColor != unplayedColor;
}
