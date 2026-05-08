import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import '../providers/auth_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(matrixClientProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portal IM'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _tab == 0
          ? _ChatList(client: client)
          : _tab == 1
              ? _ContactList(client: client)
              : _MePage(client: client),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: '消息'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: '联系人'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我'),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: () => context.push('/add-contact'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _ChatList extends ConsumerWidget {
  const _ChatList({required this.client});
  final Client client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = client.rooms;
    if (rooms.isEmpty) {
      return const Center(child: Text('暂无会话，点击 + 添加联系人'));
    }
    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (context, i) {
        final room = rooms[i];
        final isDm = room.isDirectChat;
        return ListTile(
          leading: CircleAvatar(
            child: Text(room.getLocalizedDisplayname().characters.first.toUpperCase()),
          ),
          title: Text(room.getLocalizedDisplayname()),
          subtitle: Text(
            room.lastEvent?.body ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: room.notificationCount > 0
              ? Badge(label: Text('${room.notificationCount}'))
              : null,
          onTap: () => isDm
              ? context.push('/chat/${Uri.encodeComponent(room.id)}')
              : context.push('/group/${Uri.encodeComponent(room.id)}'),
        );
      },
    );
  }
}

class _ContactList extends ConsumerWidget {
  const _ContactList({required this.client});
  final Client client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dmRooms = client.rooms.where((r) => r.isDirectChat).toList();
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.person_add_outlined),
          title: const Text('添加联系人'),
          onTap: () => context.push('/add-contact'),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('好友申请'),
          onTap: () => context.push('/requests'),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: dmRooms.length,
            itemBuilder: (context, i) {
              final room = dmRooms[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(room.getLocalizedDisplayname().characters.first.toUpperCase()),
                ),
                title: Text(room.getLocalizedDisplayname()),
                onTap: () => context.push('/contact/${Uri.encodeComponent(room.directChatMatrixID ?? '')}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MePage extends ConsumerWidget {
  const _MePage({required this.client});
  final Client client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = client.userID ?? '';
    final domain = userId.contains(':') ? userId.split(':').last : userId;
    return ListView(
      children: [
        const SizedBox(height: 24),
        CircleAvatar(radius: 40, child: Text(domain.isNotEmpty ? domain[0].toUpperCase() : '?')),
        const SizedBox(height: 12),
        FutureBuilder<Profile?>(
          future: client.userID != null
              ? client.getProfileFromUserId(client.userID!)
              : Future.value(null),
          builder: (_, snap) => Text(
            snap.data?.displayName ?? '未设置昵称',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Text(domain, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('设置'),
          onTap: () => context.push('/settings'),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('退出登录'),
          onTap: () async {
            await ref.read(authStateNotifierProvider.notifier).logout();
          },
        ),
      ],
    );
  }
}
