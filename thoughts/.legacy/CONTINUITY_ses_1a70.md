---
session: ses_1a70
updated: 2026-05-24T08:44:47.191Z
---

# Session Summary

## Goal
Eliminate the theme-level floating drag handle and convert context menus from bottom sheets to popup dialogs for a cleaner, tighter UI.

## Constraints & Preferences
- Prefer `showBlurDialog` over `showBlurBottomSheet` for context menus
- Match `BlurBottomSheet` spacing standard: 12px gap on each side of the drag handle
- Follow `type(scope): description` commit message format
- Keep frosted‑glass (`BackdropFilter`) and transparent background (`Colors.transparent`) on all sheets/dialogs
- `AfColors.surfaceRaised.withValues(alpha: 0.85)` for dialog background
- `EdgeInsets.all(16)` for dialog content padding (reduced from 24)
- Always run `flutter analyze --no-fatal-infos` and `flutter test` before commit

## Progress
### Done
- [x] Removed `showDragHandle: true`, `dragHandleColor`, `dragHandleSize` from `BottomSheetThemeData` in `theme.dart`
- [x] Set `bottomSheetTheme.backgroundColor` and `modalBackgroundColor` to `Colors.transparent`
- [x] Stripped `DraggableScrollableSheet` + `scrollController` from `track_details_sheet.dart`
- [x] Added manual drag handle (40×4 rounded container, `AfColors.textTertiary` at 0.4 alpha) inside `album_more_sheet.dart`
- [x] Added same manual drag handle inside `track_details_sheet.dart`
- [x] Unified sheet container background to `Color(0xB30B0B14)` across all sheets
- [x] Tightened album_more_sheet gap from handle to content: `AfSpacing.s16` → `AfSpacing.s12`
- [x] Fixed track_details_sheet double‑gap (12px SizedBox + 12px ListView top padding) by removing ListView's top padding
- [x] Reduced `_BlurDialog` padding from `EdgeInsets.all(24)` → `EdgeInsets.all(16)` in `af_dialog.dart`
- [x] Converted `showTrackContextMenu` in `track_context_menu.dart` from `showBlurBottomSheet` → `showBlurDialog`
- [x] Converted `showAlbumContextMenu` in `track_context_menu.dart` from `showBlurBottomSheet` → `showBlurDialog`
- [x] Updated import in `track_context_menu.dart` from `bottom_sheet.dart` → `af_dialog.dart`
- [x] Used `Navigator.of(ctx).pop()` (Consumer context) and `Navigator.of(dialogCtx).pop()` (Builder context) for dialog dismissal

### In Progress
- [ ] (none — all changes committed)

### Blocked
- (none)

## Key Decisions
- **Remove theme‑level drag handle**: Floating on transparent bg looked wrong; moving per‑sheet gives pixel control inside the visual content.
- **Manual drag handle inside Column**: Replaced theme handle with a simple `Container(40×4, rounded, textTertiary@40%)` inside each sheet's content Column.
- **`showBlurDialog` for context menus**: Context menus are action lists, not scrollable sheets — a centered dialog is the correct UX pattern.
- **`EdgeInsets.all(16)` for dialog padding**: Tighter than 24px to reduce wasted space between canvas edge and content; matches `AfSpacing.s16`.

## Next Steps
1. Verify the new dialog‑style context menus render correctly on device (manual QA)
2. If needed, convert `album_more_sheet.dart` (`showAlbumMoreSheet`) and `track_details_sheet.dart` (`showTrackDetailsSheet`) from bottom sheets to dialogs as well
3. Optionally convert `save_to_playlist_sheet.dart` to dialog

## Critical Context
- `showBlurDialog` is defined in `lib/widgets/af_dialog.dart`
- `AfColors.surfaceRaised.withValues(alpha: 0.85)` + `BackdropFilter(blur 15)` gives the frosted‑glass look
- Context menus (`track_context_menu.dart`) now use `Builder` wrapper for album menu (no Consumer) and `Consumer` wrapper for track menu (needs Riverpod)
- All `Navigator.pop()` calls inside dialogs use a context captured from inside the dialog's widget tree
- Commit headers: `a565eda` (dialog padding), `41a5588` (bottom sheet drag handles) — the latest commit `0404d34` (message fix) should be squashed

## File Operations
### Read
- `D:\project\mobile-app\lib\widgets\af_dialog.dart`
- `D:\project\mobile-app\lib\widgets\album_more_sheet.dart`
- `D:\project\mobile-app\lib\widgets\bottom_sheet.dart`
- `D:\project\mobile-app\lib\widgets\track_context_menu.dart`
- `D:\project\mobile-app\lib\widgets\track_details_sheet.dart`
- `D:\project\mobile-app\lib\widgets\save_to_playlist_sheet.dart`

### Modified
- `D:\project\mobile-app\lib\app\theme.dart`
- `D:\project\mobile-app\lib\widgets\af_dialog.dart`
- `D:\project\mobile-app\lib\widgets\album_more_sheet.dart`
- `D:\project\mobile-app\lib\widgets\track_context_menu.dart`
- `D:\project\mobile-app\lib\widgets\track_details_sheet.dart`
