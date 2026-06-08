/// Stores and distributes auth headers for stream requests.
///
/// Provides a single source of truth for the current auth header map
/// so that playback, artwork, and prefetch all share the same credentials.
class AuthHeadersManager {
  Map<String, String> _headers = const <String, String>{};

  /// The current auth headers.
  Map<String, String> get headers => _headers;

  /// Whether no auth headers are set.
  bool get isEmpty => _headers.isEmpty;

  /// Replace the stored auth headers.
  void setHeaders(Map<String, String> headers) {
    _headers = headers;
  }
}
