# Design Implementation Plan: Now Playing Redesign

## Summary
- **Scope:** Page (full screen)
- **Target:** `lib/features/now_playing/now_playing_screen.dart`
- **Winner:** Variant F — Full-Bleed Immersive + Visualizer
- **Key improvements:** Artwork-dominant Roon-inspired layout, A-B loop removed from main view, frosted glass controls, modern premium feel

## Architecture Changes

### Current → New Layout Model
```
Current:  Column (vertical stack, artwork ~35% height)
New:      Stack (artwork fills screen, frosted bottom panel)
```

### Reactive Islands (PRESERVED)
The current architecture isolates high-frequency rebuilds to leaf widgets. This MUST be preserved:
- `NowPlayingScreen` → watches `currentTrackProvider` (skip only)
- `_ReactiveBackground` → watches `currentSpectralProvider` (color extraction)
- `_ReactiveArtwork` → watches `currentSpectralProvider` (artwork + pulse)
- `_ReactiveProgress` → watches `positionStreamProvider` (high-frequency)
- `_ReactiveTransport` → watches playing/shuffle/loop

## Files to Change

- [ ] `lib/features/now_playing/now_playing_screen.dart` — Major refactor
- [ ] `lib/features/now_playing/utility_row.dart` — Add A-B loop to More sheet
- [ ] `DESIGN_MEMORY.md` — Update interaction patterns

## Implementation Steps

### Step 1: Restructure layout (now_playing_screen.dart)
Replace `Column` layout with `Stack`:
1. `_ReactiveBackground` → fills entire screen (not just `color:`)
2. Add gradient scrim positioned at bottom 65%
3. Move `_TopBar` to positioned overlay (frosted pill)
4. Create new `_FrostedBottomPanel` container
5. Move metadata, progress, transport, utility into bottom panel

### Step 2: Redesign bottom panel
New widget `_FrostedBottomPanel`:
- `BackdropFilter` blur (sigma 30)
- `fixtureBackground` at 0.72 alpha
- Top border: white at 0.08 alpha
- Padding: 20h, 24v
- Contains: metadata → visualizer → time labels → transport → utility

### Step 3: Redesign metadata row
Replace `_MetadataRow`:
- Mini artwork thumbnail (48dp, `AfRadii.borderSm`)
- Title + artist in column
- Favorite icon button
- Quality chip badge (indigo accent bg)
- **Remove:** `_AbLoopButton` (moved to More sheet)
- **Remove:** `_NowPlayingMetaChip` sleep timer logic (keep in separate widget)

### Step 4: Redesign transport row
Replace `_TransportRow`:
- Single row: shuffle · skipBack · play/pause · skipForward · repeat
- Remove pill container background (let frosted panel handle it)
- Play button: 60dp, white, circular
- Transport buttons: 44dp hit targets
- Shuffle/Repeat show active state via spectral energy color

### Step 5: Redesign utility row
Replace `UtilityRow`:
- Row of 5 actions: Lyrics · EQ · Save · Queue · More
- Same icon + label pattern
- No visual changes needed (already clean)

### Step 6: Move A-B loop to More sheet (utility_row.dart)
Add A-B Loop as first item in `_MoreMenu`:
- Icon: `LucideIcons.arrowLeftRight`
- Label: "A-B Loop"
- Shows current state (A set / A+B active / off)
- Opens the existing A-B loop dialog
- Keep `abLoopAProvider` / `abLoopBProvider` providers unchanged

### Step 7: Top bar redesign
Refactor `_TopBar`:
- Frosted pill: `BackdropFilter` blur 20, white 0.08 bg
- Center: "PLAYING FROM ALBUM" overline + album name
- Left: chevron down (dismiss)
- Right: ellipsis (more menu)
- Keep album tap → navigate to album

### Step 8: Artwork changes
`_ReactiveArtwork`:
- Remove `UnconstrainedBox` wrapper (artwork fills available space)
- Keep Hero animation (`now-playing-artwork`)
- Keep sub-bass pulse animation
- Keep spectral glow shadow
- Artwork uses `BoxFit.cover` to fill background
- Size: fills screen (remove height clamping)

### Step 9: Remove scroll behavior
Current: scroll when `maxHeight < 620`
New: No scroll — frosted panel is fixed at bottom, artwork is absolute background
- Keep `LayoutBuilder` for responsive adjustments to bottom panel height
- Remove `SingleChildScrollView` branch

## Component API

### _FrostedBottomPanel (NEW)
- No props — reads all state from providers internally
- Internal: metadata, visualizer, time, transport, utility

### _MetadataRow (REFACTORED)
- Props: `AfTrack track`
- Removed: `_AbLoopButton`, `_NowPlayingMetaChip` inline
- Added: mini artwork thumbnail

### _TransportRow (REFACTORED)
- Props: `isPlaying`, `shuffleOn`, `shuffleMode`, `loopMode`, `accent`, callbacks
- Removed: pill container background

### A-B Loop (MOVED to More sheet)
- Existing `showAbLoopDialog` reused in `utility_row.dart`
- Added as first `MoreItem` in `_MoreMenu`

## Required UI States
- **Loading:** Artwork placeholder + skeleton (existing pattern)
- **Empty:** "Nothing playing yet" (existing)
- **Buffering:** Play button shows `CircularProgressIndicator` (existing)
- **Favorite:** Heart filled red (existing)

## Accessibility Checklist
- [ ] All buttons have 44dp min hit targets
- [ ] `Semantics` labels on interactive elements
- [ ] `tooltip` on icon buttons
- [ ] Keyboard navigation via focus order
- [ ] Color contrast: text on frosted panels meets APCA Lc ≥ 60

## Design Tokens Used
- `AfColors.surfaceCanvas` — background
- `AfColors.textOnPrimary` — play button fill
- `AfColors.textPrimary/Secondary/Tertiary` — text hierarchy
- `AfColors.indigo400/600` — accent states
- `AfTypography.titleMedium/titleSmall/bodySmall/caption/mono`
- `AfSpacing.s4` through `AfSpacing.gutterGenerous`
- `AfRadii.borderPill/borderSm/borderLg/borderXl`
- `AfDurations.expressive/quick/standard`
- `AfCurves.easeStandard`
