# lucide_icons_flutter_patched

A **size-optimized** local patch of [lucide_icons_flutter](https://pub.dev/packages/lucide_icons_flutter).

## Purpose

The official `lucide_icons_flutter` package (v3.1.14+) includes **6 variable font families** (Lucide100-600) for stroke weight variants, totaling ~2.6MB per ABI. Aetherfin does not use stroke weight variants (all icons use the default weight), so these additional font files are unnecessary bloat.

This patch:
- Consolidates all icons into a **single TTF font file** (`assets/lucide.ttf`)
- Removes unused Lucide100-600 font families
- **Saves ~5.2MB** total (2.6MB × 2 ABIs: arm64-v8a + x86_64)
- Preserves all icon glyphs and RTL support

## Generation

The patch is generated from the upstream Lucide source using the scripts in `tool/`.

Key tool:
- `tool/add_directional_icon_variants.dart` — adds `*Dir` variants for RTL support

## Upstream

- **Package:** https://pub.dev/packages/lucide_icons_flutter
- **Repository:** https://github.com/vqh2602/lucide-flutter-main
- **Upstream version:** 3.1.14+1 (patched from source)

## Do Not Use Directly

This is an **internal dependency** of Aetherfin. Do not publish or use separately.
To update: re-run the generation scripts from upstream source, then update the version in `pubspec.yaml`.
