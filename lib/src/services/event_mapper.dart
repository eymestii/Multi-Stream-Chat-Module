import 'dart:convert';

import '../generated/streamchat.pbgrpc.dart' as pb;
import '../models/chat_line.dart';

/// Lo que un ChatEvent le hace al feed.
sealed class FeedUpdate {
  const FeedUpdate();
}

class AddLine extends FeedUpdate {
  const AddLine(this.line);
  final ChatLine line;
}

class DeleteMessage extends FeedUpdate {
  const DeleteMessage(this.channelKey, this.messageId);
  final String channelKey;
  final String messageId;
}

class ClearChannel extends FeedUpdate {
  const ClearChannel(this.channelKey, this.notice);
  final String channelKey;
  final ChatLine notice;
}

/// Convierte un ChatEvent del servicio en un cambio del feed.
///
/// Los mensajes de chat usan los campos tipados del contrato. Para el resto
/// de eventos (follow, raid, ban…) el resumen del contrato no detalla sus
/// campos, así que el nombre del usuario se saca de `raw_json` si viene.
/// Con el .proto real se pueden leer esos campos directamente aquí.
FeedUpdate? mapEvent(pb.ChatEvent e) {
  final key = channelKeyOf(e.channel);
  final name = channelLabel(e.channel);
  final time = e.hasOccurredAt()
      ? e.occurredAt.toDateTime().toLocal()
      : (e.hasReceivedAt() ? e.receivedAt.toDateTime().toLocal() : DateTime.now());
  final platform =
      e.platform != pb.Platform.PLATFORM_UNSPECIFIED ? e.platform : e.channel.platform;

  ChatLine line(LineKind kind, String type, String text) => ChatLine(
        id: e.id,
        platform: platform,
        channelKey: key,
        channelName: name,
        kind: kind,
        timestamp: time,
        text: text,
        eventType: type,
      );

  final who = _userFromRaw(e.rawJson);

  switch (e.whichPayload()) {
    case pb.ChatEvent_Payload.message:
      final m = e.message;
      final s = m.sender;
      return AddLine(ChatLine(
        id: e.id,
        platform: platform,
        channelKey: key,
        channelName: name,
        kind: LineKind.message,
        timestamp: time,
        text: m.text,
        username: s.displayName.isNotEmpty ? s.displayName : s.username,
        color: parseHexColor(s.color),
        badges: [
          if (s.isBroadcaster) 'streamer',
          if (s.isModerator) 'mod',
          if (s.isVip) 'vip',
          if (s.isSubscriber) 'sub',
        ],
        messageId: m.messageId.isNotEmpty ? m.messageId : null,
        replyTo: m.hasReply()
            ? '${_name(m.reply.parentSender)}: ${m.reply.parentText}'
            : null,
      ));

    case pb.ChatEvent_Payload.messageDeleted:
      final id = _findString(e.rawJson,
          const ['message_id', 'messageId', 'target_message_id', 'deleted_message_id']);
      return id == null ? null : DeleteMessage(key, id);

    case pb.ChatEvent_Payload.chatCleared:
      return ClearChannel(key,
          line(LineKind.notice, 'chat_cleared', 'Un moderador limpió el chat.'));

    case pb.ChatEvent_Payload.userBanned:
      return AddLine(line(LineKind.notice, 'user_banned',
          who != null ? '$who fue expulsado del chat.' : 'Un usuario fue expulsado del chat.'));

    case pb.ChatEvent_Payload.follow:
      return AddLine(line(LineKind.event, 'follow',
          who != null ? '$who empezó a seguir el canal' : 'Nuevo seguidor'));

    case pb.ChatEvent_Payload.subscription:
      return AddLine(line(LineKind.event, 'subscription',
          who != null ? '$who se suscribió' : 'Nueva suscripción'));

    case pb.ChatEvent_Payload.giftSubscription:
      return AddLine(line(LineKind.event, 'gift_subscription',
          who != null ? '$who regaló suscripciones' : 'Suscripciones regaladas'));

    case pb.ChatEvent_Payload.raid:
      return AddLine(line(LineKind.event, 'raid',
          who != null ? 'Raid de $who' : 'Llegó un raid'));

    case pb.ChatEvent_Payload.cheer:
      return AddLine(line(LineKind.event, 'cheer',
          who != null ? '$who envió bits' : 'Nuevos bits'));

    case pb.ChatEvent_Payload.streamStatus:
      return AddLine(line(LineKind.notice, 'stream_status',
          'El estado del stream cambió.'));

    case pb.ChatEvent_Payload.rewardRedemption:
      return AddLine(line(LineKind.event, 'reward_redemption',
          who != null ? '$who canjeó una recompensa' : 'Recompensa canjeada'));

    case pb.ChatEvent_Payload.notSet:
      return null;
  }
}

String _name(pb.User u) => u.displayName.isNotEmpty ? u.displayName : u.username;

const _userKeys = [
  'user_name',
  'user_display_name',
  'display_name',
  'username',
  'user_login',
  'from_broadcaster_user_name',
  'gifter_username',
  'banned_user_name',
];

String? _userFromRaw(String raw) => _findString(raw, _userKeys);

/// Busca la primera clave de [keys] con un valor de texto en un JSON anidado.
String? _findString(String raw, List<String> keys) {
  if (raw.isEmpty) return null;
  try {
    return _search(jsonDecode(raw), keys);
  } catch (_) {
    return null;
  }
}

String? _search(Object? node, List<String> keys) {
  if (node is Map) {
    for (final k in keys) {
      final v = node[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is num) return v.toString();
    }
    for (final v in node.values) {
      final found = _search(v, keys);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final v in node) {
      final found = _search(v, keys);
      if (found != null) return found;
    }
  }
  return null;
}
