import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Search Filters
//
// Extracted from search_screen.dart. Contains the SearchFilter enum (results
// scope) and IdleFilter enum (idle-state sub-filter), plus their chip widgets.
// ─────────────────────────────────────────────────────────────────────────────

/// Filter chips at the top of the results panel. Lets the user scope
/// to a single result type — when active, the per-type cap is lifted
/// so the full list is browsable (matches Spotify/Apple Music behavior).
enum SearchFilter { all, tracks, albums, artists, playlists }

extension SearchFilterExtension on SearchFilter {
  String get label => switch (this) {
    SearchFilter.all => 'All',
    SearchFilter.tracks => 'Tracks',
    SearchFilter.albums => 'Albums',
    SearchFilter.artists => 'Artists',
    SearchFilter.playlists => 'Playlists',
  };
}

/// Horizontal filter chip row. Renders once a query is committed and
/// scopes the results to a single category (lifting the per-type cap).
class SearchFilterChips extends ConsumerWidget {
  const SearchFilterChips({
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final SearchFilter selected;
  final ValueChanged<SearchFilter> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: SearchFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AfSpacing.s8),
        itemBuilder: (context, i) {
          final f = SearchFilter.values[i];
          final active = f == selected;
          return ChoiceChip(
            label: Text(f.label),
            selected: active,
            onSelected: (_) => onChanged(f),
            backgroundColor: AfColors.surfaceBase,
            selectedColor: spectral,
            labelStyle: AfTypography.bodySmall.copyWith(
              color: active ? AfColors.textOnPrimary : AfColors.textSecondary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AfRadii.borderPill,
              side: BorderSide(color: active ? spectral : AfColors.surfaceHigh),
            ),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s8,
              vertical: 0,
            ),
          );
        },
      ),
    );
  }
}

/// Sub-filter for the idle (empty-query) state — Artists | Genres | Albums.
enum IdleFilter { artists, genres, albums }

extension IdleFilterExtension on IdleFilter {
  String get label => switch (this) {
    IdleFilter.artists => 'Artists',
    IdleFilter.genres => 'Genres',
    IdleFilter.albums => 'Albums',
  };
}

/// Pill selector for the idle-state sub-filter.
class IdleFilterPills extends ConsumerWidget {
  const IdleFilterPills({
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final IdleFilter selected;
  final ValueChanged<IdleFilter> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: IdleFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AfSpacing.s8),
        itemBuilder: (context, i) {
          final f = IdleFilter.values[i];
          final active = f == selected;
          return GestureDetector(
            onTap: () => onChanged(f),
            child: AnimatedContainer(
              duration: AfDurations.quick,
              curve: AfCurves.easeStandard,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              decoration: BoxDecoration(
                color: active ? spectral : AfColors.surfaceRaised,
                borderRadius: AfRadii.borderPill,
              ),
              alignment: Alignment.center,
              child: Text(
                f.label,
                style: AfTypography.bodyMedium.copyWith(
                  color: active
                      ? AfColors.textOnPrimary
                      : AfColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
