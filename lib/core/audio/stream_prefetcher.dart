import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../../utils/log.dart';

/// Prefetches audio stream bytes for upcoming tracks into local temporary files
/// to facilitate smooth, gapless-like transition on completion.
class StreamPrefetcher {
  StreamPrefetcher({Dio? dio}) : _dio = dio ?? Dio() {
    _init();
  }

  final Dio _dio;
  String? _cacheDir;
  CancelToken? _cancelToken;
  File? _currentTempFile;
  String? _currentPrefetchingTrackId;
  final Map<String, File> _cachedFiles = {};

  Future<void> _init() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = tempDir.path;
      clearStaleTempFiles();
    } catch (e, stack) {
      afLog(
        'audio',
        'StreamPrefetcher init failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Returns the cached prefetch file for [trackId], if it exists and is valid.
  File? getCachedFile(String trackId) {
    final file = _cachedFiles[trackId];
    if (file != null && file.existsSync()) {
      return file;
    }
    return null;
  }

  /// Starts prefetching the track stream at [url] to a temp file.
  Future<File?> prefetch(
    String url,
    Map<String, String> headers, {
    required String trackId,
  }) async {
    if (_currentPrefetchingTrackId == trackId) {
      final cached = getCachedFile(trackId);
      if (cached != null) return cached;
      return null;
    }

    cancelCurrentPrefetch();

    if (_cacheDir == null) {
      try {
        final tempDir = await getTemporaryDirectory();
        _cacheDir = tempDir.path;
      } catch (e) {
        afLog('audio', 'Failed to retrieve temp dir in prefetch', error: e);
        return null;
      }
    }

    _currentPrefetchingTrackId = trackId;
    _cancelToken = CancelToken();

    final tempFile = File(
      p.join(
        _cacheDir!,
        'prefetch_${trackId}_${DateTime.now().millisecondsSinceEpoch}.tmp',
      ),
    );
    _currentTempFile = tempFile;

    afLog('audio', 'Starting prefetch for trackId=$trackId, url=$url');

    try {
      Response<ResponseBody> response;
      int retries = 0;
      while (true) {
        try {
          response = await _dio.get<ResponseBody>(
            url,
            options: Options(
              headers: headers,
              responseType: ResponseType.stream,
            ),
            cancelToken: _cancelToken,
          );
          break;
        } catch (e) {
          if (_cancelToken?.isCancelled ?? false) {
            rethrow;
          }
          if (retries >= 1) {
            rethrow;
          }
          retries++;
          afLog(
            'audio',
            'Prefetch download failed, retrying (retry=$retries)',
            error: e,
          );
        }
      }

      final sink = tempFile.openWrite();
      await response.data!.stream.forEach(sink.add);
      await sink.close();

      _cachedFiles[trackId] = tempFile;
      _currentPrefetchingTrackId = null;
      _currentTempFile = null;
      _cancelToken = null;

      afLog('audio', 'Prefetch completed successfully for trackId=$trackId');
      return tempFile;
    } catch (e, stack) {
      _currentPrefetchingTrackId = null;
      _currentTempFile = null;
      _cancelToken = null;

      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }

      if (e is DioException && DioExceptionType.cancel == e.type) {
        afLog('audio', 'Prefetch cancelled for trackId=$trackId');
      } else {
        afLog(
          'audio',
          'Prefetch failed for trackId=$trackId',
          error: e,
          stackTrace: stack,
        );
      }
      return null;
    }
  }

  /// Cancels the current prefetch download and deletes the partial temp file.
  void cancelCurrentPrefetch() {
    if (_cancelToken != null) {
      _cancelToken!.cancel();
      _cancelToken = null;
    }
    if (_currentTempFile != null) {
      final file = _currentTempFile!;
      _currentTempFile = null;
      Future.microtask(() {
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
      });
    }
    _currentPrefetchingTrackId = null;
  }

  /// Deletes all prefetch_*.tmp files in the temp directory that are older than 5 minutes.
  void clearStaleTempFiles() {
    if (_cacheDir == null) return;
    try {
      final dir = Directory(_cacheDir!);
      if (!dir.existsSync()) return;

      final now = DateTime.now();
      final threshold = now.subtract(const Duration(minutes: 5));

      final files = dir.listSync();
      for (final f in files) {
        if (f is File &&
            p.basename(f.path).startsWith('prefetch_') &&
            f.path.endsWith('.tmp')) {
          try {
            final stat = f.statSync();
            if (stat.modified.isBefore(threshold)) {
              f.deleteSync();
              afLog('audio', 'Deleted stale prefetch file: ${f.path}');
            }
          } catch (e) {
            afLog('audio', 'Failed to delete stale file: ${f.path}', error: e);
          }
        }
      }
    } catch (e) {
      afLog('audio', 'Error clearing stale temp files', error: e);
    }
  }
}
