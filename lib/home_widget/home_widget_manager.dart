import 'package:home_widget/home_widget.dart';

/// Manages the Android home screen "Now Playing" widget.
///
/// Data is saved to SharedPreferences via [home_widget] and read
/// by the native [AetherfinAppWidgetProvider] Kotlin class.
class HomeWidgetManager {
  HomeWidgetManager._();

  static const _name = 'AetherfinAppWidgetProvider';

  /// Save current playback state and update the widget.
  static Future<void> update({
    required String title,
    required String artist,
    required bool playing,
    required bool isFavorite,
    String? artPath,
  }) async {
    await HomeWidget.saveWidgetData<String>('title', title);
    await HomeWidget.saveWidgetData<String>('artist', artist);
    await HomeWidget.saveWidgetData<String>('playing', playing.toString());
    await HomeWidget.saveWidgetData<String>(
      'isFavorite',
      isFavorite.toString(),
    );
    if (artPath != null) {
      await HomeWidget.saveWidgetData<String>('artPath', artPath);
    }
    await HomeWidget.updateWidget(name: _name, androidName: _name);
  }

  /// Clear widget to default "Not Playing" state.
  static Future<void> clear() async {
    await HomeWidget.saveWidgetData<String>('title', 'Not Playing');
    await HomeWidget.saveWidgetData<String>('artist', '');
    await HomeWidget.saveWidgetData<String>('playing', 'false');
    await HomeWidget.saveWidgetData<String>('isFavorite', 'false');
    await HomeWidget.updateWidget(name: _name, androidName: _name);
  }
}
