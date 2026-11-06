import 'package:flutter/material.dart';

import '../../generated/streamchat.pbgrpc.dart' as pb;
import '../../models/chat_line.dart';
import '../theme.dart';

/// Una línea del feed. La franja izquierda indica la plataforma.
/// Al pasar el ratón por un mensaje aparece el botón de responder.
class MessageTile extends StatefulWidget {
  const MessageTile({
    super.key,
    required this.line,
    this.showChannel = false,
    this.onReply,
  });

  final ChatLine line;
  final bool showChannel;
  final VoidCallback? onReply;

  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    return switch (l.kind) {
      LineKind.message => _message(l),
      LineKind.event => _event(l),
      LineKind.notice => _notice(l),
    };
  }

  Widget _message(ChatLine l) {
    final nameColor = readableNameColor(l.color, l.username);
    const muted = TextStyle(color: Palette.muted, fontSize: 12);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 1, 12, 1),
        decoration: BoxDecoration(
          color: _hover ? Palette.hover : null,
          border: Border(
              left: BorderSide(color: platformColor(l.platform), width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (l.replyTo != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '↳ respondiendo a ${l.replyTo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${formatTime(l.timestamp)}  ',
                        style: muted.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      if (widget.showChannel)
                        TextSpan(text: '${l.channelName}  ', style: muted),
                      for (final b in l.badges)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: _Badge(b),
                        ),
                      TextSpan(
                        text: l.username,
                        style: TextStyle(
                            color: nameColor, fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ': '),
                      l.deleted
                          ? const TextSpan(
                              text: 'mensaje eliminado',
                              style: TextStyle(
                                  color: Palette.muted,
                                  fontStyle: FontStyle.italic),
                            )
                          : TextSpan(children: _messageContent(l)),
                    ]),
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                ],
              ),
            ),
            // Siempre ocupa su sitio para que la línea no cambie de alto.
            SizedBox(
              width: 30,
              height: 22,
              child: widget.onReply != null && _hover
                  ? IconButton(
                      tooltip: 'Responder',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: const Icon(Icons.reply, color: Palette.muted),
                      onPressed: widget.onReply,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _messageContent(ChatLine line) {
    if (line.fragments.isEmpty) return [TextSpan(text: line.text)];

    return line.fragments.map((fragment) {
      switch (fragment.whichKind()) {
        case pb.MessageFragment_Kind.text:
          return TextSpan(text: fragment.text);
        case pb.MessageFragment_Kind.emote:
          final emote = fragment.emote;
          return _networkImageSpan(
            url: emote.imageUrl,
            fallback: emote.name,
            tooltip: emote.name,
          );
        case pb.MessageFragment_Kind.mention:
          return TextSpan(
            text: '@${fragment.mention.username}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          );
        case pb.MessageFragment_Kind.cheermote:
          final cheer = fragment.cheermote;
          return TextSpan(
            text: '${cheer.prefix}${cheer.bits}',
            style: const TextStyle(
              color: Color(0xFFB794F4),
              fontWeight: FontWeight.w700,
            ),
          );
        case pb.MessageFragment_Kind.gif:
          final gif = fragment.gif;
          return _networkImageSpan(
            url: gif.url,
            fallback: '[GIF]',
            tooltip: 'GIF',
          );
        case pb.MessageFragment_Kind.notSet:
          return const TextSpan();
      }
    }).toList(growable: false);
  }

  InlineSpan _networkImageSpan({
    required String url,
    required String fallback,
    required String tooltip,
  }) {
    if (url.isEmpty) return TextSpan(text: fallback);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Tooltip(
        message: tooltip,
        child: Image.network(
          url,
          width: 28,
          height: 28,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => Text(fallback),
        ),
      ),
    );
  }

  Widget _event(ChatLine l) {
    final color = platformColor(l.platform);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Palette.raised,
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Icon(_eventIcon(l.eventType), size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l.text,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          Text(
            widget.showChannel
                ? '${l.channelName} · ${formatTime(l.timestamp)}'
                : formatTime(l.timestamp),
            style: const TextStyle(color: Palette.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _notice(ChatLine l) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
              color: platformColor(l.platform).withAlpha(90), width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(_eventIcon(l.eventType), size: 14, color: Palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${formatTime(l.timestamp)}  ${l.channelName}: ${l.text}',
              style: const TextStyle(
                  color: Palette.muted,
                  fontStyle: FontStyle.italic,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _eventIcon(String? type) => switch (type) {
        'follow' => Icons.favorite_border,
        'subscription' => Icons.star_border,
        'gift_subscription' => Icons.card_giftcard,
        'raid' => Icons.groups_outlined,
        'cheer' => Icons.diamond_outlined,
        'reward_redemption' => Icons.redeem,
        'user_banned' => Icons.block,
        'chat_cleared' => Icons.cleaning_services_outlined,
        'stream_status' => Icons.sensors,
        _ => Icons.info_outline,
      };
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Palette.raised,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style:
              const TextStyle(fontSize: 11, color: Palette.muted, height: 1.3)),
    );
  }
}
