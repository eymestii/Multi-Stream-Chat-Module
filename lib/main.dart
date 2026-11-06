import 'package:flutter/material.dart';

import 'src/services/chat_service.dart';
import 'src/ui/chat_screen.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StreamChatApp());
}

class StreamChatApp extends StatefulWidget {
  const StreamChatApp({super.key});

  @override
  State<StreamChatApp> createState() => _StreamChatAppState();
}

class _StreamChatAppState extends State<StreamChatApp> {
  final service = ChatService();

  @override
  void initState() {
    super.initState();
    service.start();
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamChat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ChatScreen(service: service),
    );
  }
}
