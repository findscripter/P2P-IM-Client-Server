import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import '../providers/auth_provider.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/portal_avatar.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/app_theme.dart';

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
    void rebuild() {
      if (mounted) setState(() {});
    }

    try {
      _timeline = await room.getTimeline(
        onUpdate: rebuild,
        onChange: (_) => rebuild(),
        onInsert: (_) => rebuild(),
        onRemove: (_) => rebuild(),
      );
    } on Object catch (e) {
      debugPrint('getTimeline failed: $e');
    }
    if (mounted) setState(() => _loading = false);
    // 灌历史进 Timeline（timeline 级，不是 room 级）
    final tl = _timeline;
    if (tl != null) {
      unawaited(_backfillHistory(tl));
    }
  }

  Future<void> _backfillHistory(Timeline timeline) async {
    // 拉够 50 条历史；matrix SDK 单次返回有限，需要循环
    var attempts = 0;
    while (attempts < 5 &&
        timeline.canRequestHistory &&
        timeline.events.where((e) => e.type == EventTypes.Message).length < 50) {
      try {
        await timeline.requestHistory(historyCount: 30);
      } on Object catch (e) {
        debugPrint('timeline.requestHistory failed: $e');
        break;
      }
      attempts++;
    }
    if (mounted) setState(() {});
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
    final t = context.tk;
    if (room == null) {
      return const Scaffold(body: Center(child: Text('会话不存在')));
    }

    // Timeline.events is newest-first; ListView reverse:true puts index 0 at
    // bottom — so we keep newest-first to render newest at the bottom.
    final events = _timeline?.events
            .where((e) => e.type == EventTypes.Message)
            .toList() ??
        [];

    final mxid = room.directChatMatrixID ?? '';
    final name = room.getLocalizedDisplayname();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            PortalAvatar(seed: name, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.sans(
                          size: 14,
                          weight: FontWeight.w600,
                          color: t.text)),
                  if (mxid.isNotEmpty)
                    Text(mxid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppTheme.mono(size: 11, color: t.accentCool)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.phone, size: 18, color: t.text),
            onPressed: () => context.push(
                '/call/${Uri.encodeComponent(widget.roomId)}'),
          ),
          IconButton(
            icon: Icon(LucideIcons.video, size: 18, color: t.text),
            onPressed: () => context.push(
                '/call/${Uri.encodeComponent(widget.roomId)}'),
          ),
          IconButton(
            icon: Icon(LucideIcons.info, size: 18, color: t.text),
            onPressed: () => context.push(
                '/contact/${Uri.encodeComponent(mxid)}'),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.border),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: t.accent),
                    ),
                  )
                : events.isEmpty
                    ? Center(
                        child: Text('开始你们的第一条消息',
                            style: AppTheme.sans(
                                size: 13, color: t.textMute)))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: events.length,
                        itemBuilder: (context, i) =>
                            MessageBubble(event: events[i]),
                      ),
          ),
          MessageInputBar(ctrl: _msgCtrl, onSend: _send, room: room),
        ],
      ),
    );
  }
}
