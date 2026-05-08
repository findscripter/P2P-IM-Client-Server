import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.event});
  final Event event;

  @override
  Widget build(BuildContext context) {
    final isMe = event.senderId == event.room.client.userID;
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          event.body,
          style: TextStyle(color: isMe ? cs.onPrimary : cs.onSurface),
        ),
      ),
    );
  }
}

class MessageInputBar extends StatelessWidget {
  const MessageInputBar({
    super.key,
    required this.ctrl,
    required this.onSend,
    required this.room,
  });

  final TextEditingController ctrl;
  final VoidCallback onSend;
  final Room room;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  hintText: '发消息...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                minLines: 1,
                maxLines: 5,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
