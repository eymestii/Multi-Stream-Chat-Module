import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../generated/streamchat.pbgrpc.dart' as pb;
import '../../models/chat_line.dart';
import '../../services/chat_service.dart';
import '../theme.dart';

/// Barra de envío. El destino es un canal de ListChannels: de ahí salen
/// SendMessageRequest.platform y SendMessageRequest.channel_id
/// (broadcaster_user_id). Enter envía, Esc cancela la respuesta.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.service,
    required this.replyTo,
    required this.onCancelReply,
    required this.onSent,
  });

  final ChatService service;
  final ChatLine? replyTo;
  final VoidCallback onCancelReply;
  final VoidCallback onSent;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  ChatService get service => widget.service;

  @override
  void didUpdateWidget(Composer old) {
    super.didUpdateWidget(old);
    if (widget.replyTo != null && widget.replyTo != old.replyTo) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? _blocker(pb.Channel? target) {
    if (!service.isConnected) return 'Sin conexión con el servicio de chat.';
    if (target == null) return 'No hay canales disponibles para escribir.';
    return null;
  }

  Future<void> _send(pb.Channel target) async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;

    // Solo se responde si el mensaje es del mismo canal que el destino.
    final reply = widget.replyTo;
    final replyId =
        reply != null && reply.channelKey == channelKeyOf(target) ? reply.messageId : null;

    setState(() => _sending = true);
    try {
      await service.sendMessage(target, text, replyToMessageId: replyId);
      _text.clear();
      widget.onSent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se envió el mensaje: ${describeError(e)}'),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = service.selectedChannel;
    final blocker = _blocker(target);
    final reply = widget.replyTo;
    final replyValid = reply != null && target != null && reply.channelKey == channelKeyOf(target);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Palette.surface,
        border: Border(top: BorderSide(color: Palette.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyValid)
            _ReplyBar(line: reply, onCancel: widget.onCancelReply),
          Row(
            children: [
              if (target != null)
                _TargetPicker(
                  channels: service.channels,
                  selected: target,
                  onChanged: (c) {
                    service.selectChannel(channelKeyOf(c));
                    _focus.requestFocus();
                  },
                ),
              if (target != null) const SizedBox(width: 8),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): widget.onCancelReply,
                  },
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    enabled: blocker == null,
                    inputFormatters: [LengthLimitingTextInputFormatter(500)],
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) {
                      if (target != null) _send(target);
                    },
                    decoration: InputDecoration(
                      hintText: blocker ??
                          (replyValid
                              ? 'Responder a ${reply.username}'
                              : 'Escribe en el chat de ${channelLabel(target!)}'),
                      hintStyle: const TextStyle(color: Palette.muted),
                      filled: true,
                      fillColor: Palette.raised,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: target != null
                              ? platformColor(target.platform)
                              : Palette.line,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: blocker == null && !_sending ? () => _send(target!) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(88, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enviar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.line, required this.onCancel});

  final ChatLine line;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: Palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Respondiendo a '),
                TextSpan(
                  text: line.username,
                  style: TextStyle(
                    color: readableNameColor(line.color, line.username),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ': ${line.text}'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Palette.muted, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Cancelar respuesta (Esc)',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: Palette.muted),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.channels,
    required this.selected,
    required this.onChanged,
  });

  final List<pb.Channel> channels;
  final pb.Channel selected;
  final ValueChanged<pb.Channel> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<pb.Channel>(
      tooltip: 'Elegir en qué canal escribir',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final c in channels)
          PopupMenuItem(value: c, child: _TargetLabel(channel: c, showPlatform: true)),
      ],
      child: Container(
        height: 46,
        constraints: const BoxConstraints(maxWidth: 210),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Palette.raised,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: _TargetLabel(channel: selected)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 16, color: Palette.muted),
          ],
        ),
      ),
    );
  }
}

class _TargetLabel extends StatelessWidget {
  const _TargetLabel({required this.channel, this.showPlatform = false});

  final pb.Channel channel;
  final bool showPlatform;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: platformColor(channel.platform),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(channelLabel(channel),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (showPlatform) ...[
          const SizedBox(width: 8),
          Text(platformName(channel.platform),
              style: const TextStyle(color: Palette.muted, fontSize: 12)),
        ],
      ],
    );
  }
}
