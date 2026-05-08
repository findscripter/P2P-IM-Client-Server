import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import '../providers/auth_provider.dart';
import '../widgets/chat_widgets.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _msgCtrl = TextEditingController();
  Timeline? _timeline;
  bool _loading = true;

  Room? get _room =>
      ref.read(matrixClientProvider).getRoomById(widget.roomId);

  @override
  void initState() {
    super.initState();
    _initTimeline();
  }

  Future<void> _initTimeline() async {
    final room = _room;
    if (room == null) return;
    _timeline = await room.getTimeline(onUpdate: () => setState(() {}));
    await room.requestHistory(historyCount: 50);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _timeline?.cancelSubscriptions();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    await _room?.sendTextEvent(text);
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) return const Scaffold(body: Center(child: Text('会话不存在')));
    final events = _timeline?.events
        .where((e) => e.type == EventTypes.Message)
        .toList()
        .reversed
        .toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(room.getLocalizedDisplayname()),
        actions: [
          IconButton(
            icon: const Icon(Icons.video_call_outlined),
            onPressed: () => context.push('/call/${Uri.encodeComponent(widget.roomId)}'),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.push('/contact/${Uri.encodeComponent(room.directChatMatrixID ?? '')}'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: events.length,
                    itemBuilder: (context, i) => MessageBubble(event: events[i]),
                  ),
          ),
          MessageInputBar(ctrl: _msgCtrl, onSend: _send, room: room),
        ],
      ),
    );
  }
}
