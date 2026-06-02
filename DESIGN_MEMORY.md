# Design Memory

> This file captures reusable design decisions and patterns for Aetherfin.
> Read by the Design and Refine skill to skip redundant questions and ensure consistency.

## Brand Tone

### Adjectives
Premium, dark, immersive, artwork-forward

### Voice
Quiet confidence. Let the music and artwork speak. No visual noise.

### Avoid
- Cluttered/dense layouts
- Generic flat UI
- Material ripple effects
- Bouncy/spring physics

---

## Layout & Spacing

### Density
Comfortable — balanced between compact and spacious. 16dp gutters, 24dp section gaps.

### Grid System
4dp base unit. All spacing is a multiple of 4.

### Spacing Scale
- `s4` / `s8` / `s12` / `s16` / `s20` / `s24` / `s32` / `s40` / `s48` / `s64`
- `gutter`: 16dp (standard), 24dp (generous — Now Playing, Lyrics)
- `rhythm`: 8dp (sibling spacing)
- `sectionGap`: 24dp
- `minHitTarget`: 48dp

### Corner Radius
- `xs`: 4dp, `sm`: 8dp, `md`: 12dp, `lg`: 16dp, `xl`: 24dp
- `pill`: 999dp (buttons, chips, indicators)
- Hero cards use `xl` (24dp), standard cards use `lg` (16dp)

### Shadows
Depth through surface tone, NOT shadow-as-decoration. Use `surfaceCanvas` → `surfaceLow` → `surfaceBase` → `surfaceRaised` → `surfaceHigh` → `surfaceMax` scale.

---

## Typography

### Font Family
- **Headings:** Inter Variable (Google Fonts)
- **Body:** Inter Variable (Google Fonts)
- **Mono:** JetBrains Mono (Google Fonts) — bitrate, codec, hash readouts only

### Type Scale
- `display`: 32dp, w700, height 38/32, letterSpacing -0.4
- `titleLarge`: 24dp, w600, height 30/24
- `titleMedium`: 20dp, w600, height 26/20
- `titleSmall`: 16dp, w600, height 22/16
- `bodyLarge`: 16dp, w400, height 24/16
- `bodyMedium`: 14dp, w400, height 20/14
- `bodySmall`: 12dp, w400, height 16/12
- `label`: 12dp, w600, letterSpacing 0.4 — UPPERCASE in widget
- `caption`: 11dp, w400, letterSpacing 0.2

### Font Weights
- w400 (body), w500 (mono), w600 (titles), w700 (display)

---

## Color

### Primary Palette (Indigo, hue 275°)
- `indigo50` → `indigo1000`: 12-step scale
- `indigo600` (#6657D7): Primary action
- `indigo400` (#8276E0): Accent, highlights
- `indigo300` (#A89DEC): Subtle accents, artist rings

### Surface Scale (Nocturne)
- `surfaceCanvas` (#0B0B14): Background
- `surfaceLow` (#101020)
- `surfaceBase` (#15152A): Cards, inputs
- `surfaceRaised` (#1B1B36): Elevated cards
- `surfaceHigh` (#232347): Borders, dividers
- `surfaceMax` (#2C2C57): Disabled, tertiary

### Text Scale
- `textPrimary` (#F2F1F8): Body text
- `textSecondary` (#BFBED0): Secondary text
- `textTertiary` (#8C8AA3): Labels, captions
- `textDisabled` (#5E5C72)
- `textOnPrimary` (#F8F7FB): Text on primary buttons

### Semantic Colors
- **Success:** #5DCB87
- **Error:** #E26A53
- **Warning:** #D7B852
- **Info:** #6CB1D9

### Dark Mode
Dark-only ("Nocturne" theme). No light mode. Spectral accent from artwork at runtime.

---

## Interaction Patterns

### Press Feedback
- `PressScale` widget — scale + tint, no Material ripple
- `NoSplash.splashFactory` globally
- `highlightColor: Colors.transparent` globally

### Navigation
- `go_router` — `go()` for shell tabs, `push()` for detail screens
- Custom horizontal slide transition (slide + fade + scale)

### Loading States
- Shimmer skeletons per section type
- `AsyncErrorView.compact()` with retry

### Bottom Sheets
- Transparent background, `AfRadii.borderXl` top corners
- `AfColors.surfaceScrim` barrier

### Glass-Morphism (Library/EQ)
- BackdropFilter blur on preset chips (sigma 4-12)
- surfaceRaised at 0.6-0.7 alpha + surfaceHigh border at 0.3-0.5 alpha
- Used for: album cards, preset chips, artist overlays

### Gradient Accents
- Indigo gradient titles via ShaderMask (indigo300 → indigo500)
- Section headers glow: indigo400 text with Shadow(blur 8, alpha 0.3)
- Active elements: indigo500 border at 0.3-0.4 alpha + indigo400 glow shadow

### Accordion Pattern (EQ/DSP)
- Single-open: only one section expanded at a time
- Collapsed: surfaceLow bg, surfaceHigh border, UPPERCASE label
- Open: surfaceBase bg, indigo600 border at 0.4 alpha
- Badge pill: indigo600 at 0.3 bg, overline text, indigo400 color
- Chevron: AnimatedRotation 0.5 turns, AfDurations.quick

### Dashboard Pattern (Playlist)
- Centered 128dp hero artwork with shadow
- Mono stat badges (surfaceLow bg, surfaceHigh border, mono 10dp)
- Segmented control (Play | Shuffle) as single pill
- Track container: surfaceRaised bg, rounded top corners (AfRadii.xl)
- Overline track numbers (AfTypography.overline)

### iOS-Style Groups (Settings)
- Continuous rounded corners per group (first: top, last: bottom, middle: none)
- Rounded-square icon containers (32dp, surfaceHigh bg, AfRadii.borderSm)
- Chevron disclosure indicators (chevronRight, 16dp, textDisabled)
- Bold UPPERCASE section headers (AfTypography.titleSmall)
- Danger isolation: semanticError icon + title for destructive actions

---

## Accessibility Rules

### Focus Management
- `PressScale` with `ensureHitTarget: true` ensures 48dp hit targets
- Visible focus states via `:focus-visible` equivalent

### Labeling Conventions
- `Semantics` widget on all interactive elements
- `tooltip` on icon buttons

### Motion Preferences
- `MediaQuery.of(context).disableAnimations` check
- Reduced motion → instant fade only (no slide/scale)

### Color Contrast
- APCA targets: body Lc ≥ 60, secondary ≥ 45, tertiary ≥ 30
- Text colors chosen for contrast on Nocturne surfaces

---

## Repo Conventions

### Component Structure
- Feature-first: `lib/features/{feature}/{feature}_screen.dart`
- Widgets: `lib/widgets/{widget_name}.dart`
- State: `lib/state/{feature}_providers.dart`
- Core: `lib/core/{domain}/{domain}_client.dart`

### File Naming
- Snake_case for files
- PascalCase for classes
- `Af` prefix for design tokens (AfColors, AfTypography, etc.)

### Styling Approach
- All colors via `AfColors` — never hard-coded
- All typography via `AfTypography` — never hard-coded
- All spacing via `AfSpacing` — never hard-coded
- All radii via `AfRadii` — never hard-coded
- All motion via `AfCurves` / `AfDurations` — never hard-coded

### Existing Primitives
- `PressScale` — tap feedback
- `Artwork` — cached network image
- `MarqueeText` — scrolling long text
- `Tile` — generic album/artist tile
- `TrackRow` — track list item
- `SectionHeader` — title + action
- `StaggerReveal` — staggered fade-in
- `GenreTile` — genre chip
- `HeroAlbumCard` — hero album card
- `EqMasterBanner` — gradient master toggle banner with glow
- `EqAccordionSection` — single-open accordion with badge count
- `EqEffectToggle` — compact pill toggle row (title + subtitle + custom switch)

---

## Do / Don't

### Do
- Use `AfColors` / `AfTypography` / `AfSpacing` tokens
- Use `PressScale` for all tappable elements
- Use `Semantics` for accessibility
- Use `ClampingScrollPhysics` (no bouncy physics)
- Use `NoSplash.splashFactory` (no Material ripple)
- Keep 48dp minimum hit targets

### Don't
- Hard-code colors in widgets
- Use Material ripple effects
- Use bouncy/spring scroll physics
- Put shadow-as-decoration (use surface depth instead)
- Use `just_audio` (use `mpv_audio_kit`)
- Use `json_serializable` (hand-write models)
- Use `ChangeNotifier` for state (use Riverpod)

---

### Full-Bleed Immersive (Now Playing)
- Artwork fills screen edge-to-edge via `BoxFit.cover` on background
- Gradient scrim: bottom 65%, transparent → surfaceCanvas at 0.92 alpha
- Frosted top bar: `BackdropFilter` blur 20, white 0.08 bg, `AfRadii.borderPill`
- Frosted bottom panel: `BackdropFilter` blur 30, `surfaceCanvas` at 0.72 alpha
- Bottom panel contains: metadata → AudioVisualScrubber → time → transport → utility
- Mini artwork thumbnail (48dp) in metadata row
- Transport: prev · play(60dp white circle) · next · shuffle · repeat
- A-B loop REMOVED from main view → lives in More sheet
- No scroll — artwork is absolute background, panel is fixed bottom

---

## History

| Date | Change | Context |
|------|--------|---------|
| 2026-06-02 | Initial creation | Home screen redesign — Variant E (Premium Expressive) |
| 2026-06-02 | Library + Playlist + Settings + EQ/DSP redesigns | 4-target visual refresh batch |
| 2026-06-02 | Now Playing redesign — Variant F (Full-Bleed + Visualizer) | Artwork-dominant, A-B loop moved to More |

---

*Maintained by Design and Refine skill*
