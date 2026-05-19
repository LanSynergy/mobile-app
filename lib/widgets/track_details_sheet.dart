import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../core/jellyfin/models/quality.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/time_format.dart';

/// Shows a bottom-sheet with full song metadata + file details.
///
/// Called from the track context menu ("Show details") and from the
/// Now Playing screen's "More" dialog. Fetches [trackDetailsProvider]
/// lazily — the sheet renders the basic [AfTrack] info immediately and
/// appends the extended fields (file size, codec, channels, path, …)
/// once the network call resolves.
void showTrackDetailsSheet(BuildContext context, WidgetRef ref, AfTrack track) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AfColors.surfaceBase,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AfRadii.lg)),
    ),
    builder: (sheetCtx) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) => _TrackDetailsBody(
        track: track,
        scrollController: scrollController,
      ),
    ),
  );
}

class _TrackDetailsBody extends ConsumerWidget {
  final AfTrack track;
  final ScrollController scrollController;

  const _TrackDetailsBody({
    required this.track,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(trackDetailsProvider(track.id));

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.gutterGenerous,
        vertical: AfSpacing.s12,
      ),
      children: [
        // Grab handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: AfSpacing.s16),
            decoration: BoxDecoration(
              color: AfColors.textTertiary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header
        Text(
          track.title,
          style: AfTypography.titleSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          track.artistName,
          style: AfTypography.bodyMedium.copyWith(color: AfColors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: AfSpacing.s16),
        const Divider(height: 1, color: AfColors.surfaceHigh),
        const SizedBox(height: AfSpacing.s16),

        // ── Song metadata ───────────────────────────────────────
        _SectionTitle(label: 'Song info'),
        _DetailRow(label: 'Title', value: track.title),
        _DetailRow(label: 'Artist', value: track.artistName),
        _DetailRow(label: 'Album', value: track.albumName),
        if (track.trackNumber != null)
          _DetailRow(label: 'Track #', value: '${track.trackNumber}'),
        if (track.duration > Duration.zero)
          _DetailRow(
            label: 'Duration',
            value: formatTrackDuration(track.duration),
          ),
        if (track.dateAdded != null)
          _DetailRow(
            label: 'Date added',
            value: _formatDate(track.dateAdded!),
          ),

        // ── Extended details (async) ────────────────────────────
        detailsAsync.when(
          data: (details) {
            if (details == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (details.genres.isNotEmpty)
                  _DetailRow(
                    label: 'Genre',
                    value: details.genres.join(', '),
                  ),
                if (details.playCount != null)
                  _DetailRow(
                    label: 'Play count',
                    value: '${details.playCount}',
                  ),
                if (details.lastPlayedAt != null)
                  _DetailRow(
                    label: 'Last played',
                    value: _formatDate(details.lastPlayedAt!),
                  ),

                const SizedBox(height: AfSpacing.s16),
                const Divider(height: 1, color: AfColors.surfaceHigh),
                const SizedBox(height: AfSpacing.s16),

                // ── File details ────────────────────────────────
                _SectionTitle(label: 'File details'),
                if (details.container != null)
                  _DetailRow(
                    label: 'Container',
                    value: details.container!.toUpperCase(),
                  ),
                if (track.quality != null)
                  _DetailRow(
                    label: 'Codec',
                    value: track.quality!.sourceCodec.toUpperCase(),
                  ),
                if (details.bitrateBps != null)
                  _DetailRow(
                    label: 'Bitrate',
                    value: '${details.bitrateBps! ~/ 1000} kbps',
                  ),
                if (details.sampleRateHz != null)
                  _DetailRow(
                    label: 'Sample rate',
                    value: _formatSampleRate(details.sampleRateHz!),
                  ),
                if (details.bitDepth != null)
                  _DetailRow(
                    label: 'Bit depth',
                    value: '${details.bitDepth}-bit',
                  ),
                if (details.formattedChannels != null)
                  _DetailRow(
                    label: 'Channels',
                    value: details.formattedChannels!,
                  ),
                if (details.formattedSize != null)
                  _DetailRow(
                    label: 'File size',
                    value: details.formattedSize!,
                  ),
                if (details.path != null)
                  _DetailRow(
                    label: 'Path',
                    value: details.path!,
                    selectable: true,
                  ),
              ],
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: AfSpacing.s24),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AfColors.indigo300,
                ),
              ),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
        ),

        // ── Quality badge fallback (when no extended details) ───
        if (track.quality != null)
          detailsAsync.maybeWhen(
            data: (d) => d != null ? const SizedBox.shrink() : _qualityFallback(track.quality!),
            orElse: () => const SizedBox.shrink(),
          ),

        const SizedBox(height: AfSpacing.s24),
      ],
    );
  }

  Widget _qualityFallback(TrackQuality q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AfSpacing.s16),
        const Divider(height: 1, color: AfColors.surfaceHigh),
        const SizedBox(height: AfSpacing.s16),
        _SectionTitle(label: 'File details'),
        _DetailRow(label: 'Codec', value: q.sourceCodec.toUpperCase()),
        if (q.bitrateKbps != null)
          _DetailRow(label: 'Bitrate', value: '${q.bitrateKbps} kbps'),
        if (q.bitDepth != null)
          _DetailRow(label: 'Bit depth', value: '${q.bitDepth}-bit'),
        if (q.sampleRateKhz != null)
          _DetailRow(label: 'Sample rate', value: '${q.sampleRateKhz} kHz'),
      ],
    );
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static String _formatSampleRate(int hz) {
    if (hz % 1000 == 0) return '${hz ~/ 1000} kHz';
    return '${(hz / 1000).toStringAsFixed(1)} kHz';
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s12),
      child: Text(
        label,
        style: AfTypography.caption.copyWith(
          color: AfColors.indigo300,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool selectable;

  const _DetailRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueWidget = selectable
        ? SelectableText(
            value,
            maxLines: 3,
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          )
        : Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
