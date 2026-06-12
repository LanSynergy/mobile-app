import 'dart:ui' as ui;

import 'package:aetherfin/features/now_playing/parametric_band.dart';
import 'package:aetherfin/utils/frequency_response_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FrequencyResponsePainter', () {
    // ── Log frequency mapping ────────────────────────────────────────────────
    group('freqToNormalized', () {
      test('20 Hz maps to 0.0', () {
        expect(
          FrequencyResponsePainter.freqToNormalized(20),
          closeTo(0.0, 1e-10),
        );
      });

      test('20000 Hz maps to 1.0', () {
        expect(
          FrequencyResponsePainter.freqToNormalized(20000),
          closeTo(1.0, 1e-10),
        );
      });

      test('1000 Hz is logarithmic midpoint', () {
        final result = FrequencyResponsePainter.freqToNormalized(1000);
        expect(result, greaterThan(0.3));
        expect(result, lessThan(0.7));
      });
    });

    group('normalizedToFreq', () {
      test('0.0 maps to 20 Hz', () {
        expect(
          FrequencyResponsePainter.normalizedToFreq(0),
          closeTo(20, 1e-10),
        );
      });

      test('1.0 maps to 20000 Hz', () {
        expect(
          FrequencyResponsePainter.normalizedToFreq(1),
          closeTo(20000, 1e-10),
        );
      });
    });

    group('dbToY', () {
      test('0 dB maps to center', () {
        final y = FrequencyResponsePainter.dbToY(0, 200);
        expect(y, 100.0);
      });

      test('+6 dB maps above center', () {
        final y = FrequencyResponsePainter.dbToY(6, 200);
        expect(y, lessThan(100.0));
      });

      test('-6 dB maps below center', () {
        final y = FrequencyResponsePainter.dbToY(-6, 200);
        expect(y, greaterThan(100.0));
      });
    });

    // ── Grid frequency labels ───────────────────────────────────────────────
    group('gridFrequencyLabels', () {
      test('returns standard frequency labels', () {
        const labels = FrequencyResponsePainter.gridFrequencyLabels;
        expect(labels, contains('20'));
        expect(labels, contains('100'));
        expect(labels, contains('1k'));
        expect(labels, contains('10k'));
        expect(labels, contains('20k'));
      });

      test('has correct count', () {
        expect(FrequencyResponsePainter.gridFrequencyLabels.length, 10);
      });
    });

    // ── Grid dB labels ──────────────────────────────────────────────────────
    group('gridDbLabels', () {
      test('returns ±12 dB labels', () {
        const labels = FrequencyResponsePainter.gridDbLabels;
        expect(labels, contains('+12'));
        expect(labels, contains('0'));
        expect(labels, contains('-12'));
      });
    });

    // ── Painting smoke test ─────────────────────────────────────────────────
    group('paint', () {
      test('does not throw with default bands', () {
        final painter = FrequencyResponsePainter(
          bands: ParametricBand.defaultBands(),
          selectedBand: null,
          accentColor: Colors.blue,
        );
        // Painting in a test environment should not throw
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 200));
        expect(recorder.endRecording(), isNotNull);
      });

      test('does not throw with empty bands', () {
        final painter = FrequencyResponsePainter(
          bands: [],
          selectedBand: null,
          accentColor: Colors.blue,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 200));
        expect(recorder.endRecording(), isNotNull);
      });

      test('does not throw with selected band', () {
        final painter = FrequencyResponsePainter(
          bands: ParametricBand.defaultBands(),
          selectedBand: 3,
          accentColor: Colors.blue,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 200));
        expect(recorder.endRecording(), isNotNull);
      });
    });

    // ── shouldRepaint ───────────────────────────────────────────────────────
    group('shouldRepaint', () {
      test('returns true when bands change', () {
        final a = FrequencyResponsePainter(
          bands: ParametricBand.defaultBands(),
          selectedBand: null,
          accentColor: Colors.blue,
        );
        final b = FrequencyResponsePainter(
          bands: [const ParametricBand(frequency: 1000, gain: 6, q: 1.0)],
          selectedBand: null,
          accentColor: Colors.blue,
        );
        expect(a.shouldRepaint(b), isTrue);
      });

      test('returns true when selectedBand changes', () {
        final a = FrequencyResponsePainter(
          bands: ParametricBand.defaultBands(),
          selectedBand: null,
          accentColor: Colors.blue,
        );
        final b = FrequencyResponsePainter(
          bands: ParametricBand.defaultBands(),
          selectedBand: 3,
          accentColor: Colors.blue,
        );
        expect(a.shouldRepaint(b), isTrue);
      });

      test('returns true when accentColor changes', () {
        final a = FrequencyResponsePainter(
          bands: ParametricBand.defaultBands(),
          selectedBand: null,
          accentColor: Colors.blue,
        );
        final b = FrequencyResponsePainter(
          bands: ParametricBand.defaultBands(),
          selectedBand: null,
          accentColor: Colors.red,
        );
        expect(a.shouldRepaint(b), isTrue);
      });

      test('returns false when nothing changes', () {
        final bands = ParametricBand.defaultBands();
        final a = FrequencyResponsePainter(
          bands: bands,
          selectedBand: null,
          accentColor: Colors.blue,
        );
        final b = FrequencyResponsePainter(
          bands: bands,
          selectedBand: null,
          accentColor: Colors.blue,
        );
        expect(a.shouldRepaint(b), isFalse);
      });
    });
  });
}
