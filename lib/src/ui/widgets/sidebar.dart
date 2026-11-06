import 'package:flutter/material.dart';

import '../../generated/streamchat.pbgrpc.dart' as pb;
import '../../models/chat_line.dart';
import '../../services/chat_service.dart';
import '../theme.dart';
import 'connect_dialog.dart';

/// Panel izquierdo: estado de la conexión con el servicio y canales que
/// el servicio está escuchando (ListChannels). Elegir un canal lo deja
/// como destino de la barra de envío.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key, required this.service});

  final ChatService service;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  /// Indica si el panel está extendido (true) o colapsado (false).
  bool _isOpen = true;

  void _toggle() => setState(() => _isOpen = !_isOpen);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _isOpen ? 268 : 56,
      color: Palette.surface,
      child: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          final selected = widget.service.selectedChannel;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isOpen) ...[
                _ConnectionCard(service: widget.service),
                const Divider(height: 1, thickness: 1, color: Palette.line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
                  child: Row(
                    children: [
                      Text('Canales',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Actualizar canales',
                        icon: const Icon(
                          Icons.refresh,
                          size: 18,
                          color: Palette.muted,
                        ),
                        onPressed: widget.service.isConnected
                            ? widget.service.refreshChannels
                            : null,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: widget.service.channels.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'Los canales aparecen aquí cuando el servicio '
                            'los está escuchando.',
                            style: TextStyle(color: Palette.muted, height: 1.5),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            for (final c in widget.service.channels)
                              _ChannelRow(
                                channel: c,
                                selected: selected != null &&
                                    channelKeyOf(selected) == channelKeyOf(c),
                                onTap: () =>
                                    widget.service.selectChannel(
                                        channelKeyOf(c)),
                              ),
                          ],
                        ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Text(
                    'Los canales se configuran en el Websocket Module.',
                    style: TextStyle(
                      color: Palette.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                _SidebarToggleButton(isOpen: true, onPressed: _toggle),
              ] else ...[
                // Panel colapsado: solo un botón compacto para volver a abrirlo.
                Expanded(
                  child: Center(
                    child: _SidebarToggleButton(
                      isOpen: false,
                      onPressed: _toggle,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Botón para colapsar o expandir el sidebar, ubicado al final del panel.
class _SidebarToggleButton extends StatelessWidget {
  const _SidebarToggleButton({required this.isOpen, required this.onPressed});

  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = isOpen ? Icons.chevron_left : Icons.chevron_right;
    final label = isOpen ? 'Ocultar sidebar' : 'Mostrar sidebar';

    if (!isOpen) {
      // Versión compacta: solo ícono con tooltip, para el panel estrecho.
      return Tooltip(
        message: label,
        child: IconButton(
          icon: Icon(icon, size: 20, color: Palette.muted),
          onPressed: onPressed,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: Palette.muted),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Palette.muted,
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.service});

  final ChatService service;

  @override
  Widget build(BuildContext context) {
    final (String label, Color dot) = switch (service.status) {
      ServiceStatus.connected => ('Conectado', Palette.ok),
      ServiceStatus.connecting => ('Conectando…', Palette.muted),
      ServiceStatus.reconnecting => ('Reconectando…', Palette.warn),
      ServiceStatus.searching => ('Buscando servicio…', Palette.muted),
      ServiceStatus.notFound => ('Servicio no encontrado', Palette.warn),
    };
    final endpoint = service.endpoint;
    final detail = switch (service.status) {
      ServiceStatus.notFound || ServiceStatus.searching => 'Sin conexión',
      _ => endpoint == null
          ? ''
          : service.endpointSource != null
              ? '$endpoint · ${service.endpointSource}'
              : endpoint.toString(),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      child: Row(
        children: [
          CircleAvatar(radius: 4, backgroundColor: dot),
          const SizedBox(width: 10),
          Expanded(
            child: _MaybeTooltip(
              message: service.lastError,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (detail.isNotEmpty)
                    Text(detail,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Palette.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cambiar conexión',
            icon: const Icon(Icons.tune, size: 18, color: Palette.muted),
            onPressed: () => showConnectDialog(context, service),
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final pb.Channel channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = channel.slug.isNotEmpty && channel.slug != channelLabel(channel)
        ? '${platformName(channel.platform)} · ${channel.slug}'
        : platformName(channel.platform);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? Palette.raised : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Tooltip(
            message: 'Escribir en ${channelLabel(channel)} · ID ${channel.id}',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 30,
                    decoration: BoxDecoration(
                      color: platformColor(channel.platform),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(channelLabel(channel),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(sub,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Palette.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.edit_outlined, size: 14, color: Palette.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MaybeTooltip extends StatelessWidget {
  const _MaybeTooltip({required this.message, required this.child});

  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      message == null ? child : Tooltip(message: message!, child: child);
}
