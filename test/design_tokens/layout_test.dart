import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Layout tokens — breakpoints', () {
    test('compact breakpoint is 600dp', () {
      expect(AfLayout.compact, 600);
    });

    test('medium breakpoint is 840dp', () {
      expect(AfLayout.medium, 840);
    });

    test('screenSize returns compact for small widths', () {
      expect(AfLayout.screenSize(320), AfScreenSize.compact);
      expect(AfLayout.screenSize(360), AfScreenSize.compact);
      expect(AfLayout.screenSize(599), AfScreenSize.compact);
    });

    test('screenSize returns medium for medium widths', () {
      expect(AfLayout.screenSize(600), AfScreenSize.medium);
      expect(AfLayout.screenSize(700), AfScreenSize.medium);
      expect(AfLayout.screenSize(839), AfScreenSize.medium);
    });

    test('screenSize returns expanded for large widths', () {
      expect(AfLayout.screenSize(840), AfScreenSize.expanded);
      expect(AfLayout.screenSize(1024), AfScreenSize.expanded);
      expect(AfLayout.screenSize(1440), AfScreenSize.expanded);
    });
  });

  group('Layout tokens — content constraints', () {
    test('maxContentWidth is 600dp', () {
      expect(AfLayout.maxContentWidth, 600);
    });

    test('dialogMaxWidth is 560dp', () {
      expect(AfLayout.dialogMaxWidth, 560);
    });
  });

  group('Layout tokens — grid tile extents', () {
    test('albumGridMaxTileExtent is 200dp', () {
      expect(AfLayout.albumGridMaxTileExtent, 200);
    });

    test('artistGridMaxTileExtent is 160dp', () {
      expect(AfLayout.artistGridMaxTileExtent, 160);
    });

    test('genreGridMaxTileExtent is 280dp', () {
      expect(AfLayout.genreGridMaxTileExtent, 280);
    });
  });

  group('Layout tokens — mini player', () {
    test('miniPlayerHeight is 64dp', () {
      expect(AfLayout.miniPlayerHeight, 64);
    });
  });
}
