import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../generated/streamchat.pbgrpc.dart' as pb;
import '../models/chat_line.dart';
import 'event_mapper.dart';
import 'service_discovery.dart';

enum ServiceStatus { searching, connecting, connected, reconnecting, notFound }

/// Cliente del servicio ChatHub y estado del feed.
///
/// - Encuentra el servicio (ver [ServiceDiscovery]).
/// - Mantiene abierto StreamEvents y, si se corta, reconecta usando
///   resume_after_id para no perder eventos.
/// - Refresca ListChannels cada 30 s.
/// - Envía mensajes con SendMessage.
class ChatService extends ChangeNotifier {
  ChatService({ServiceDiscovery? discovery})
      : _discovery = discovery ?? ServiceDiscovery();

  static const _prefsKey = 'streamchat.endpoint';
  static const maxLines = 1000;

  final ServiceDiscovery _discovery;

  ServiceStatus _status = ServiceStatus.searching;
  Endpoint? _endpoint;
  String? _endpointSource;
  String? _lastError;
  List<pb.Channel> _channels = const [];
  String? _selectedKey;
  final Set<pb.Platform> _visible = {
    pb.Platform.PLATFORM_TWITCH,
    pb.Platform.PLATFORM_KICK,
  };

  ClientChannel? _grpcChannel;
  pb.ChatHubClient? _client;
  ResponseStream<pb.ChatEvent>? _call;
  StreamSubscription<pb.ChatEvent>? _sub;
  Timer? _retryTimer;
  Timer? _channelsTimer;
  Timer? _flushTimer;
  int _attempt = 0;
  String? _lastEventId;
  bool _disposed = false;

  final List<ChatLine> _lines = [];
  final List<FeedUpdate> _pending = [];
  List<ChatLine>? _cache;

  ServiceStatus get status => _status;
  Endpoint? get endpoint => _endpoint;
  String? get endpointSource => _endpointSource;
  String? get lastError => _lastError;
  bool get isConnected => _status == ServiceStatus.connected;
  List<pb.Channel> get channels => _channels;
  Set<pb.Platform> get visiblePlatforms => Set.unmodifiable(_visible);

  /// Canal al que se escribe desde la barra de envío.
  pb.Channel? get selectedChannel => channelByKey(_selectedKey);

  pb.Channel? channelByKey(String? key) {
    if (key == null) return null;
    for (final c in _channels) {
      if (channelKeyOf(c) == key) return c;
    }
    return null;
  }

  /// Líneas visibles según el filtro de plataformas, de la más vieja a la más nueva.
  List<ChatLine> get lines => _cache ??= List.unmodifiable(
        _visible.length == 2 ? _lines : _lines.where((l) => _visible.contains(l.platform)),
      );

  // ---------------------------------------------------------------- conexión

  Future<void> start() => _discoverAndConnect();

  /// Vuelve a buscar el servicio desde cero.
  void rediscover() {
    _retryTimer?.cancel();
    _teardown();
    _discoverAndConnect();
  }

  /// Conecta a una dirección concreta. Lanza un error si ahí no hay un ChatHub.
  Future<void> connectTo(Endpoint e) async {
    _retryTimer?.cancel();
    final ch = await ServiceDiscovery.probe(e, timeout: const Duration(seconds: 2));
    if (ch == null) {
      throw Exception('No hay un servicio ChatHub respondiendo en $e.');
    }
    await _remember(e);
    _endpointSource = 'configuración manual';
    _applyChannels(ch);
    await _connect(e);
  }

  Future<void> _discoverAndConnect() async {
    if (_disposed) return;
    _setStatus(ServiceStatus.searching);

    final prefs = await SharedPreferences.getInstance();
    final last = Endpoint.parse(prefs.getString(_prefsKey));
    final found = await _discovery.discover(lastKnown: last);
    if (_disposed) return;

    if (found == null) {
      _setStatus(ServiceStatus.notFound);
      _schedule(_discoverAndConnect, const Duration(seconds: 5));
      return;
    }

    await _remember(found.endpoint);
    _endpointSource = found.source;
    _applyChannels(found.channels);
    await _connect(found.endpoint);
  }

  Future<void> _connect(Endpoint e) async {
    _teardown();
    _endpoint = e;
    _setStatus(_attempt == 0 ? ServiceStatus.connecting : ServiceStatus.reconnecting);

    final grpcChannel = ClientChannel(
      e.host,
      port: e.port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    final client = pb.ChatHubClient(grpcChannel);
    _grpcChannel = grpcChannel;
    _client = client;

    try {
      final res = await client.listChannels(
        pb.ListChannelsRequest(),
        options: CallOptions(timeout: const Duration(seconds: 3)),
      );
      _applyChannels(res.channels);
    } catch (err) {
      _lastError = describeError(err);
      _onStreamLost();
      return;
    }
    if (_disposed || _client != client) return;

    final req = pb.StreamEventsRequest();
    if (_lastEventId != null) req.resumeAfterId = _lastEventId!;

    final call = client.streamEvents(req);
    _call = call;
    _sub = call.listen(
      _onEvent,
      onError: (Object err) {
        _lastError = describeError(err);
        _onStreamLost();
      },
      onDone: _onStreamLost,
      cancelOnError: true,
    );

    _attempt = 0;
    _lastError = null;
    _channelsTimer = Timer.periodic(const Duration(seconds: 30), (_) => refreshChannels());
    _setStatus(ServiceStatus.connected);
  }

  void _onStreamLost() {
    if (_disposed) return;
    _teardown();
    _attempt++;
    _setStatus(ServiceStatus.reconnecting);

    // Tras varios fallos seguidos se vuelve a buscar: el servicio pudo
    // reiniciarse en otro puerto.
    if (_attempt >= 4) {
      _attempt = 0;
      _schedule(_discoverAndConnect, const Duration(seconds: 2));
      return;
    }
    final e = _endpoint!;
    _schedule(() => _connect(e), Duration(seconds: min(10, 1 << _attempt)));
  }

  void _teardown() {
    _channelsTimer?.cancel();
    _channelsTimer = null;
    _sub?.cancel();
    _sub = null;
    _call?.cancel();
    _call = null;
    _grpcChannel?.shutdown();
    _grpcChannel = null;
    _client = null;
  }

  void _schedule(FutureOr<void> Function() fn, Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => fn());
  }

  Future<void> _remember(Endpoint e) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, e.toString());
  }

  void _setStatus(ServiceStatus s) {
    if (_disposed) return;
    _status = s;
    notifyListeners();
  }

  // ----------------------------------------------------------------- canales

  Future<void> refreshChannels() async {
    final client = _client;
    if (client == null) return;
    try {
      final res = await client.listChannels(
        pb.ListChannelsRequest(),
        options: CallOptions(timeout: const Duration(seconds: 3)),
      );
      _applyChannels(res.channels);
    } catch (_) {
      // Si el servicio cayó, el stream lo detecta y reconecta.
    }
  }

  void _applyChannels(Iterable<pb.Channel> list) {
    _channels = list.toList()
      ..sort((a, b) {
        final p = a.platform.value.compareTo(b.platform.value);
        return p != 0 ? p : channelLabel(a).toLowerCase().compareTo(channelLabel(b).toLowerCase());
      });
    if (channelByKey(_selectedKey) == null) {
      _selectedKey = _channels.isEmpty ? null : channelKeyOf(_channels.first);
    }
    if (!_disposed) notifyListeners();
  }

  void selectChannel(String key) {
    if (_selectedKey == key) return;
    _selectedKey = key;
    notifyListeners();
  }

  void togglePlatform(pb.Platform p) {
    if (_visible.contains(p)) {
      if (_visible.length > 1) _visible.remove(p);
    } else {
      _visible.add(p);
    }
    _cache = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------ envío

  /// Envía [text] al canal. Lanza un error con un motivo legible si el
  /// servicio no lo acepta. El mensaje enviado vuelve por StreamEvents,
  /// así que no se añade al feed aquí.
  Future<void> sendMessage(
    pb.Channel channel,
    String text, {
    String? replyToMessageId,
  }) async {
    final client = _client;
    if (client == null || !isConnected) {
      throw Exception('No hay conexión con el servicio de chat.');
    }
    final req = pb.SendMessageRequest()
      ..platform = channel.platform
      ..channelId = channel.id
      ..text = text;
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      req.replyToMessageId = replyToMessageId;
    }

    final pb.SendMessageResponse res;
    try {
      res = await client.sendMessage(
        req,
        options: CallOptions(timeout: const Duration(seconds: 10)),
      );
    } catch (err) {
      throw Exception(describeError(err));
    }
    if (!res.accepted) {
      throw Exception(res.dropReason.isNotEmpty
          ? res.dropReason
          : 'La plataforma no aceptó el mensaje.');
    }

    // Se añade localmente para que aparezca en la UI aunque el mensaje
    // no regrese por el stream de eventos (p. ej. Kick sin webhook activo
    // o mensaje propio no entregado por la plataforma).
    final now = DateTime.now();
    final msgId = res.messageId.isNotEmpty ? res.messageId : '';
    _lines.add(ChatLine(
      id: msgId,
      platform: channel.platform,
      channelKey: channelKeyOf(channel),
      channelName: channelLabel(channel),
      kind: LineKind.message,
      timestamp: now,
      text: text,
      username: '',
      messageId: msgId.isNotEmpty ? msgId : null,
    ));
    _cache = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------- feed

  void _onEvent(pb.ChatEvent e) {
    if (e.id.isNotEmpty) _lastEventId = e.id;
    final update = mapEvent(e);
    if (update == null) return;
    _pending.add(update);
    // Se agrupa cada 100 ms para no reconstruir la UI en cada mensaje.
    _flushTimer ??= Timer(const Duration(milliseconds: 100), _flush);
  }

  void _flush() {
    _flushTimer = null;
    if (_pending.isEmpty || _disposed) return;

    for (final u in _pending) {
      switch (u) {
        case AddLine(:final line):
          _lines.add(line);
        case DeleteMessage(:final channelKey, :final messageId):
          for (final l in _lines) {
            if (l.channelKey == channelKey && l.messageId == messageId) l.deleted = true;
          }
        case ClearChannel(:final channelKey, :final notice):
          _lines.removeWhere((l) => l.channelKey == channelKey);
          _lines.add(notice);
      }
    }
    _pending.clear();

    if (_lines.length > maxLines) _lines.removeRange(0, _lines.length - maxLines);
    _cache = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _flushTimer?.cancel();
    _teardown();
    super.dispose();
  }
}

/// Traduce errores de gRPC a un texto que se pueda mostrar.
String describeError(Object err) {
  if (err is GrpcError) {
    switch (err.code) {
      case StatusCode.unavailable:
        return 'El servicio de chat no responde.';
      case StatusCode.deadlineExceeded:
        return 'El servicio tardó demasiado en responder.';
      case StatusCode.unimplemented:
        return 'El servicio no reconoce la llamada. Revisa que el .proto sea el mismo.';
      case StatusCode.invalidArgument:
        return err.message ?? 'El servicio rechazó los datos enviados.';
      case StatusCode.permissionDenied:
      case StatusCode.unauthenticated:
        return err.message ?? 'El servicio no tiene permiso para esa acción.';
      default:
        return err.message ?? err.codeName;
    }
  }
  return err.toString().replaceFirst('Exception: ', '');
}
