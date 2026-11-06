import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:multicast_dns/multicast_dns.dart';

import '../generated/streamchat.pbgrpc.dart' as pb;

/// Dirección de un servicio ChatHub.
class Endpoint {
  const Endpoint(this.host, this.port);

  final String host;
  final int port;

  /// Acepta "host:puerto", "host" (usa el puerto por defecto) o
  /// "grpc://host:puerto".
  static Endpoint? parse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final s = value.trim().replaceFirst(RegExp(r'^[a-z]+://'), '');
    final i = s.lastIndexOf(':');
    if (i <= 0) return Endpoint(s, ServiceDiscovery.defaultPort);
    final port = int.tryParse(s.substring(i + 1));
    if (port == null || port <= 0 || port > 65535) return null;
    return Endpoint(s.substring(0, i), port);
  }

  @override
  String toString() => '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is Endpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

class DiscoveryResult {
  const DiscoveryResult(this.endpoint, this.source, this.channels);

  final Endpoint endpoint;

  /// Cómo se encontró, para mostrarlo en la interfaz.
  final String source;
  final List<pb.Channel> channels;
}

/// Busca el servicio ChatHub sin configuración.
///
/// Orden de búsqueda:
///   1. Variable de entorno STREAMCHAT_ADDRESS (host:puerto).
///   2. La última dirección que funcionó (guardada por la app).
///   3. Este equipo: 127.0.0.1 en el puerto por defecto y vecinos.
///   4. La red local por mDNS, si el servicio se anuncia como _streamchat._tcp.
///
/// Cada candidato se valida llamando a ListChannels: un puerto abierto no
/// basta, tiene que responder el servicio ChatHub. Así se descarta, por
/// ejemplo, el módulo OAuth en :50052.
class ServiceDiscovery {
  static const defaultPort = 50051;
  static const mdnsServiceType = '_streamchat._tcp.local';

  /// 50052 se omite a propósito: es el módulo OAuth.
  static const localPorts = [50051, 50050, 50053, 50054, 50055, 50056, 50057, 50058, 50059, 50060];

  static const probeTimeout = Duration(milliseconds: 800);

  Future<DiscoveryResult?> discover({Endpoint? lastKnown}) async {
    final fromEnv = Endpoint.parse(Platform.environment['STREAMCHAT_ADDRESS']);
    if (fromEnv != null) {
      final ch = await probe(fromEnv, timeout: const Duration(seconds: 2));
      if (ch != null) return DiscoveryResult(fromEnv, 'variable STREAMCHAT_ADDRESS', ch);
    }

    if (lastKnown != null && lastKnown != fromEnv) {
      final ch = await probe(lastKnown);
      if (ch != null) return DiscoveryResult(lastKnown, 'última conexión', ch);
    }

    final local = await _probeLocal();
    if (local != null) return local;

    return _probeMdns();
  }

  Future<DiscoveryResult?> _probeLocal() async {
    final candidates = [for (final p in localPorts) Endpoint('127.0.0.1', p)];
    // En paralelo: el tiempo total es el de un solo intento.
    final results = await Future.wait(candidates.map((e) => probe(e)));
    for (var i = 0; i < candidates.length; i++) {
      final ch = results[i];
      if (ch != null) return DiscoveryResult(candidates[i], 'este equipo', ch);
    }
    return null;
  }

  Future<DiscoveryResult?> _probeMdns() async {
    final client = MDnsClient();
    const t = Duration(seconds: 2);
    try {
      await client.start();
      await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(mdnsServiceType),
          timeout: t)) {
        await for (final srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: t)) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
              timeout: t)) {
            final e = Endpoint(ip.address.address, srv.port);
            final ch = await probe(e);
            if (ch != null) return DiscoveryResult(e, 'red local (mDNS)', ch);
          }
        }
      }
    } catch (_) {
      // mDNS es opcional: si el sistema no deja abrir el socket, se ignora.
    } finally {
      client.stop();
    }
    return null;
  }

  /// Devuelve los canales si en [e] responde un ChatHub, o null si no.
  static Future<List<pb.Channel>?> probe(Endpoint e,
      {Duration timeout = probeTimeout}) async {
    final channel = ClientChannel(
      e.host,
      port: e.port,
      options: ChannelOptions(
        credentials: const ChannelCredentials.insecure(),
        connectionTimeout: timeout,
      ),
    );
    try {
      final res = await pb.ChatHubClient(channel).listChannels(
        pb.ListChannelsRequest(),
        options: CallOptions(timeout: timeout),
      );
      return res.channels.toList();
    } catch (_) {
      return null;
    } finally {
      unawaited(channel.terminate());
    }
  }
}
