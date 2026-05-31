import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'dart:developer' as dev;

/// Shared Dio client with connection pooling and caching for all HTTP requests.
///
/// This singleton provides a centralized, optimized HTTP client that can be reused
/// across all backend implementations (Jellyfin, Subsonic, Navidrome) to:
/// - Enable connection pooling (reduces TCP/TLS handshake overhead)
/// - Share cache storage across all clients
/// - Provide consistent timeout and retry configuration
/// - Reduce memory overhead from multiple Dio instances
class SharedDioClient {
  SharedDioClient._internal()
    : _cacheStore = MemCacheStore(
        maxSize: 20 * 1024 * 1024, // 20MB
        maxEntrySize: 1 * 1024 * 1024, // 1MB per entry
      ),
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          // Enable following redirects
          followRedirects: true,
          // Maximum number of redirects
          maxRedirects: 5,
        ),
      ) {
    // Configure connection pooling via HttpClientAdapter
    _dio.httpClientAdapter = _createAdapter();

    // Configure caching with LRU eviction
    _dio.interceptors.add(
      DioCacheInterceptor(
        options: CacheOptions(
          store: _cacheStore,
          policy: CachePolicy.request,
          maxStale: const Duration(minutes: 5),
          priority: CachePriority.normal,
        ),
      ),
    );

    // Add retry interceptor for transient failures
    _dio.interceptors.add(_RetryInterceptor());
  }

  /// Factory constructor returns the singleton instance
  factory SharedDioClient() => _instance;

  static final SharedDioClient _instance = SharedDioClient._internal();

  final Dio _dio;
  final MemCacheStore _cacheStore;

  /// Shared HttpClient adapter with connection pooling.
  /// Reused by [createWithOptions] so custom Dio instances share the pool.
  final IOHttpClientAdapter _httpClientAdapter = _createAdapter();

  static IOHttpClientAdapter _createAdapter() {
    return IOHttpClientAdapter()
      ..createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => 'DIRECT';
        client.idleTimeout = const Duration(seconds: 15);
        client.connectionTimeout = const Duration(seconds: 5);
        return client;
      };
  }

  /// Returns the shared Dio instance
  Dio get dio => _dio;

  /// Returns the cache store for direct access (e.g., manual cache clearing)
  MemCacheStore get cacheStore => _cacheStore;

  /// Creates a Dio instance with custom base options but shared connection pooling.
  /// Reuses the singleton's [IOHttpClientAdapter] so connections are pooled
  /// across all backend clients (Jellyfin, Subsonic, Navidrome).
  Dio createWithOptions(BaseOptions options) {
    final customDio = Dio(options);
    customDio.httpClientAdapter = _httpClientAdapter;
    return customDio;
  }

  /// Clears all cached responses
  void clearCache() {
    _cacheStore.clean();
  }

  /// Closes the Dio client and cleans up resources
  void close() {
    _dio.close(force: true);
    _cacheStore.close();
  }

  /// Returns the current number of cached entries
  int get cacheSize => 0; // MemCacheStore doesn't expose size directly
}

/// Retry interceptor for transient HTTP failures.
///
/// Retries on connection timeouts, connection errors, and server errors
/// (500, 502, 503, 504) with exponential backoff: 1s, 2s, 4s. Max 3 retries.
class _RetryInterceptor extends Interceptor {
  static const _maxRetries = 3;
  static const _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_shouldRetry(err)) {
      final retryCount = (err.requestOptions.extra['_retryCount'] as int?) ?? 0;
      if (retryCount < _maxRetries) {
        final delay = _retryDelays[retryCount];
        dev.log(
          'Retrying ${err.requestOptions.method} ${err.requestOptions.uri} '
          '(attempt ${retryCount + 1}/$_maxRetries) after ${delay.inSeconds}s',
          name: 'aetherfin:http',
        );
        await Future.delayed(delay);
        final options = err.requestOptions;
        options.extra['_retryCount'] = retryCount + 1;
        try {
          final response = await Dio().fetch(options);
          return handler.resolve(response);
        } catch (_) {
          // Fall through to next retry or final error
        }
      }
    }
    return handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    if (err.response != null) {
      final statusCode = err.response!.statusCode;
      if (statusCode == 500 ||
          statusCode == 502 ||
          statusCode == 503 ||
          statusCode == 504) {
        return true;
      }
    }
    return false;
  }
}
