import 'package:flutter/material.dart';

import '../../services/chat_service.dart';
import '../../services/service_discovery.dart';
import '../theme.dart';

Future<void> showConnectDialog(BuildContext context, ChatService service) {
  return showDialog(
    context: context,
    builder: (_) => ConnectDialog(service: service),
  );
}

/// Conectar a mano a otra dirección, o volver a la detección automática.
class ConnectDialog extends StatefulWidget {
  const ConnectDialog({super.key, required this.service});

  final ChatService service;

  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  late final _host = TextEditingController(text: widget.service.endpoint?.host ?? '127.0.0.1');
  late final _port = TextEditingController(
      text: '${widget.service.endpoint?.port ?? ServiceDiscovery.defaultPort}');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final port = int.tryParse(_port.text.trim());
    if (_host.text.trim().isEmpty || port == null) {
      setState(() => _error = 'Escribe un host y un puerto válidos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.connectTo(Endpoint(_host.text.trim(), port));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _auto() {
    widget.service.rediscover();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Conexión con el servicio'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'La app busca el servicio sola al arrancar. Usa esto si el '
              'Websocket Module corre en otra dirección o puerto.',
              style: TextStyle(color: Palette.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _host,
                    decoration: const InputDecoration(labelText: 'Host'),
                    onSubmitted: (_) => _connect(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Puerto'),
                    onSubmitted: (_) => _connect(),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Palette.warn)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _auto,
          child: const Text('Detectar automáticamente'),
        ),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: _busy
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Conectar'),
        ),
      ],
    );
  }
}
