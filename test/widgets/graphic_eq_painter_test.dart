import 'dart:ui' as ui;

import 'package:aetherfin/utils/graphic_eq_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GraphicEqPainter', () {
    const testBands = [
      '65',
      '92',
      '131',
      '185',
      '262',
      '370',
      '523',
      '740',
      '1k',
      '2k',
      '5k',
      '10k',
      '20k',
    ];

    // ── Constructor ─────────────────────────────────────────────────────────
    group('constructor', () {
      test('creates with valid parameters', () {
        final painter = GraphicEqPainter(
          bands: testBands,
          gains: List.filled(testBands.length, 1.0),
          accentColor: Colors.blue,
        );
        expect(painter.bands, testBands);
        expect(painter.gains, List.filled(testBands.length, 1.0));
        expect(painter.enabled, isTrue);
        expect(painter.selectedBand, isNull);
      });
    });

    // ── dB to bar height ────────────────────────────────────────────────────
    group('dbToBarHeight', () {
      test('0 dB returns 0 height', () {
        expect(GraphicEqPainter.dbToBarHeight(0, 100), 0.0);
      });

      test('+6 dB returns positive height', () {
        expect(GraphicEqPainter.dbToBarHeight(6, 100), greaterThan(0));
      });

      test('-6 dB returns positive height (below center)', () {
        expect(GraphicEqPainter.dbToBarHeight(-6, 100), greaterThan(0));
      });

      test('symmetric for ±dB', () {
        final up = GraphicEqPainter.dbToBarHeight(6, 100);
        final down = GraphicEqPainter.dbToBarHeight(-6, 100);
        expect(up, closeTo(down, 0.01));
      });
    });

    // ── Gain to dB ──────────────────────────────────────────────────────────
    group('gainToDb', () {
      test('1.0 multiplier = 0 dB', () {
        expect(GraphicEqPainter.gainToDb(1.0), closeTo(0.0, 0.01));
      });

      test('0.5 multiplier = -6 dB', () {
        expect(GraphicEqPainter.gainToDb(0.5), closeTo(-6.0, 0.1));
      });

      test('2.0 multiplier = +6 dB', () {
        expect(GraphicEqPainter.gainToDb(2.0), closeTo(6.0, 0.1));
      });
    });

    // ── Frequency coded color ───────────────────────────────────────────────
    group('bandColor', () {
      test('returns different colors for different bands', () {
        final colors = <Color>[];
        for (var i = 0; i < testBands.length; i++) {
          colors.add(GraphicEqPainter.bandColor(i, testBands.length));
        }
        // All colors should be distinct
        final uniqueColors = colors.toSet();
        expect(uniqueColors.length, testBands.length);
      });

      test('first band is reddish (bass)', () {
        final color = GraphicEqPainter.bandColor(0, testBands.length);
        // Hue should be near 0 (red)
        final hsv = HSVColor.fromColor(color);
        expect(hsv.hue, lessThan(30));
      });

      test('last band is bluish (treble)', () {
        final color = GraphicEqPainter.bandColor(
          testBands.length - 1,
          testBands.length,
        );
        final hsv = HSVColor.fromColor(color);
        expect(hsv.hue, greaterThan(210));
      });
    });

    // ── Painting smoke test ─────────────────────────────────────────────────
    group('paint', () {
      test('does not throw with default gains', () {
        final painter = GraphicEqPainter(
          bands: testBands,
          gains: List.filled(testBands.length, 1.0),
          accentColor: Colors.blue,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 120));
        expect(recorder.endRecording(), isNotNull);
      });

      test('does not throw when disabled', () {
        final painter = GraphicEqPainter(
          bands: testBands,
          gains: List.filled(testBands.length, 1.0),
          accentColor: Colors.blue,
          enabled: false,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 120));
        expect(recorder.endRecording(), isNotNull);
      });

      test('does not throw with selected band', () {
        final painter = GraphicEqPainter(
          bands: testBands,
          gains: List.filled(testBands.length, 1.0),
          accentColor: Colors.blue,
          selectedBand: 5,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 120));
        expect(recorder.endRecording(), isNotNull);
      });

      test('does not throw with mixed gains (boosts and cuts)', () {
        final gains = List<double>.generate(
          testBands.length,
          (i) => i.isEven ? 1.5 : 0.7,
        );
        final painter = GraphicEqPainter(
          bands: testBands,
          gains: gains,
          accentColor: Colors.blue,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 120));
        expect(recorder.endRecording(), isNotNull);
      });

      test('does not throw with max boost', () {
        final painter = GraphicEqPainter(
          bands: testBands,
          gains: List.filled(testBands.length, 4.0),
          accentColor: Colors.blue,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 120));
        expect(recorder.endRecording(), isNotNull);
      });
    });

    // ── shouldRepaint ───────────────────────────────────────────────────────
    group('shouldRepaint', () {
      test('returns true when gains change', () {
        final a = GraphicEqPainter(
          bands: testBands,
          gains: List.filled(testBands.length, 1.0),
          accentColor: Colors.blue,
        );
        final b = GraphicEqPainter(
          bands: testBands,
          gains: List.filled(testBands.length, 2.0),
          accentColor: Colors.blue,
        );
        expect(a.shouldRepaint(b), isTrue);
      });

      test('returns true when enabled changes', () {
        final a = GraphicEqPainter(
          bands: testBands,
          gains: List.filled(testBands.length, 1.0),
          accentColor: Colors.blue,
          enabled: true,
        );
        final b = GraphicEqPainter(
          bands: testBands,
          gains: List.filled(testBands.length, 1.0),
          accentColor: Colors.blue,
          enabled: false,
        );
        expect(a.shouldRepaint(b), isTrue);
      });

      test('returns false when identical', () {
        final gains = List.filled(testBands.length, 1.0);
        final a = GraphicEqPainter(
          bands: testBands,
          gains: gains,
          accentColor: Colors.blue,
        );
        final b = GraphicEqPainter(
          bands: testBands,
          gains: gains,
          accentColor: Colors.blue,
        );
        expect(a.shouldRepaint(b), isFalse);
      });
    });
  });
}
