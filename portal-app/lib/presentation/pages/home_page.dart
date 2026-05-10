import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../widgets/portal_avatar.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/app_theme.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _tab = 0;
  StreamSubscription<SyncUpdate>? _syncSub;

  @override
  void initState() {
    super.initState();
    // 订阅 client.onSync,任何 /sync 周期触发就重建,
    // 让会话列表的 lastEvent / notificationCount / 新房间 实时更新。
    final client = ref.read(matrixClientProvider);
    _syncSub = client.onSync.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(matrixClientProvider);
    final t = context.tk;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: t.accent.withValues(alpha: 0.4)),
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.message_square,
                  size: 12, color: t.accent),
            ),
            const SizedBox(width: 8),
            Text('Portal IM',
                style:
                    AppTheme.mono(size: 15, weight: FontWeight.w700, color: t.text)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.search, size: 18, color: t.text),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: Icon(LucideIcons.settings, size: 18, color: t.text),
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: switch (_tab) {
        0 => _ChatList(client: client),
        1 => _ContactList(client: client),
        _ => _MePage(client: client),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(LucideIcons.message_square, size: 18),
            selectedIcon: Icon(LucideIcons.message_square, size: 18),
            label: '消息',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.users, size: 18),
            selectedIcon: Icon(LucideIcons.users, size: 18),
            label: '联系人',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.user, size: 18),
            selectedIcon: Icon(LucideIcons.user, size: 18),
            label: '我',
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: () => context.push('/add-contact'),
              child: const Icon(LucideIcons.plus, size: 22),
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
    final t = context.tk;

    if (rooms.isEmpty) {
      return _Empty(
        icon: LucideIcons.message_square_dashed,
        title: '暂无会话',
        subtitle: '点击 + 添加联系人开始聊天',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final room = rooms[i];
        return _ChatTile(room: room, t: t);
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.room, required this.t});
  final Room room;
  final PortalTokens t;

  @override
  Widget build(BuildContext context) {
    final isDm = room.isDirectChat;
    final name = room.getLocalizedDisplayname();
    final lastEvent = room.lastEvent;
    final mxid = room.directChatMatrixID ?? '';
    final unread = room.notificationCount;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => isDm
            ? context.push('/chat/${Uri.encodeComponent(room.id)}')
            : context.push('/group/${Uri.encodeComponent(room.id)}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PortalAvatar(seed: name, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.sans(
                                  size: 15,
                                  weight: FontWeight.w600,
                                  color: t.text)),
                        ),
                        if (lastEvent != null)
                          Text(
                              _formatTime(
                                  lastEvent.originServerTs.millisecondsSinceEpoch),
                              style: AppTheme.mono(
                                  size: 11, color: t.textMute)),
                      ],
                    ),
                    if (isDm && mxid.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(mxid,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.mono(
                                size: 11, color: t.accentCool)),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastEvent?.body ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.sans(
                                size: 13, color: t.textMute),
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: t.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('$unread',
                                style: AppTheme.mono(
                                    size: 10,
                                    color: Colors.black,
                                    weight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) return DateFormat('HH:mm').format(dt);
    if (now.difference(dt).inDays == 1) return '昨天';
    if (now.difference(dt).inDays < 7) return DateFormat('EEE', 'zh').format(dt);
    return DateFormat('MM/dd').format(dt);
  }
}

Future<void> _showCreateGroupDialog(
    BuildContext context, Client client) async {
  final nameCtrl = TextEditingController();
  final inviteCtrl = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('创建群组'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: '群名称'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: inviteCtrl,
            decoration: const InputDecoration(
              labelText: '邀请成员（可选）',
              hintText: '@owner:example.com，多个用逗号分隔',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('创建'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;
  final name = nameCtrl.text.trim();
  if (name.isEmpty) return;

  final invites = inviteCtrl.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.startsWith('@'))
      .toList();

  try {
    final roomId = await client.createRoom(
      displayName: name,
      invite: invites,
      preset: CreateRoomPreset.privateChat,
      isDirect: false,
    );
    if (context.mounted) context.push('/group/${Uri.encodeComponent(roomId)}');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }
}

class _ContactList extends ConsumerWidget {
  const _ContactList({required this.client});
  final Client client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tk;
    final dmRooms = client.rooms.where((r) => r.isDirectChat).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _ActionTile(
          icon: LucideIcons.user_plus,
          label: '添加联系人',
          subtitle: '通过域名',
          onTap: () => context.push('/add-contact'),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: LucideIcons.users,
          label: '创建群组',
          subtitle: '邀请联系人',
          onTap: () => _showCreateGroupDialog(context, client),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: LucideIcons.bell_dot,
          label: '好友/群邀请',
          subtitle: 'Pending',
          onTap: () => context.push('/requests'),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '联系人 (${dmRooms.length})',
            style: AppTheme.mono(
                size: 11,
                color: t.textMute,
                weight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        ...dmRooms.map((room) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ChatTile(room: room, t: t),
            )),
      ],
    );
  }
}

class _MePage extends ConsumerWidget {
  const _MePage({required this.client});
  final Client client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tk;
    final userId = client.userID ?? '';
    final domain = userId.contains(':') ? userId.split(':').last : userId;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.border),
          ),
          child: Column(
            children: [
              PortalAvatar(seed: domain, size: 64),
              const SizedBox(height: 12),
              FutureBuilder<Profile?>(
                future: client.userID != null
                    ? client.getProfileFromUserId(client.userID!)
                    : Future.value(null),
                builder: (_, snap) => Text(
                  snap.data?.displayName ?? '未设置昵称',
                  style: AppTheme.sans(
                      size: 18, weight: FontWeight.w600, color: t.text),
                ),
              ),
              const SizedBox(height: 4),
              PortalMxid(userId, size: 12),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ActionTile(
          icon: LucideIcons.settings,
          label: '设置',
          onTap: () => context.push('/settings'),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: LucideIcons.log_out,
          label: '退出登录',
          danger: true,
          onTap: () async {
            await ref.read(authStateNotifierProvider.notifier).logout();
          },
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final color = danger ? t.danger : t.text;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: AppTheme.sans(
                        size: 14, weight: FontWeight.w500, color: color)),
              ),
              if (subtitle != null) ...[
                Text(subtitle!,
                    style: AppTheme.mono(size: 11, color: t.textMute)),
                const SizedBox(width: 6),
              ],
              Icon(LucideIcons.chevron_right, size: 16, color: t.textMute),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: t.textMute),
          const SizedBox(height: 12),
          Text(title,
              style: AppTheme.sans(
                  size: 14, color: t.text, weight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(subtitle, style: AppTheme.sans(size: 12, color: t.textMute)),
        ],
      ),
    );
  }
}
