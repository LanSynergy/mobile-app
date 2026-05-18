/// Strip the trailing slash from [url] if present.
///
/// Used by both [JellyfinClient] and [SubsonicClient] when building
/// stream / image URLs via `Uri.replace` — a trailing slash would
/// produce a double-slash in the path segment.
String stripTrailingSlash(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;

/// Query parameters that carry auth material or other sensitive state and
/// must never appear in logs / error toasts / bug reports. The set is
/// intentionally broad to cover both Jellyfin (`api_key`) and the
/// Subsonic auth scheme (`t`, `s`, `u`, `p`).
const Set<String> _sensitiveQueryKeys = <String>{
  'api_key',
  'apikey',
  'access_token',
  't',
  's',
  'u',
  'p',
  'password',
  'token',
};

/// Return a copy of [uri] (or its parsed form, if a [String]) with the
/// values of any [_sensitiveQueryKeys] replaced by `[REDACTED]`. Used
/// when an error or status line needs to be surfaced to the user or
/// included in a log entry — the path, host, and other params stay
/// visible so the message is still useful for debugging.
String redactSensitiveQueryParams(Object uri) {
  // Preserve the caller's exact rendering whenever we don't actually
  // need to mutate anything — `Uri.toString()` after a round-trip can
  // re-encode spaces, swap implicit ports, etc., which is noise in
  // error messages.
  final original = uri.toString();
  Uri parsed;
  if (uri is Uri) {
    parsed = uri;
  } else if (uri is String) {
    final maybe = Uri.tryParse(uri);
    if (maybe == null) return original;
    parsed = maybe;
  } else {
    return original;
  }
  if (parsed.queryParameters.isEmpty) return original;
  final hasSensitive =
      parsed.queryParameters.keys.any(_sensitiveQueryKeys.contains);
  if (!hasSensitive) return original;
  final scrubbed = <String, String>{
    for (final entry in parsed.queryParameters.entries)
      entry.key:
          _sensitiveQueryKeys.contains(entry.key) ? '[REDACTED]' : entry.value,
  };
  return parsed.replace(queryParameters: scrubbed).toString();
}
