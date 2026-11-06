import 'package:flutter/material.dart';

import '../generated/streamchat.pbgrpc.dart' as pb;
import '../models/chat_line.dart';
import '../services/chat_service.dart';
import 'theme.dart';
import 'widgets/composer.dart';
import 'widgets/connect_dialog.dart';
import 'widgets/message_tile.dart';
import 'widgets/sidebar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.service});

  final ChatService service;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();

  /// Al subir para leer, la lista se congela para que no salte con cada
  /// mensaje nuevo. Al volver abajo se descongela.
  List<ChatLine>? _frozen;

  /// Mensaje al que se está respondiendo.
  ChatLine? _replyTo;

  ChatService get service => widget.service;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final away = _scroll.hasClients && _scroll.offset > 48;
    if (away && _frozen == null) {
      setState(() => _frozen = service.lines);
    } else if (!away && _frozen != null) {
      setState(() => _frozen = null);
    }
  }

  void _jumpToLatest() {
    setState(() => _frozen = null);
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  void _startReply(ChatLine line) {
    service.selectChannel(line.channelKey);
    setState(() => _replyTo = line);
  }

  int _countUnseen(List<ChatLine> frozen, List<ChatLine> live) {
    if (frozen.isEmpty) return live.length;
    final lastId = frozen.last.id;
    final i = live.lastIndexWhere((l) => l.id == lastId);
    return i < 0 ? live.length : live.length - 1 - i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Sidebar(service: service),
          const VerticalDivider(width: 1, thickness: 1, color: Palette.line),
          Expanded(
            child: ListenableBuilder(
              listenable: service,
              builder: (context, _) {
                final live = service.lines;
                final shown = _frozen ?? live;
                final unseen = _frozen == null ? 0 : _countUnseen(_frozen!, live);
                final showChannel = service.channels.length > 1;

                return Column(
                  children: [
                    _FeedHeader(service: service, onFilterChanged: _jumpToLatest),
                    const Divider(height: 1, thickness: 1, color: Palette.line),
                    Expanded(
                      child: Stack(
                        children: [
                          if (shown.isEmpty)
                            _EmptyFeed(service: service)
                          else
                            SelectionArea(
                              child: ListView.builder(
                                controller: _scroll,
                                reverse: true, // el más nuevo abajo y pegado
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                itemCount: shown.length,
                                itemBuilder: (_, i) {
                                  final line = shown[shown.length - 1 - i];
                                  return MessageTile(
                                    key: ValueKey(line.id),
                                    line: line,
                                    showChannel: showChannel,
                                    onReply: service.isConnected &&
                                            line.kind == LineKind.message &&
                                            line.messageId != null &&
                                            !line.deleted
                                        ? () => _startReply(line)
                                        : null,
                                  );
                                },
                              ),
                            ),
                          if (_frozen != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 16,
                              child: Center(
                                child: _JumpButton(count: unseen, onPressed: _jumpToLatest),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Composer(
                      service: service,
                      replyTo: _replyTo,
                      onCancelReply: () => setState(() => _replyTo = null),
                      onSent: () => setState(() => _replyTo = null),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.service, required this.onFilterChanged});

  final ChatService service;
  final VoidCallback onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final visible = service.visiblePlatforms;
    final count = service.channels.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Row(
        children: [
          Text('Chat', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 10),
          if (count > 0)
            Text(count == 1 ? '1 canal' : '$count canales',
                style: const TextStyle(color: Palette.muted, fontSize: 13)),
          const Spacer(),
          for (final p in const [pb.Platform.PLATFORM_TWITCH, pb.Platform.PLATFORM_KICK]) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: Text(platformName(p)),
              avatar: CircleAvatar(radius: 4, backgroundColor: platformColor(p)),
              selected: visible.contains(p),
              showCheckmark: false,
              tooltip: visible.contains(p)
                  ? 'Ocultar mensajes de ${platformName(p)}'
                  : 'Mostrar mensajes de ${platformName(p)}',
              onSelected: (_) {
                service.togglePlatform(p);
                onFilterChanged();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = switch (count) {
      0 => 'Ir al final',
      1 => 'Ver 1 mensaje nuevo',
      _ => 'Ver $count mensajes nuevos',
    };
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_downward, size: 16),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Palette.raised,
        foregroundColor: Palette.text,
      ),
    );
  }
}

/// Estado vacío: cambia según en qué punto de la conexión estemos.
class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.service});

  final ChatService service;

  @override
  Widget build(BuildContext context) {
    final (String title, String body, bool spinner, bool actions) = switch (service.status) {
      ServiceStatus.searching => (
          'Buscando el servicio de chat',
          'Probando en este equipo y en la red local.',
          true,
          false,
        ),
      ServiceStatus.connecting || ServiceStatus.reconnecting => (
          'Conectando con ${service.endpoint}',
          service.lastError ?? 'Abriendo el stream de eventos.',
          true,
          false,
        ),
      ServiceStatus.notFound => (
          'No se encontró el servicio de chat',
          'Se buscó en 127.0.0.1 (puertos 50050–50060) y en la red local. '
              'Comprueba que el Websocket Module esté en marcha. '
              'Se vuelve a buscar cada 5 segundos.',
          false,
          true,
        ),
      ServiceStatus.connected when service.channels.isEmpty => (
          'El servicio no escucha ningún canal',
          'Configura los canales en el Websocket Module. '
              'Esta lista se actualiza sola cada 30 segundos.',
          false,
          false,
        ),
      ServiceStatus.connected => (
          'Conectado',
          'Los mensajes aparecerán aquí en cuanto alguien escriba.',
          false,
          false,
        ),
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner) ...[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Palette.muted),
              ),
              const SizedBox(height: 16),
            ],
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Palette.muted, height: 1.5)),
            if (actions) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: service.rediscover,
                    child: const Text('Buscar de nuevo'),
                  ),
                  OutlinedButton(
                    onPressed: () => showConnectDialog(context, service),
                    child: const Text('Conectar manualmente'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
