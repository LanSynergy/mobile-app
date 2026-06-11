import 'dart:async';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../design_tokens/tokens.dart';
import '../state/animated_spectral.dart';

/// Frosted-glass card — [ClipRRect] + [BackdropFilter] + semi-transparent fill.
///
/// Reusable across now-playing bottom content, top bar, or any overlay
/// that needs to read over album art / dynamic backgrounds.
///
/// ## Blur snapshot caching
///
/// [BackdropFilter] re-rasters the blurred background every frame, which is
/// expensive on the Now Playing screen (sigma 30). The blur only changes when
/// the spectral colors (background gradient) change — during track transitions
/// (~300 ms every few seconds). During static playback the blur output is
/// identical frame-to-frame.
///
/// **Strategy:** On first render (or when spectral colors change), the live
/// [BackdropFilter] is rendered inside a [RepaintBoundary]. After the frame
/// paints, we capture the blurred area via [RenderRepaintBoundary.toImage]
/// and store it as a [ui.Image]. On subsequent frames, if the spectral hash
/// is unchanged and the cache is valid, we draw the cached image via
/// [DecorationImage] instead of running the live [BackdropFilter]. This avoids
/// redundant GPU blur rasterization during the vast majority of playback time
/// where the background is static.
///
/// **Invalidation:** The cache is invalidated whenever `animatedSpectral`
/// emits a [Spectral] whose [hashCode] differs from the last captured value.
/// This happens at the start/end of each track transition. The glass fill
/// overlay and child are always rendered live (never cached) so interactive
/// elements remain responsive.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = AfRadii.borderLg,
    this.blurSigma = 16,
    this.color = AfColors.glassFillHeavy,
    this.borderColor,
    this.borderWidth = 0.5,
    this.padding = const EdgeInsets.all(AfSpacing.s16),
    this.margin,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color color;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  /// Key for the [RepaintBoundary] wrapping the live [BackdropFilter].
  /// Used to access [RenderRepaintBoundary.toImage] for snapshot capture.
  final GlobalKey _blurKey = GlobalKey();

  /// Cached snapshot of the blurred background area.
  /// Only the blur is cached — the glass fill and child are always live.
  ui.Image? _cachedBlurImage;

  /// Hash of the last [Spectral] value that triggered a cache capture.
  /// Compared against `animatedSpectral.value.hashCode` to detect changes.
  int? _lastSpectralHash;

  /// Monotonically increasing counter to discard stale capture callbacks.
  /// If spectral changes before a pending capture completes, the stale
  /// callback is discarded via this counter.
  int _captureGeneration = 0;

  @override
  void dispose() {
    _cachedBlurImage?.dispose();
    super.dispose();
  }

  /// Captures the blurred background from the [RepaintBoundary] and stores
  /// it in [_cachedBlurImage]. Scheduled as a post-frame callback so the
  /// live [BackdropFilter] has already painted.
  void _captureBlurSnapshot() {
    final generation = ++_captureGeneration;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _captureGeneration != generation) return;
      final renderObject = _blurKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return;

      renderObject.toImage(pixelRatio: 1).then((ui.Image image) {
        if (!mounted || _captureGeneration != generation) {
          image.dispose();
          return;
        }
        final ui.Image? previous = _cachedBlurImage;
        setState(() {
          _cachedBlurImage = image;
        });
        // Defer disposal of the previous snapshot to after the next frame
        // paints, ensuring the old [DecorationImage] (holding the previous
        // [ImageInfo]) has been replaced and its reference released.
        if (previous != null) {
          SchedulerBinding.instance.addPostFrameCallback(
            (_) => previous.dispose(),
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Spectral>(
      valueListenable: animatedSpectral,
      builder: (context, spectral, _) {
        final currentHash = spectral.hashCode;
        final spectralChanged = currentHash != _lastSpectralHash;
        _lastSpectralHash = currentHash;

        final useCache = !spectralChanged && _cachedBlurImage != null;

        if (!useCache) {
          // Spectral changed or first build — render live [BackdropFilter]
          // and schedule a snapshot capture for future frames.
          _captureBlurSnapshot();
        }

        return Padding(
          padding: widget.margin ?? EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Blur layer ──
                if (useCache)
                  // Cache hit: draw the pre-captured blurred background via
                  // [DecorationImage]. Avoids re-running the expensive
                  // [BackdropFilter] GPU rasterization.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: _CachedBlurImageProvider(_cachedBlurImage!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                else
                  // Cache miss: render live [BackdropFilter] for capture.
                  // The [RepaintBoundary] allows us to snapshot just the
                  // blurred backdrop without the glass fill or child.
                  RepaintBoundary(
                    key: _blurKey,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: widget.blurSigma,
                        sigmaY: widget.blurSigma,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),

                // ── Glass fill + content (always live) ──
                // Rendered on top of the blur layer (cached or live).
                // Always live so interactive elements remain responsive.
                Container(
                  padding: widget.padding,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: widget.borderRadius,
                    border: widget.borderColor != null
                        ? Border.all(
                            color: widget.borderColor!,
                            width: widget.borderWidth,
                          )
                        : null,
                  ),
                  child: widget.child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ImageProvider for an already-decoded [ui.Image].
// ---------------------------------------------------------------------------

/// Wraps a pre-captured [ui.Image] as an [ImageProvider] so it can be used
/// with [DecorationImage]. The image is already decoded (captured via
/// [RenderRepaintBoundary.toImage]), so no decoding step is needed.
class _CachedBlurImageProvider extends ImageProvider<_CachedBlurImageProvider> {
  _CachedBlurImageProvider(this._image);
  final ui.Image _image;

  @override
  Future<_CachedBlurImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedBlurImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return _CachedBlurImageStreamCompleter(key._image);
  }

  @override
  String toString() =>
      '${describeIdentity(this)} (blur snapshot, ${_image.width}x${_image.height})';
}

/// An [ImageStreamCompleter] that immediately emits an already-decoded
/// [ui.Image] without re-decoding.
class _CachedBlurImageStreamCompleter extends ImageStreamCompleter {
  _CachedBlurImageStreamCompleter(ui.Image image) {
    // Emit the image immediately — no codec/decode step needed.
    setImage(ImageInfo(image: image));
  }
}
