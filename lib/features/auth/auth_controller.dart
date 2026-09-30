import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/config/env.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../core/security/app_logger.dart';
import '../../data/repositories/local_data_claimer.dart';
import '../../shared/providers/core_providers.dart';
import '../settings/settings_controller.dart';
import 'account_vault.dart';
import 'desktop_oauth.dart';
import 'native_google_sign_in.dart';

enum SessionKind { localOnly, cloud, signedOut }

class SessionState {
  const SessionState({
    required this.kind,
    required this.userId,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.busy = false,
    this.error,
  });

  const SessionState.local() : this(kind: SessionKind.localOnly, userId: AppConstants.localUserId);

  const SessionState.signedOut()
      : this(kind: SessionKind.signedOut, userId: AppConstants.localUserId);

  factory SessionState.fromUser(sb.User u) {
    final meta = u.userMetadata ?? const <String, dynamic>{};
    return SessionState(
      kind: SessionKind.cloud,
      userId: u.id,
      email: u.email,
      displayName: (meta['full_name'] ?? meta['name']) as String?,
      avatarUrl: (meta['avatar_url'] ?? meta['picture']) as String?,
    );
  }

  final SessionKind kind;
  final String userId;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final bool busy;
  final AppErrorType? error;

  bool get isCloud => kind == SessionKind.cloud;
  bool get needsLogin => kind == SessionKind.signedOut;

  SessionState copyWith({bool? busy, AppErrorType? error, bool clearError = false}) => SessionState(
        kind: kind,
        userId: userId,
        email: email,
        displayName: displayName,
        avatarUrl: avatarUrl,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Google Account -> Supabase Auth -> Supabase user id (spec K).
/// Xử lý: first login, session sẵn có, logout, session hết hạn/bị thu hồi,
/// lỗi auth, lỗi mạng, tạo/cập nhật profile.
class AuthController extends Notifier<SessionState> {
  StreamSubscription<sb.AuthState>? _sub;

  /// Đang đổi mật khẩu bằng mã (verifyOTP cũng phát passwordRecovery) -> không mở hộp thoại.
  bool _resettingWithCode = false;

  /// Đang ở màn đăng nhập để THÊM tài khoản: phiên cũ vẫn còn trong client và tự làm mới
  /// ngầm -> bỏ qua sự kiện của nó (chỉ cập nhật token vào kho) cho tới khi đăng nhập xong.
  String? _pickingFrom;

  /// Đang chuyển tài khoản: bỏ qua signedOut tạm thời nếu token cũ hỏng.
  bool _switching = false;

  AccountVault get _vault => ref.read(accountVaultProvider);

  /// Ghi phiên vào kho tài khoản (refresh token đổi sau mỗi lần làm mới).
  Future<void> _remember(sb.Session? session) async {
    final u = session?.user;
    final token = session?.refreshToken;
    if (u == null || token == null || token.isEmpty) return;
    final meta = u.userMetadata ?? const <String, dynamic>{};
    await _vault.save(SavedAccount(
      userId: u.id,
      refreshToken: token,
      email: u.email,
      name: (meta['full_name'] ?? meta['name']) as String?,
      avatarUrl: (meta['avatar_url'] ?? meta['picture']) as String?,
      lastUsed: DateTime.now(),
    ));
    ref.invalidate(savedAccountsProvider);
  }

  sb.SupabaseClient? get _client => Env.cloudReady ? sb.Supabase.instance.client : null;

  @override
  SessionState build() {
    ref.onDispose(() => _sub?.cancel());
    final client = _client;
    final offline = ref.read(settingsProvider).offlineChosen;
    if (client == null) return const SessionState.local();

    _sub = client.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case sb.AuthChangeEvent.signedIn:
        case sb.AuthChangeEvent.tokenRefreshed:
        case sb.AuthChangeEvent.userUpdated:
        case sb.AuthChangeEvent.initialSession:
        case sb.AuthChangeEvent.passwordRecovery:
          unawaited(_remember(data.session));
          final u = data.session?.user;
          // Đang thêm tài khoản: chỉ nhận khi thật sự đăng nhập (không phải làm mới phiên cũ).
          if (_pickingFrom != null) {
            if (data.event != sb.AuthChangeEvent.signedIn &&
                data.event != sb.AuthChangeEvent.passwordRecovery) {
              break;
            }
            _pickingFrom = null;
          }
          if (u != null) {
            final wasCloud = state.isCloud && state.userId == u.id;
            state = SessionState.fromUser(u);
            if (!wasCloud) unawaited(_afterSignIn(u));
          }
          // Bấm link "quên mật khẩu" trong email -> app mở hộp đặt mật khẩu mới.
          if (data.event == sb.AuthChangeEvent.passwordRecovery && !_resettingWithCode) {
            ref.read(passwordRecoveryProvider.notifier).state = true;
          }
          break;
        case sb.AuthChangeEvent.signedOut:
          if (_switching) break;
          state = ref.read(settingsProvider).offlineChosen
              ? const SessionState.local()
              : const SessionState.signedOut();
          break;
        default:
          break;
      }
    }, onError: (Object e) {
      AppLogger.e('auth', 'auth stream error', e);
      state = state.copyWith(error: AppError.from(e).type);
    });

    final user = client.auth.currentUser;
    if (user != null) {
      unawaited(Future(() => _remember(client.auth.currentSession)));
      unawaited(Future(() => _afterSignIn(user)));
      return SessionState.fromUser(user);
    }
    return offline ? const SessionState.local() : const SessionState.signedOut();
  }

  Future<void> _afterSignIn(sb.User u) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final events = ref.read(dataEventsProvider);
      await LocalDataClaimer(db, events).claim(u.id);
    } catch (e) {
      AppLogger.e('auth', 'claim local data failed', e);
    }
    try {
      final meta = u.userMetadata ?? const <String, dynamic>{};
      await _client?.from('profiles').upsert({
        'id': u.id,
        'display_name': meta['full_name'] ?? meta['name'],
        'avatar_url': meta['avatar_url'] ?? meta['picture'],
      }, onConflict: 'id');
    } catch (e) {
      // Offline hoặc profile do trigger tạo - không chặn đăng nhập.
      AppLogger.e('auth', 'profile upsert skipped', e);
    }
  }

  Future<void> signInWithGoogle() async {
    final client = _client;
    if (client == null) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await DesktopOAuth.signInWithGoogle(client);
      } else if (await _nativeGoogle(client) case final done?) {
        if (!done) {
          state = state.copyWith(busy: false); // người dùng đóng bảng chọn
          return;
        }
      } else {
        await client.auth.signInWithOAuth(
          sb.OAuthProvider.google,
          redirectTo: Env.mobileRedirect,
          // Luôn hiện bảng chọn tài khoản Google (dùng nhiều tài khoản).
          queryParams: const {'prompt': 'select_account'},
        );
      }
      final u = client.auth.currentUser;
      // Đang thêm tài khoản thì currentUser vẫn là tài khoản cũ -> chờ sự kiện signedIn.
      if (u != null && u.id != _pickingFrom) {
        _pickingFrom = null;
        await ref.read(settingsProvider.notifier).setOfflineChosen(false);
        state = SessionState.fromUser(u);
        await _afterSignIn(u);
      } else {
        // Mobile: session đến qua deep link -> onAuthStateChange xử lý.
        state = state.copyWith(busy: false);
      }
    } catch (e) {
      AppLogger.e('auth', 'google sign-in failed', e);
      state = state.copyWith(busy: false, error: AppError.from(e).type);
    }
  }

  /// Android: bảng chọn tài khoản gốc. null = không dùng được -> đăng nhập qua trình duyệt.
  Future<bool?> _nativeGoogle(sb.SupabaseClient client) async {
    if (!NativeGoogleSignIn.supported) return null;
    try {
      return await NativeGoogleSignIn.signIn(client);
    } catch (e) {
      AppLogger.e('auth', 'native google sign-in unavailable, using browser', e);
      return null;
    }
  }

  Future<void> _signedIn(sb.User? u) async {
    if (u == null) return;
    await ref.read(settingsProvider.notifier).setOfflineChosen(false);
    state = SessionState.fromUser(u);
    await _afterSignIn(u);
  }

  /// Đăng nhập bằng email + mật khẩu. Ném lỗi (AuthException / mạng) để màn hình báo.
  Future<void> signInWithEmail(String email, String password) async {
    final client = _client;
    if (client == null) throw const AppError(AppErrorType.provider, detail: 'no_server');
    final res = await client.auth
        .signInWithPassword(email: email.trim(), password: password)
        .timeout(const Duration(seconds: 25));
    await _signedIn(res.user ?? client.auth.currentUser);
  }

  /// Đăng ký. Trả về true nếu cần xác nhận email trước khi đăng nhập.
  Future<bool> signUpWithEmail(String name, String email, String password) async {
    final client = _client;
    if (client == null) throw const AppError(AppErrorType.provider, detail: 'no_server');
    final res = await client.auth
        .signUp(
          email: email.trim(),
          password: password,
          data: name.trim().isEmpty ? null : {'full_name': name.trim()},
        )
        .timeout(const Duration(seconds: 25));
    if (res.session == null) return true;
    await _signedIn(res.user);
    return false;
  }

  /// Gửi mã khôi phục mật khẩu (6 số) về email.
  Future<void> sendPasswordReset(String email) async {
    final client = _client;
    if (client == null) throw const AppError(AppErrorType.provider, detail: 'no_server');
    // Gói Free của Supabase không sửa được mẫu email -> email chứa LINK (không có mã).
    // Link mở app qua deep link (Android) rồi phát passwordRecovery.
    final mobile = Platform.isAndroid || Platform.isIOS;
    await client.auth
        .resetPasswordForEmail(email.trim(), redirectTo: mobile ? Env.mobileRedirect : null)
        .timeout(const Duration(seconds: 25));
  }

  /// Đặt mật khẩu mới khi đã vào bằng link khôi phục.
  Future<void> updatePassword(String newPassword) async {
    final client = _client;
    if (client == null) throw const AppError(AppErrorType.provider, detail: 'no_server');
    await client.auth
        .updateUser(sb.UserAttributes(password: newPassword))
        .timeout(const Duration(seconds: 25));
  }

  /// Nhập mã trong email + mật khẩu mới -> đổi mật khẩu và đăng nhập luôn.
  Future<void> resetPasswordWithCode(String email, String code, String newPassword) async {
    final client = _client;
    if (client == null) throw const AppError(AppErrorType.provider, detail: 'no_server');
    // Sự kiện passwordRecovery tới bất đồng bộ -> giữ cờ suốt cả quá trình.
    _resettingWithCode = true;
    try {
      final res = await client.auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: sb.OtpType.recovery,
      );
      await client.auth.updateUser(sb.UserAttributes(password: newPassword));
      await _signedIn(res.user ?? client.auth.currentUser);
    } finally {
      _resettingWithCode = false;
    }
  }

  /// Chuyển sang tài khoản đã lưu trên máy (không cần đăng nhập lại).
  /// Token hết hạn / bị thu hồi -> bỏ tài khoản đó khỏi danh sách, quay về tài khoản cũ,
  /// rồi ném lỗi để màn hình báo "cần đăng nhập lại".
  Future<void> switchTo(String userId) async {
    final client = _client;
    if (client == null) return;
    if (state.isCloud && state.userId == userId && _pickingFrom == null) return;
    final target = await _vault.find(userId);
    if (target == null) throw const AppError(AppErrorType.auth, detail: 'account_expired');
    final previous = client.auth.currentSession;
    await _remember(previous);
    state = state.copyWith(busy: true, clearError: true);
    _switching = true;
    try {
      final res = await client.auth.setSession(target.refreshToken);
      _pickingFrom = null;
      await _remember(res.session);
      final u = res.user ?? client.auth.currentUser;
      if (u != null) {
        await ref.read(settingsProvider.notifier).setOfflineChosen(false);
        state = SessionState.fromUser(u);
        await _afterSignIn(u);
      }
    } catch (e) {
      AppLogger.e('auth', 'switch account failed', e);
      await _vault.remove(userId);
      ref.invalidate(savedAccountsProvider);
      final back = previous?.refreshToken;
      var restored = false;
      if (back != null && previous?.user.id != userId) {
        try {
          final r = await client.auth.setSession(back);
          await _remember(r.session);
          final u = r.user ?? client.auth.currentUser;
          if (u != null) {
            state = SessionState.fromUser(u);
            restored = true;
          }
        } catch (_) {}
      }
      if (!restored) state = const SessionState.signedOut();
      throw const AppError(AppErrorType.auth, detail: 'account_expired');
    } finally {
      _switching = false;
    }
  }

  /// Mở màn đăng nhập để thêm tài khoản khác, KHÔNG đăng xuất tài khoản hiện tại
  /// (vẫn nằm trong danh sách để chuyển lại).
  Future<void> addAccount() async {
    if (_client == null || !state.isCloud) return;
    await _remember(_client?.auth.currentSession);
    _pickingFrom = state.userId;
    state = const SessionState.signedOut();
  }

  /// Bỏ tài khoản khỏi danh sách trên máy (không ảnh hưởng dữ liệu trên cloud).
  Future<void> forgetAccount(String userId) async {
    await _vault.remove(userId);
    ref.invalidate(savedAccountsProvider);
  }

  Future<void> continueOffline() async {
    await ref.read(settingsProvider.notifier).setOfflineChosen(true);
    state = const SessionState.local();
  }

  /// Đăng xuất: dữ liệu local + outbox vẫn giữ (gắn với user id) để không mất
  /// thay đổi chưa đồng bộ; đăng nhập lại cùng tài khoản sẽ đẩy tiếp.
  Future<void> signOut() async {
    // Đăng xuất = bỏ tài khoản này khỏi danh sách chuyển nhanh (token bị thu hồi trên server).
    if (state.isCloud) await forgetAccount(state.userId);
    _pickingFrom = null;
    try {
      await _client?.auth.signOut();
    } catch (e) {
      AppLogger.e('auth', 'sign out remote failed', e);
    }
    await ref.read(settingsProvider.notifier).setOfflineChosen(false);
    state = _client == null ? const SessionState.local() : const SessionState.signedOut();
  }

  void showLogin() {
    if (_client == null) return;
    state = const SessionState.signedOut();
  }
}

final accountVaultProvider = Provider<AccountVault>((ref) => AccountVault());

/// Các tài khoản đã đăng nhập trên máy (mới dùng gần nhất trước).
final savedAccountsProvider = FutureProvider<List<SavedAccount>>((ref) {
  ref.watch(sessionProvider.select((s) => s.userId));
  return ref.watch(accountVaultProvider).list();
});

/// true khi người dùng vừa mở link khôi phục mật khẩu (RootGate hiện hộp đặt mật khẩu mới).
final passwordRecoveryProvider = StateProvider<bool>((ref) => false);

final sessionProvider = NotifierProvider<AuthController, SessionState>(AuthController.new);

final currentUserIdProvider =
    Provider<String>((ref) => ref.watch(sessionProvider.select((s) => s.userId)));

final isCloudUserProvider =
    Provider<bool>((ref) => ref.watch(sessionProvider.select((s) => s.isCloud)));
