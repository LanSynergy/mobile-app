import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'models/server.dart';

/// Scans the local network for Jellyfin servers via mDNS.
///
/// Jellyfin advertises itself on `_jellyfin._tcp.local` (HTTP) and
/// `_jellyfin-server._tcp.local` (server-API). We listen on both.
class JellyfinDiscovery {
  static const _httpService = '_jellyfin._tcp.local';
  static const _serverService = '_jellyfin-server._tcp.local';

  /// Yields servers as they are resolved. The stream completes after
  /// [timeout] elapses; cancel the subscription early to stop scanning.
  Stream<JellyfinServer> scan({
    Duration timeout = const Duration(seconds: 6),
  }) async* {
    final client = MDnsClient(rawDatagramSocketFactory:
        (dynamic host, int port,
                {bool reuseAddress = true,
                bool reusePort = false,
                int ttl = 1}) {
      return RawDatagramSocket.bind(
        host,
        port,
        reuseAddress: reuseAddress,
        reusePort: false, // Android disallows reusePort
        ttl: ttl,
      );
    });
    try {
      await client.start();
      final seen = <String>{};
      final completer = Completer<void>();
      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      Stream<JellyfinServer> resolveOne(String service) async* {
        final ptrStream = client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(service),
          timeout: timeout,
        );
        await for (final ptr in ptrStream) {
          if (completer.isCompleted) break;
          final srvStream = client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: timeout,
          );
          await for (final srv in srvStream) {
            if (completer.isCompleted) break;
            final ipStream = client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
              timeout: timeout,
            );
            await for (final ip in ipStream) {
              if (completer.isCompleted) break;
              final url = 'http://${ip.address.address}:${srv.port}';
              if (seen.add(url)) {
                yield JellyfinServer(
                  baseUrl: url,
                  name: ptr.domainName.split('.').first,
                  isLocal: true,
                );
              }
            }
          }
        }
      }

      yield* StreamGroup.merge([
        resolveOne(_httpService),
        resolveOne(_serverService),
      ]);
    } finally {
      client.stop();
    }
  }
}

/// Minimal stream-group merge (we don't pull in `async/StreamGroup` to avoid
/// a heavy dep — we only ever merge two streams).
class StreamGroup {
  static Stream<T> merge<T>(Iterable<Stream<T>> streams) async* {
    final controller = StreamController<T>();
    final subs = <StreamSubscription<T>>[];
    var open = streams.length;

    for (final s in streams) {
      subs.add(s.listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          open--;
          if (open == 0) controller.close();
        },
      ));
    }

    try {
      yield* controller.stream;
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      await controller.close();
    }
  }
}
