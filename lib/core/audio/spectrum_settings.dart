import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Default spectrum analyser configuration shared across initialisation and
/// on-track-change re-configuration.
const defaultSpectrumSettings = SpectrumSettings(
  fftSize: 2048,
  bandCount: 64,
  bandLowHz: 20.0,
  bandHighHz: 20000.0,
  attackSmoothing: 0.8,
  releaseSmoothing: 0.1,
  minDb: -105.0,
  maxDb: 35.0,
  emitInterval: Duration(milliseconds: 8),
);
