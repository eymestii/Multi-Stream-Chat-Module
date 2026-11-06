import 'package:flutter/painting.dart';

import '../generated/streamchat.pbgrpc.dart' as pb;

enum LineKind {
  /// Mensaje de un usuario.
  message,

  /// Evento destacado del canal: follow, sub, raid, bits…
  event,

  /// Aviso del sistema: chat limpiado, usuario baneado…
  notice,
}

/// Una línea del feed, ya normalizada para la interfaz.
class ChatLine {
  ChatLine({
    required this.id,
    required this.platform,
    required this.channelKey,
    required this.channelName,
    required this.kind,
    required this.timestamp,
    required this.text,
    this.username = '',
    this.color,
    this.badges = const [],
    this.messageId,
    this.replyTo,
    this.eventType,
  });

  final String id;
  final pb.Platform platform;

  /// "twitch:1153760357", mismo formato que usa el contrato.
  final String channelKey;
  final String channelName;
  final LineKind kind;
  final DateTime timestamp;
  final String text;
  final String username;
  final Color? color;
  final List<String> badges;

  /// ID del mensaje en la plataforma; se usa para responder y para borrar.
  final String? messageId;

  /// "usuario: texto" del mensaje al que responde, si es una respuesta.
  final String? replyTo;

  /// follow, subscription, raid… (solo para kind == event / notice).
  final String? eventType;

  /// Se marca cuando llega un MessageDeleted para este mensaje.
  bool deleted = false;
}

String platformSlug(pb.Platform p) {
  if (p == pb.Platform.PLATFORM_TWITCH) return 'twitch';
  if (p == pb.Platform.PLATFORM_KICK) return 'kick';
  return 'desconocida';
}

String channelKeyOf(pb.Channel c) => '${platformSlug(c.platform)}:${c.id}';

String channelLabel(pb.Channel c) =>
    c.displayName.isNotEmpty ? c.displayName : (c.slug.isNotEmpty ? c.slug : c.id);

Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
