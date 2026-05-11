package dev.aetherfin.aetherfin

import com.ryanheise.audioservice.AudioServiceActivity

/// Extends [AudioServiceActivity] (from the `audio_service` plugin) instead
/// of FlutterActivity so audio_service's foreground service can attach to
/// the running Flutter engine. Without this, AudioService.init throws:
///   "The Activity class declared in your AndroidManifest.xml is wrong or
///    has not provided the correct FlutterEngine."
class MainActivity : AudioServiceActivity()
