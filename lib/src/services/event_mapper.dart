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
/// Usa los campos tipados del contrato para que los eventos no dependan de
/// `raw_json`, que normalmente está desactivado en el servicio.
FeedUpdate? mapEvent(pb.ChatEvent e) {
  final key = channelKeyOf(e.channel);
  final name = channelLabel(e.channel);
  final time = e.hasOccurredAt()
      ? e.occurredAt.toDateTime().toLocal()
      : (e.hasReceivedAt()
          ? e.receivedAt.toDateTime().toLocal()
          : DateTime.now());
  final platform = e.platform != pb.Platform.PLATFORM_UNSPECIFIED
      ? e.platform
      : e.channel.platform;

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
        fragments: List.unmodifiable(m.fragments),
      ));

    case pb.ChatEvent_Payload.messageDeleted:
      final id = e.messageDeleted.messageId.isNotEmpty
          ? e.messageDeleted.messageId
          : _findString(e.rawJson, const [
              'message_id',
              'messageId',
              'target_message_id',
              'deleted_message_id'
            ]);
      return id == null ? null : DeleteMessage(key, id);

    case pb.ChatEvent_Payload.chatCleared:
      return ClearChannel(
          key,
          line(
              LineKind.notice, 'chat_cleared', 'Un moderador limpió el chat.'));

    case pb.ChatEvent_Payload.userBanned:
      final who = _userName(e.userBanned.user) ?? _userFromRaw(e.rawJson);
      return AddLine(line(
          LineKind.notice,
          'user_banned',
          who != null
              ? '$who fue expulsado del chat.'
              : 'Un usuario fue expulsado del chat.'));

    case pb.ChatEvent_Payload.follow:
      final who = _userName(e.follow.follower) ?? _userFromRaw(e.rawJson);
      return AddLine(line(LineKind.event, 'follow',
          who != null ? '$who empezó a seguir el canal' : 'Nuevo seguidor'));

    case pb.ChatEvent_Payload.subscription:
      final sub = e.subscription;
      final who = _userName(sub.subscriber) ?? _userFromRaw(e.rawJson);
      final action = sub.isRenewal ? 'renovó su suscripción' : 'se suscribió';
      final months =
          sub.cumulativeMonths > 0 ? ' · ${sub.cumulativeMonths} meses' : '';
      final message = sub.message.isNotEmpty ? ' · ${sub.message}' : '';
      return AddLine(line(LineKind.event, 'subscription',
          '${who ?? 'Un usuario'} $action$months$message'));

    case pb.ChatEvent_Payload.giftSubscription:
      final gift = e.giftSubscription;
      final who = gift.isAnonymous
          ? null
          : (_userName(gift.gifter) ?? _userFromRaw(e.rawJson));
      final total = gift.total > 0 ? ' ${gift.total}' : '';
      return AddLine(line(
          LineKind.event,
          'gift_subscription',
          who != null
              ? '$who regaló$total suscripciones'
              : 'Se regalaron$total suscripciones'));

    case pb.ChatEvent_Payload.raid:
      final raid = e.raid;
      final who = _userName(raid.fromBroadcaster) ?? _userFromRaw(e.rawJson);
      final viewers =
          raid.viewers > 0 ? ' con ${raid.viewers} espectadores' : '';
      return AddLine(line(LineKind.event, 'raid',
          who != null ? 'Raid de $who$viewers' : 'Llegó un raid$viewers'));

    case pb.ChatEvent_Payload.cheer:
      final cheer = e.cheer;
      final who = cheer.isAnonymous
          ? null
          : (_userName(cheer.user) ?? _userFromRaw(e.rawJson));
      final amount = cheer.amount > 0 ? ' ${cheer.amount} bits' : ' bits';
      return AddLine(line(LineKind.event, 'cheer',
          who != null ? '$who envió$amount' : 'Cheer anónimo de$amount'));

    case pb.ChatEvent_Payload.streamStatus:
      final status = e.streamStatus;
      return AddLine(line(LineKind.notice, 'stream_status',
          status.isLive ? 'El stream comenzó.' : 'El stream terminó.'));

    case pb.ChatEvent_Payload.rewardRedemption:
      final reward = e.rewardRedemption;
      final who = _userName(reward.user) ?? _userFromRaw(e.rawJson);
      final title =
          reward.rewardTitle.isNotEmpty ? ' “${reward.rewardTitle}”' : '';
      final input = reward.userInput.isNotEmpty ? ' · ${reward.userInput}' : '';
      return AddLine(line(LineKind.event, 'reward_redemption',
          '${who ?? 'Un usuario'} canjeó$title$input'));

    case pb.ChatEvent_Payload.notSet:
      return null;
  }
}

String _name(pb.User u) =>
    u.displayName.isNotEmpty ? u.displayName : u.username;

String? _userName(pb.User u) {
  final name = _name(u);
  return name.isEmpty ? null : name;
}

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
