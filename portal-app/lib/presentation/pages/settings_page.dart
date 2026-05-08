import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixClientProvider);
    final userId = client.userID ?? '';
    final domain = userId.contains(':') ? userId.split(':').last : '';

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('账号'),
            subtitle: Text(userId),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('域名'),
            subtitle: Text(domain),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: const Text('Portal IM v2.0.0 (Matrix)'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('退出登录'),
            textColor: Theme.of(context).colorScheme.error,
            iconColor: Theme.of(context).colorScheme.error,
            onTap: () => ref.read(authStateNotifierProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }
}
