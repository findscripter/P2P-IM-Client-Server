import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_provider.g.dart';

// Matrix client singleton.
// TODO Day 2: 切换到 MatrixSdkDatabase + path_provider 实现持久化。
// 当前内存模式仅用于开发期联调；登录态由 flutter_secure_storage 兜底，重启会重新 sync。
@riverpod
Client matrixClient(Ref ref) {
  return Client('PortalIM');
}

class AuthState {
  const AuthState({required this.isLoggedIn, this.userId, this.homeserver});
  final bool isLoggedIn;
  final String? userId;
  final String? homeserver;
}

@riverpod
class AuthStateNotifier extends _$AuthStateNotifier {
  static const _storage = FlutterSecureStorage();

  @override
  Future<AuthState> build() async {
    final client = ref.watch(matrixClientProvider);
    final token = await _storage.read(key: 'matrix_token');
    final homeserver = await _storage.read(key: 'matrix_homeserver');
    final userId = await _storage.read(key: 'matrix_user_id');

    if (token != null && homeserver != null && userId != null) {
      try {
        await client.checkHomeserver(Uri.parse(homeserver));
        await client.init(
          newToken: token,
          newUserID: userId,
          newHomeserver: Uri.parse(homeserver),
          newDeviceID: await _storage.read(key: 'matrix_device_id'),
          newDeviceName: 'PortalIM',
        );
        return AuthState(isLoggedIn: true, userId: userId, homeserver: homeserver);
      } catch (_) {
        await _storage.deleteAll();
      }
    }
    return const AuthState(isLoggedIn: false);
  }

  Future<void> login(String homeserverUrl, String password) async {
    final client = ref.read(matrixClientProvider);
    final uri = Uri.parse(
      homeserverUrl.startsWith('http') ? homeserverUrl : 'https://$homeserverUrl',
    );
    await client.checkHomeserver(uri);
    await client.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: '@owner:${uri.host}'),
      password: password,
    );
    await _storage.write(key: 'matrix_token', value: client.accessToken);
    await _storage.write(key: 'matrix_homeserver', value: uri.toString());
    await _storage.write(key: 'matrix_user_id', value: client.userID);
    await _storage.write(key: 'matrix_device_id', value: client.deviceID);
    state = AsyncData(AuthState(
      isLoggedIn: true,
      userId: client.userID,
      homeserver: uri.toString(),
    ));
  }

  Future<void> register(String homeserverUrl, String password, String displayName) async {
    final client = ref.read(matrixClientProvider);
    final uri = Uri.parse(
      homeserverUrl.startsWith('http') ? homeserverUrl : 'https://$homeserverUrl',
    );
    await client.checkHomeserver(uri);
    await client.register(username: 'owner', password: password);
    await client.setDisplayName(client.userID!, displayName);
    await _storage.write(key: 'matrix_token', value: client.accessToken);
    await _storage.write(key: 'matrix_homeserver', value: uri.toString());
    await _storage.write(key: 'matrix_user_id', value: client.userID);
    await _storage.write(key: 'matrix_device_id', value: client.deviceID);
    state = AsyncData(AuthState(
      isLoggedIn: true,
      userId: client.userID,
      homeserver: uri.toString(),
    ));
  }

  Future<void> logout() async {
    final client = ref.read(matrixClientProvider);
    await client.logout();
    await _storage.deleteAll();
    state = const AsyncData(AuthState(isLoggedIn: false));
  }
}
