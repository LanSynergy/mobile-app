# Design Implementation Plan: 4-Target Visual Refresh

## Summary
- **Scope:** 4 screens (Library, Playlist, Settings, EQ/DSP)
- **Date:** 2026-06-02
- **Method:** Design and Refine — 5 variants per target, user-selected winners

## Winners

| Target | Winner | Pattern | File |
|--------|--------|---------|------|
| Library | E | Premium Expressive | `lib/features/library/library_screen.dart` |
| Playlist | D | Dashboard | `lib/features/playlist/playlist_screen.dart` |
| Settings | B | iOS-Style | `lib/features/settings/settings_screen.dart` |
| EQ/DSP | D | Accordion Sections | `lib/features/now_playing/eq_dsp_screen.dart` + `eq_dsp_widgets.dart` |

---

## Library — Premium Expressive (Variant E)

### Changes Applied
- **Title**: ShaderMask gradient (indigo300 → indigo500) on "Library" text
- **Tab indicator**: Glow-dot pattern (8dp circle, indigo400, BoxShadow blur 8/spread 2)
- **Album cards**: Glass-morphism (gradient overlay, surfaceHigh border, indigo shadow, bottom gradient with text)
- **Artist cards**: Circular with indigo300 border ring, user icon, name below
- **Genre tiles**: LinearGradient from genre tint (0.7 → 0.2 alpha)
- **Playlist rows**: surfaceRaised bg, gradient leading icon, title/subtitle
- **Press scale**: All tappable items scale to 1.02 on tap

### Component API
- `_AlbumCard` — glass-morphism album tile (private)
- `_ArtistCard` — circular artist tile with ring (private)
- `_GenreCard` — gradient genre tile (private)
- `_PlaylistCard` — elevated playlist row (private)
- Restyled `_SegmentedPill` — glow-dot indicator

---

## Playlist — Dashboard (Variant D)

### Changes Applied
- **Hero**: Centered 128dp artwork with indigo gradient + 32dp shadow
- **Name**: Centered below artwork, titleLarge
- **Stats**: Mono badge row (tracks · duration · artists) — surfaceLow bg, surfaceHigh border
- **Controls**: Segmented pill (Play | Shuffle) — indigo600 when selected
- **Track container**: surfaceRaised bg, rounded top corners (AfRadii.xl)
- **Track numbers**: Overline text, 32dp wide, centered
- **Active track**: indigo900 at 0.3 alpha background
- **Drag handle**: textDisabled, 18dp

### Component API
- `_StatBadge` — mono stat chip (private)
- `_SegmentedControl` — Play/Shuffle toggle (private)
- `_DashboardTrackRow` — numbered track row with overline index (private)
- `_Pressable` — scale-on-press wrapper (private)

---

## Settings — iOS-Style (Variant B)

### Changes Applied
- **Header**: Large title (titleLarge) with s56 top padding, no AppBar
- **Sections**: UPPERCASE bold headers (titleSmall)
- **Groups**: Continuous rounded corners (first/last/middle pattern)
- **Tiles**: 32dp rounded-square icon containers (surfaceHigh bg), chevron disclosure
- **Switches**: indigo500 active track, textOnPrimary thumb
- **Danger items**: semanticError icon container + title text
- **Footer**: Caption text with version info
- **Values**: Trailing mono text for current settings values

### Component API
- `_IosGroup` — continuous rounded-corner group container (private)
- `_IosTile` — iOS-style setting tile with icon container + chevron (private)
- `_IosSwitch` — tile with inline switch (private)
- `_IconContainer` — 32dp rounded-square icon wrapper (private)
- `_Chevron` — disclosure indicator (private)
- `_SectionHeader` — bold uppercase section label (private)

---

## EQ/DSP — Accordion Sections (Variant D)

### Changes Applied
- **Master banner**: Gradient bg (indigo700 → indigo900), glowing icon, custom toggle pill
- **Presets**: Horizontal scroll chips — surfaceBase bg, indigo600 at 0.3 active
- **Sections**: Single-open accordion pattern
  - Collapsed: surfaceLow bg, surfaceHigh border, UPPERCASE label
  - Open: surfaceBase bg, indigo600 at 0.4 border
  - Badge: pill with active effect count (indigo600 at 0.3 bg)
  - Chevron: AnimatedRotation, AfDurations.quick
  - Content: AnimatedCrossFade, AfDurations.standard
- **Toggles**: Compact pill rows (44x26) — indigo500 when on, surfaceHigh when off
- **Sliders**: 72dp label, indigo300 mono value, trackHeight 2, thumbRadius 5

### Component API
- `EqMasterBanner` — gradient master toggle with glow (public, in eq_dsp_widgets.dart)
- `EqAccordionSection` — expandable section with badge (public, in eq_dsp_widgets.dart)
- Restyled `EqEffectToggle` — compact pill toggle (public, in eq_dsp_widgets.dart)
- Updated `EqSliderRow` — indigo300 mono, compact track (public, in eq_dsp_widgets.dart)

---

## Testing

### Test Results
- **417 passed** / 1 pre-existing failure (global_mini_player_overlay_test.dart — unrelated)

### Verification
- `dart analyze` — 0 issues
- `dart format` — all files formatted
- All existing functionality preserved:
  - Library: sorting, section switching, data providers, error/loading states
  - Playlist: reorder, dismiss, undo, rename, delete, export
  - Settings: all sections, dialogs, toggles, server/local mode
  - EQ/DSP: all 80+ state variables, apply/reset/preset logic, scroll absorb

---

## Design Tokens Used

All changes use ONLY existing `Af*` tokens:
- **Colors**: `AfColors.indigo50-1000`, `surfaceCanvas/Low/Base/Raised/High/Max`, `textPrimary/Secondary/Tertiary/Disabled/OnPrimary`, `semanticSuccess/Warning/Error`
- **Typography**: `AfTypography.display`, `titleLarge/Medium/Small`, `bodyLarge/Medium/Small`, `label`, `caption`, `mono`, `overline`
- **Spacing**: `AfSpacing.s2-s136`, `gutter`, `rhythm`, `sectionGap`, `minHitTarget`
- **Radii**: `AfRadii.xs-sm-md-lg-xl-rounded-pill`, `borderXs-pill`
- **Motion**: `AfCurves.easeStandard/easeEmphasized`, `AfDurations.instant/quick/standard/expressive`

---

*Generated by Design and Refine skill*
