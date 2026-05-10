import 'package:flutter/material.dart';

import '../core/jellyfin/models/quality.dart';
import '../design_tokens/tokens.dart';

/// Quality chip — mono-font, honest. Shown on the active track row's right
/// side and in Now Playing's metadata block.
///
/// Per non-negotiable §4.1: NEVER fake "high quality" badges. The label
/// reflects what the server actually delivers (FLAC 24/96 vs AAC 192
/// transcoded), and the warning border appears whenever the audio path
/// is degraded.
class QualityChip extends StatelessWidget {
  final TrackQuality quality;
  final bool compact;

  const QualityChip({
    super.key,
    required this.quality,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AfSpacing.s8 : AfSpacing.s12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: AfColors.surfaceHigh,
        borderRadius: AfRadii.borderPill,
        border: quality.isDegraded
            ? Border.all(color: AfColors.semanticWarning, width: 1)
            : null,
      ),
      child: Text(
        quality.chipLabel,
        style: AfTypography.mono.copyWith(
          color: AfColors.textSecondary,
          fontSize: compact ? 10 : 11,
        ),
      ),
    );
  }
}
