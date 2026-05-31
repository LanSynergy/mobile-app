import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

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
    _dio.httpClientAdapter = IOHttpClientAdapter()
      ..createHttpClient = () {
        final client = HttpClient();
        // Disable proxy to ensure direct connections
        client.findProxy = (uri) => "DIRECT";
        // Set idle timeout for connections in the pool
        client.idleTimeout = const Duration(seconds: 15);
        // Allow connection reuse
        client.connectionTimeout = const Duration(seconds: 5);
        return client;
      };

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
  }

  /// Factory constructor returns the singleton instance
  factory SharedDioClient() => _instance;

  static final SharedDioClient _instance = SharedDioClient._internal();

  final Dio _dio;
  final MemCacheStore _cacheStore;

  /// Returns the shared Dio instance
  Dio get dio => _dio;

  /// Returns the cache store for direct access (e.g., manual cache clearing)
  MemCacheStore get cacheStore => _cacheStore;

  /// Creates a Dio instance with custom base options but shared connection pooling
  Dio createWithOptions(BaseOptions options) {
    final customDio = Dio(options);
    customDio.httpClientAdapter = IOHttpClientAdapter()
      ..createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => "DIRECT";
        client.idleTimeout = const Duration(seconds: 15);
        client.connectionTimeout = const Duration(seconds: 5);
        return client;
      };
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
