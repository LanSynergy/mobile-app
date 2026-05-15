/// Strip the trailing slash from [url] if present.
///
/// Used by both [JellyfinClient] and [SubsonicClient] when building
/// stream / image URLs via `Uri.replace` — a trailing slash would
/// produce a double-slash in the path segment.
String stripTrailingSlash(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;
