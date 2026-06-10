import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Opacity tokens', () {
    test('all values are between 0.0 and 1.0', () {
      expect(AfOpacity.disabled, inInclusiveRange(0.0, 1.0));
      expect(AfOpacity.hover, inInclusiveRange(0.0, 1.0));
      expect(AfOpacity.focus, inInclusiveRange(0.0, 1.0));
      expect(AfOpacity.pressed, inInclusiveRange(0.0, 1.0));
      expect(AfOpacity.dragged, inInclusiveRange(0.0, 1.0));
      expect(AfOpacity.subtle, inInclusiveRange(0.0, 1.0));
      expect(AfOpacity.light, inInclusiveRange(0.0, 1.0));
      expect(AfOpacity.medium, inInclusiveRange(0.0, 1.0));
      expect(AfOpacity.heavy, inInclusiveRange(0.0, 1.0));
    });

    test('semantic ordering: subtle < light < medium < heavy', () {
      expect(AfOpacity.subtle, lessThan(AfOpacity.light));
      expect(AfOpacity.light, lessThan(AfOpacity.medium));
      expect(AfOpacity.medium, lessThan(AfOpacity.heavy));
    });

    test('state overlays: hover < focus < pressed < dragged', () {
      expect(AfOpacity.hover, lessThan(AfOpacity.focus));
      expect(AfOpacity.focus, lessThan(AfOpacity.pressed));
      expect(AfOpacity.pressed, lessThan(AfOpacity.dragged));
    });

    test('disabled is 0.38 (Material Design standard)', () {
      expect(AfOpacity.disabled, 0.38);
    });
  });
}
