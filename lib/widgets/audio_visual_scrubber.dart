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
    final spectral = ref.watch(currentSpectralProvider);
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
                  glow:          spectral.glow,
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

  // Cyan → magenta gradient stops. Pure visualizer signature — not
  // derived from spectral or player accent. Bass punches cyan on the
  // left, treble ripples magenta on the right.
  static const Color gradientLeft  = Color(0xFF00E5FF); // cyan
  static const Color gradientRight = Color(0xFFFF3DDC); // magenta

  /// Target values received from `Player.stream.spectrum.bands`. The
  /// player pipeline delivers these already:
  ///   - log-spaced (20 Hz..20 kHz geometric bands)
  ///   - dB-clipped and normalised to `[0, 1]`
  ///   - EMA-smoothed asymmetrically (fast attack / slow release)
  ///
  /// We trust that DSP and only apply a visual motion model on top.
  final Float32List target   = Float32List(bins);

  /// Renderable bar height (what the painter reads). Separate from
  /// [target] so we can overlay a spring-based motion model — the
  /// "fast attack, bouncy decay" feel — without touching the engine's
  /// signal path.
  final Float32List smoothed = Float32List(bins);

  /// Per-bin velocity, driven by the spring model during decay.
  final Float32List velocity = Float32List(bins);

  double totalEnergy = 0.0;

  /// Accepts a frame's bands directly. If the frame's bandCount does
  /// not match [bins] we linearly resample, but the player is
  /// configured for 64 bands so this is a cheap passthrough copy in
  /// the happy path.
  void ingest(Float32List bands) {
    if (bands.isEmpty) return;
    double energy = 0.0;

    if (bands.length == bins) {
      for (var i = 0; i < bins; i++) {
        final v = bands[i];
        target[i] = v.isFinite ? v.clamp(0.0, 1.0) : 0.0;
        energy += target[i];
      }
    } else {
      // Fallback: linear resample. The player config pins bandCount
      // to 64 so this only runs if the settings drift out of sync.
      final scale = bands.length / bins;
      for (var i = 0; i < bins; i++) {
        final idx = (i * scale).floor().clamp(0, bands.length - 1);
        final v = bands[idx];
        target[i] = v.isFinite ? v.clamp(0.0, 1.0) : 0.0;
        energy += target[i];
      }
    }
    totalEnergy = energy / bins;
  }

  void clearTarget() {
    for (var i = 0; i < bins; i++) {
      target[i] = 0.0;
    }
    totalEnergy = 0.0;
  }

  /// Returns true if any bar (or its velocity) is still moving.
  ///
  /// Motion model — "fast attack, bouncy decay":
  /// - Rising target: snap toward target at 0.6 (punchy transient).
  /// - Falling target: damped spring with floor bounce. Velocity
  ///   accumulates downward, hits the 0 floor, reverses with 35%
  ///   restitution, damping eats the oscillation in 2–3 cycles.
  ///
  /// The engine already smoothed the bands with its own EMA. This
  /// spring is a *display* layer on top — it adds the visual recoil
  /// without changing the underlying dB-calibrated amplitude.
  bool tick() {
    const double attack      = 0.6;
    const double stiffness   = 0.18;
    const double damping     = 0.82;
    const double restitution = 0.35;

    var moving = totalEnergy > 0.001;

    for (var i = 0; i < bins; i++) {
      final diff = target[i] - smoothed[i];
      if (diff > 0) {
        smoothed[i] += diff * attack;
        velocity[i] = 0.0;
      } else {
        velocity[i] += diff * stiffness;
        velocity[i] *= damping;
        smoothed[i] += velocity[i];
        if (smoothed[i] < 0.0) {
          smoothed[i] = 0.0;
          velocity[i] = -velocity[i] * restitution;
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
  final Color glow;

  _CombinedBarPainter({
    required this.fftNotifier,
    required this.scrubNotifier,
    required this.glow,
  }) : super(repaint: Listenable.merge([fftNotifier, scrubNotifier]));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double midY    = size.height / 2;
    final double slotW   = size.width / _BlockNotifier.bins;
    final double barW    = (slotW * 0.55).clamp(1.0, 6.0);
    final double maxBarH = midY * 0.9;
    final barRadius      = Radius.circular(barW / 2);

    // Shared cyan → magenta gradient for the whole strip. Bars inherit
    // their color from their horizontal position so bass punches cyan
    // and treble ripples magenta, consistent left to right.
    final gradientShader = LinearGradient(
      colors: const [
        _BlockNotifier.gradientLeft,
        _BlockNotifier.gradientRight,
      ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final paint = Paint()
      ..style  = PaintingStyle.fill
      ..shader = gradientShader;

    // Background radial glow — uses the spectral token so the scene still
    // follows the cover art even though the bars themselves are fixed.
    if (fftNotifier.totalEnergy > 0.05) {
      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, midY),
        width:  size.width,
        height: size.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              glow.withValues(alpha: fftNotifier.totalEnergy * 0.30),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
    }

    // Mirrored solid bars — same geometry above and below the axis.
    for (var i = 0; i < _BlockNotifier.bins; i++) {
      final level = fftNotifier.smoothed[i];
      if (level < 0.01) continue;

      final cx   = (i + 0.5) * slotW;
      final x    = cx - barW / 2;
      final barH = (level * maxBarH).clamp(2.0, maxBarH);

      // Top half — grows upward from axis.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY - barH, barW, barH),
          barRadius,
        ),
        paint,
      );

      // Bottom half — true mirror. Same height, same geometry.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY, barW, barH),
          barRadius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CombinedBarPainter old) => old.glow != glow;
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
