import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Path helpers for reading project source files.
String _projectRoot() {
  // Tests run from the project root in Flutter.
  return '.';
}

String readSource(String relativePath) {
  return File('${_projectRoot()}/$relativePath').readAsStringSync();
}

List<String> listDir(String relativePath) {
  return Directory(
    '${_projectRoot()}/$relativePath',
  ).listSync().whereType<File>().map((f) => f.path).toList();
}

void main() {
  group('Auth headers', () {
    test('Jellyfin auth omits UserId and Token before login', () {
      // The actual _buildAuthHeader lives in url_builder.dart as a static
      // method. It conditionally adds UserId/Token only when non-null and
      // non-empty — the fields are OMITTED entirely when not authenticated.
      // See CLAUDE.md §5 rule 1.
      final urlBuilder = readSource('lib/core/jellyfin/url_builder.dart');

      // Verify the buildAuthHeader method guards UserId with null+empty check.
      expect(
        urlBuilder.contains('if (userId != null && userId.isNotEmpty)'),
        isTrue,
        reason:
            'buildAuthHeader must omit UserId when null/empty — '
            'do NOT send UserId="" before login',
      );

      // Verify the buildAuthHeader method guards Token with null+empty check.
      expect(
        urlBuilder.contains('if (token != null && token.isNotEmpty)'),
        isTrue,
        reason:
            'buildAuthHeader must omit Token when null/empty — '
            'do NOT send Token="" before login',
      );

      // Note: We do NOT assert absence of `parts.add('UserId="'...` because
      // that concatenation is the correct mechanism — it's wrapped inside
      // the `if (userId != null && userId.isNotEmpty)` guard verified above.
    });

    test('Stream URLs use query parameters, not headers', () {
      // Jellyfin: stream URLs embed api_key as a query param because
      // FFmpeg/libmpv rejects the MediaBrowser Authorization header.
      // See CLAUDE.md §1.3 strict consequence #2.
      final urlBuilder = readSource('lib/core/jellyfin/url_builder.dart');
      expect(
        urlBuilder.contains("'api_key':"),
        isTrue,
        reason:
            'Jellyfin trackStreamUrl must embed api_key as query param '
            'for FFmpeg/libmpv compatibility',
      );
      // Verify it's used as a query parameter (not in header).
      expect(
        urlBuilder.contains('queryParameters:'),
        isTrue,
        reason: 'Jellyfin stream URL must be built with queryParameters map',
      );

      // Subsonic: stream URLs embed auth (u=, t=, s=) as query params.
      // See CLAUDE.md §5.4 Subsonic auth table.
      final subsonic = readSource('lib/core/subsonic/client.dart');
      expect(
        subsonic.contains("'u':"),
        isTrue,
        reason: 'Subsonic stream URL must embed u (username) as query param',
      );
      expect(
        subsonic.contains("'t':"),
        isTrue,
        reason: 'Subsonic stream URL must embed t (token hash) as query param',
      );
      expect(
        subsonic.contains("'s':"),
        isTrue,
        reason: 'Subsonic stream URL must embed s (salt) as query param',
      );

      // Subsonic stream URLs use the stream.view endpoint.
      expect(
        subsonic.contains('stream.view'),
        isTrue,
        reason: 'Subsonic stream URLs must use the stream.view endpoint',
      );
    });

    test('No empty-string UserId or Token in auth headers', () {
      // The entire project must never produce UserId="" or Token="" in
      // Authorization headers. Sending empty-string fields differs from
      // omitting them and breaks some Jellyfin plugins.
      // See CLAUDE.md §5 rule 1.
      //
      // We check line-by-line to skip comment lines (client.dart has
      // a doc comment mentioning `Token=""` as a negative example).
      bool hasNonCommentMatch(String source, String pattern) {
        return source.split('\n').any((line) {
          final trimmed = line.trimLeft();
          // Skip comment-only lines and doc-comment lines.
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
            return false;
          }
          return trimmed.contains(pattern);
        });
      }

      final client = readSource('lib/core/jellyfin/client.dart');
      expect(
        hasNonCommentMatch(client, 'UserId=""'),
        isFalse,
        reason:
            'client.dart must never contain empty-string UserId="" — '
            'omit the field entirely instead',
      );
      expect(
        hasNonCommentMatch(client, 'Token=""'),
        isFalse,
        reason:
            'client.dart must never contain empty-string Token="" — '
            'omit the field entirely instead',
      );

      final urlBuilder = readSource('lib/core/jellyfin/url_builder.dart');
      expect(
        hasNonCommentMatch(urlBuilder, 'UserId=""'),
        isFalse,
        reason: 'url_builder.dart must never produce empty-string UserId=""',
      );
      expect(
        hasNonCommentMatch(urlBuilder, 'Token=""'),
        isFalse,
        reason: 'url_builder.dart must never produce empty-string Token=""',
      );
    });
  });

  group('Queue & player model', () {
    test('Single-track decoder: openAll with single Media only', () {
      // Aetherfin uses a single-track model: mpv loads only the currently
      // active track. openAll must only be called with a single Media.
      // See CLAUDE.md §1.3 strict consequence #3 (single-track model).
      final audioFiles = listDir(
        'lib/core/audio',
      ).where((f) => f.endsWith('.dart')).toList();

      for (final filePath in audioFiles) {
        final content = File(filePath).readAsStringSync();
        final matches = RegExp(r'openAll\(').allMatches(content).toList();

        for (final match in matches) {
          // Find what follows openAll([...]) or openAll(medias where
          // medias is a single-element list.
          final afterOpenAll = content.substring(match.start);

          // Check if the list passed to openAll is a single-element
          // literal ([Media(url)], [Media(...)]) or a variable holding
          // a single-element list.
          final hasSingleMediaLiteral = afterOpenAll.startsWith(
            'openAll([Media(',
          );
          final hasSingleMediaVariable =
              afterOpenAll.startsWith('openAll(medias') &&
              content.contains('medias = <Media>[Media(');

          expect(
            hasSingleMediaLiteral || hasSingleMediaVariable,
            isTrue,
            reason:
                'openAll must only be called with a single Media object '
                '(single-track model). Violation in: $filePath\n'
                'Found: ${afterOpenAll.substring(0, 80)}',
          );
        }
      }
    });

    test('Queue mutations guarded by _queueLock', () {
      // Queue mutations that touch mpv state must be serialized via
      // _queueLock.run() to prevent interleaved async operations.
      // See CLAUDE.md §14.1 entry #44 (AfAsyncLock serialization).
      final content = readSource('lib/core/audio/player_service.dart');

      // Verify _queueLock.run() is used.
      expect(
        content.contains('_queueLock.run('),
        isTrue,
        reason:
            'player_service.dart must use _queueLock.run() to serialize '
            'queue mutations (playQueue, setAfLoopMode, etc.)',
      );

      // Verify _queueLock is declared and exists.
      expect(
        content.contains('final AfAsyncLock _queueLock'),
        isTrue,
        reason: 'player_service.dart must declare _queueLock as AfAsyncLock',
      );

      // Verify playQueue wraps in _queueLock.run().
      final playQueueBody = content
          .split('Future<void> playQueue(')[1]
          .split('Future<void> play')[0];
      expect(
        playQueueBody.contains('_queueLock.run('),
        isTrue,
        reason: 'playQueue must wrap its critical section in _queueLock.run()',
      );

      // Verify setAfLoopMode wraps in _queueLock.run().
      // (setAfShuffleMode is pure Dart on AfQueueManager.mp),
      final loopBody = content
          .split('Future<void> setAfLoopMode(')[1]
          .split('Future<void>')[0];
      expect(
        loopBody.contains('_queueLock.run('),
        isTrue,
        reason:
            'setAfLoopMode must wrap its critical section in _queueLock.run()',
      );

      // Count occurrences — there should be several (playQueue,
      // setAfLoopMode, completed handler branches, EOF fallback).
      final lockCount = RegExp(r'_queueLock\.run\(').allMatches(content).length;
      expect(
        lockCount >= 2,
        isTrue,
        reason:
            'Expected at least 2 _queueLock.run() usages (playQueue, '
            'setAfLoopMode, completed handler). Found: $lockCount',
      );
    });

    test('No native mpv shuffle or gapless API calls', () {
      // Aetherfin manages shuffle (via Fisher-Yates in AfQueueEngine/
      // AfQueueManager) and gapless (via Dart-side StreamPrefetcher)
      // entirely in Dart. mpv's native setShuffle/setGapless must not
      // be called. See CLAUDE.md §2.1 (setShuffle/setGapless notes)
      // and §14.1 entry #24.
      final audioFiles = listDir(
        'lib/core/audio',
      ).where((f) => f.endsWith('.dart')).toList();

      for (final filePath in audioFiles) {
        final content = File(filePath).readAsStringSync();
        final lines = content.split('\n');

        // Check for _player.setShuffle( or player.setShuffle(
        // (calling the mpv Player API directly).
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('_player.setShuffle(') ||
              line.contains('player.setShuffle(')) {
            fail(
              'Found native mpv setShuffle call in $filePath:$i\n'
              'Shuffle must be managed in Dart (AfQueueManager/AfQueueEngine).\n'
              "$line\n"
              'See CLAUDE.md §14.1 entry #24',
            );
          }
          // Check for _player.setGapless( or player.setGapless(
          // The AfPlayerService.setGapless() no-op wrapper is fine,
          // but calling the mpv player directly is not.
          if ((line.contains('_player.setGapless(') ||
                  line.contains('player.setGapless(')) &&
              !line.contains('// No-op') &&
              !line.contains('no-op')) {
            fail(
              'Found native mpv setGapless call in $filePath:$i\n'
              'Gapless is handled by Dart-side StreamPrefetcher.\n'
              "$line\n"
              'See CLAUDE.md §14.1 entry #24',
            );
          }
        }
      }

      // Sanity check: AfPlayerService.setGapless should exist as a no-op.
      final service = readSource('lib/core/audio/player_service.dart');
      expect(
        service.contains('Future<void> setGapless(Gapless mode)'),
        isTrue,
        reason: 'AfPlayerService should define setGapless as a no-op wrapper',
      );
      expect(
        service.contains('// No-op'),
        isTrue,
        reason: 'AfPlayerService.setGapless must be a no-op with a comment',
      );

      // The Dart-side AfQueueManager and AfQueueEngine should own shuffle.
      final queueManager = readSource('lib/core/audio/queue_manager.dart');
      expect(
        queueManager.contains('void setShuffle(bool enabled)'),
        isTrue,
        reason: 'AfQueueManager should own shuffle state',
      );
      final queueEngine = readSource('lib/core/audio/queue_engine.dart');
      expect(
        queueEngine.contains('void setShuffle(bool enabled)'),
        isTrue,
        reason: 'AfQueueEngine should own shuffle state',
      );
    });
  });

  group('UI conventions', () {
    test('Context menus use dialogs, not bottom sheets', () {
      // Context menus (track long-press, album 3-dot) must use dialogs
      // (showBlurDialog from af_dialog.dart), not showModalBottomSheet.
      // See CLAUDE.md §15 entry #52.
      // Context menu files.
      final trackContext = readSource('lib/widgets/track_context_menu.dart');
      expect(
        trackContext.contains('showBlurDialog'),
        isTrue,
        reason:
            'track_context_menu.dart must use showBlurDialog (from af_dialog.dart)',
      );
      expect(
        trackContext.contains('showModalBottomSheet'),
        isFalse,
        reason:
            'track_context_menu.dart must not use showModalBottomSheet — '
            'context menus should use dialogs',
      );
      expect(
        trackContext.contains("import 'af_dialog.dart'"),
        isTrue,
        reason:
            'track_context_menu.dart must import af_dialog.dart '
            'for showBlurDialog',
      );

      // Album more sheet should use dialog (despite "sheet" in name).
      final albumMore = readSource('lib/widgets/album_more_sheet.dart');
      expect(
        albumMore.contains('showBlurDialog'),
        isTrue,
        reason:
            'album_more_sheet.dart must use showBlurDialog (from af_dialog.dart)',
      );
      expect(
        albumMore.contains('showModalBottomSheet'),
        isFalse,
        reason:
            'album_more_sheet.dart must not use showModalBottomSheet — '
            'album menus should use dialogs',
      );
      expect(
        albumMore.contains("import 'af_dialog.dart'"),
        isTrue,
        reason:
            'album_more_sheet.dart must import af_dialog.dart '
            'for showBlurDialog',
      );

      // Verify af_dialog.dart exists and exports showBlurDialog.
      final afDialog = readSource('lib/widgets/af_dialog.dart');
      expect(
        afDialog.contains('Future<T?> showBlurDialog<T>'),
        isTrue,
        reason: 'af_dialog.dart must define showBlurDialog function',
      );
      // showBlurDialog uses showDialog (not showModalBottomSheet).
      expect(
        afDialog.contains('showDialog<'),
        isTrue,
        reason: 'showBlurDialog must use showDialog, not showModalBottomSheet',
      );
      expect(
        afDialog.contains('showModalBottomSheet'),
        isFalse,
        reason: 'af_dialog.dart must not contain showModalBottomSheet',
      );
    });
  });
}
