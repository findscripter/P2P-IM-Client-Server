import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import '../providers/auth_provider.dart';

class RequestsPage extends ConsumerWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixClientProvider);
    final invites = client.rooms.where((r) => r.membership == Membership.invite).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('好友申请')),
      body: invites.isEmpty
          ? const Center(child: Text('暂无待处理申请'))
          : ListView.builder(
              itemCount: invites.length,
              itemBuilder: (context, i) {
                final room = invites[i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(room.getLocalizedDisplayname().characters.first.toUpperCase()),
                  ),
                  title: Text(room.getLocalizedDisplayname()),
                  subtitle: Text(room.isDirectChat ? '好友申请' : '群邀请'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () => room.join(),
                        tooltip: '接受',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => room.leave(),
                        tooltip: '拒绝',
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
