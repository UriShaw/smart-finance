import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/sync/sync_engine.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/sign_out_dialog.dart';
import '../../features/bank/bank_channel.dart';
import '../../features/bank/bank_controller.dart';
import '../../features/bank/bank_settings_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/categories/category_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/map/map_screen.dart';
import '../../features/moments/location_service.dart';
import '../../features/settings/lock_screen.dart';
import '../../features/settings/settings_controller.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/statistics/statistics_screen.dart';
import '../../features/transactions/history_screen.dart';
import '../providers/app_providers.dart';
import 'app_logo.dart';
import 'common.dart';
import 'glass.dart';
import 'liquid.dart';
import 'shell_scope.dart';
import 'sync_badge.dart';

/// Cổng vào: khóa PIN -> đăng nhập -> app.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  bool _unlocked = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () {
      // Quay lại app: đồng bộ.
      ref.read(syncEngineProvider).syncNow();
      // Giao dịch từ thông báo ngân hàng nhận được khi app ở nền.
      ref.read(bankImporterProvider)?.importPending();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinEnabled = ref.watch(settingsProvider.select((s) => s.pinEnabled));
    final needsLogin = ref.watch(sessionProvider.select((s) => s.needsLogin));
    ref.listen<bool>(passwordRecoveryProvider, (_, open) {
      if (!open) return;
      ref.read(passwordRecoveryProvider.notifier).state = false;
      showDialog<void>(context: context, builder: (_) => const NewPasswordDialog());
    });
    if (pinEnabled && !_unlocked) {
      return LockScreen(onUnlocked: () => setState(() => _unlocked = true));
    }
    if (needsLogin) return const LoginScreen();
    return const AppShell();
  }
}

class _Tab {
  const _Tab(this.icon, this.selectedIcon, this.labelKey);
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
}

/// 5 tab: Trang chủ · Lịch sử · Lịch · Thống kê · Cài đặt.
const _tabs = [
  _Tab(Icons.home_outlined, Icons.home_rounded, 'tab_home'),
  _Tab(Icons.history_rounded, Icons.history_rounded, 'nav_history'),
  _Tab(Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'nav_calendar'),
  _Tab(Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'nav_stats'),
  _Tab(Icons.settings_outlined, Icons.settings_rounded, 'nav_settings'),
];

/// Khung app theo bố cục app cũ:
///  - Thanh trên: logo + tên app, chuông thông báo, ảnh đại diện; lời chào bên dưới.
///  - 5 trang vuốt ngang (PageView) + thanh điều hướng kính nổi (điện thoại)
///    hoặc thanh bên kính (máy tính/tablet).
///  - Nút menu kính mở "Chức năng mới" (bản đồ, danh mục, ngân hàng).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _pages = PageController();
  int _index = 0;
  bool? _lastCompact;

  @override
  void initState() {
    super.initState();
    // Điện thoại: xin quyền vị trí ngay khi vào app (ảnh + giao dịch tự lấy vị trí).
    if (Platform.isAndroid || Platform.isIOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) => LocationService.ensurePermission());
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();

  void _go(int i) {
    if (i == _index) return;
    final from = _index;
    setState(() => _index = i);
    if (!_pages.hasClients) return;
    if ((i - from).abs() > 1 || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(i,
          duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Khởi động: seed danh mục, bật sync engine.
    ref.listen<int>(bankLastImportProvider, (_, n) {
      if (n > 0 && mounted) showSnack(context, context.tr('bank_imported', {'n': n}));
    });
    ref.watch(bootstrapProvider);
    ref.watch(syncEngineProvider);
    ref.watch(bankAutoImportProvider);

    final items = [
      for (final t in _tabs)
        GlassNavItem(icon: t.icon, selectedIcon: t.selectedIcon, label: context.tr(t.labelKey)),
    ];

    final pageView = PageView(
      controller: _pages,
      onPageChanged: (i) {
        if (i != _index) setState(() => _index = i);
      },
      children: [
        _KeepAlive(child: HomeScreen(onSeeAll: () => _go(1))),
        const _KeepAlive(child: HistoryScreen()),
        const _KeepAlive(child: CalendarScreen(embedded: true)),
        const _KeepAlive(child: StatisticsScreen()),
        const _KeepAlive(child: SettingsScreen()),
      ],
    );

    return LayoutBuilder(builder: (context, c) {
      final compact = c.maxWidth < 600 || c.maxHeight < 520;
      if (_lastCompact != null && _lastCompact != compact) {
        // Đổi bố cục (thu/phóng cửa sổ) -> PageView mới, đưa về đúng trang đang chọn.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pages.hasClients) _pages.jumpToPage(_index);
        });
      }
      _lastCompact = compact;
      final drawer = _LiquidMenu(
        current: _index,
        onTab: (i) {
          _scaffoldKey.currentState?.closeDrawer();
          _go(i);
        },
      );
      final top = _TopBar(onMenu: _openMenu);

      if (compact) {
        return ShellScope(
          openMenu: _openMenu,
          child: Scaffold(
            key: _scaffoldKey,
            extendBody: true,
            drawer: drawer,
            drawerScrimColor: Colors.black.withValues(alpha: 0.22),
            drawerEdgeDragWidth: 24,
            body: Column(
              children: [
                SafeArea(bottom: false, child: top),
                Expanded(child: pageView),
              ],
            ),
            bottomNavigationBar: GlassNavBar(index: _index, onSelect: _go, items: items),
          ),
        );
      }

      final extended = c.maxWidth >= 1100;
      return ShellScope(
        openMenu: _openMenu,
        child: Scaffold(
          key: _scaffoldKey,
          drawer: drawer,
          drawerScrimColor: Colors.black.withValues(alpha: 0.22),
          body: SafeArea(
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: LiquidSidebar(
                    extended: extended,
                    index: _index,
                    onSelect: _go,
                    items: items,
                    header: Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 16),
                      child: extended
                          ? Row(
                              children: [
                                const SizedBox(width: 8),
                                const AppLogo(size: 36),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    context.tr('app_name'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const AppLogo(size: 36),
                    ),
                    footer: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GlassCircleButton(
                        icon: Icons.apps_rounded,
                        tooltip: context.tr('menu_features'),
                        onPressed: _openMenu,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      top,
                      Expanded(child: pageView),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// =====================================================================
// Thanh trên (giống app cũ) + lời chào
// =====================================================================

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onMenu});
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final sync = ref.watch(syncStatusProvider).valueOrNull ?? SyncSnapshot.initial;
    final dot = sync.phase == SyncPhase.error;

    final full = (session.displayName ?? '').trim();
    final name = full.isEmpty ? context.tr('greeting_you') : full.split(RegExp(r'\s+')).last;
    final email = session.email ?? '';
    final String? initial = full.isNotEmpty
        ? full.characters.first.toUpperCase()
        : (email.isNotEmpty ? email.characters.first.toUpperCase() : null);

    Future<void> onAvatar() async {
      if (session.isCloud) {
        await confirmSignOut(context, ref);
      } else if (Env.cloudReady) {
        ref.read(sessionProvider.notifier).showLogin();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassCircleButton(
                icon: Icons.menu_rounded,
                tooltip: context.tr('menu_features'),
                size: 42,
                onPressed: onMenu,
              ),
              const SizedBox(width: 12),
              const AppLogo(size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('app_name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: context.tr('notifications'),
                    onPressed: () => showGlassSheet<void>(
                        context: context, builder: (_) => const _NotificationsSheet()),
                    icon: Icon(Icons.notifications_outlined,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (dot)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.expense,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: session.isCloud ? context.tr('sign_out') : context.tr('auth_sign_in'),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: session.busy ? null : onAvatar,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: session.isCloud
                          ? AppColors.lightBlue
                          : AppColors.hint.withValues(alpha: 0.55),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: session.busy
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : (session.isCloud && initial != null
                            ? Text(initial,
                                style: const TextStyle(
                                    color: AppColors.primary, fontWeight: FontWeight.w800))
                            : const Icon(Icons.person_rounded, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('greeting', {'name': name}),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 22),
          ),
          Text(
            context.tr('greeting_sub'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Bảng "Thông báo": trạng thái đồng bộ, ghi tự động ngân hàng.
class _NotificationsSheet extends ConsumerWidget {
  const _NotificationsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sync = ref.watch(syncStatusProvider).valueOrNull ?? SyncSnapshot.initial;
    final bank = BankChannel.supported ? ref.watch(bankControllerProvider).valueOrNull : null;

    void open(Widget w) {
      final nav = Navigator.of(context);
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => w));
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Text(context.tr('notifications'),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        GlassSection(
          children: [
            LiquidTile(
              icon: Icons.cloud_sync_rounded,
              iconColor: LiquidColors.blue,
              title: context.tr('sync_title'),
              subtitle: sync.pendingCount > 0
                  ? context.tr('pending_changes', {'n': sync.pendingCount})
                  : context.tr('last_sync', {
                      'd': sync.lastSyncAt == null
                          ? context.tr('never')
                          : formatDate(context, sync.lastSyncAt!.toLocal(), withTime: true),
                    }),
              trailing: const SyncBadge(compact: true),
            ),
            if (bank != null)
              LiquidTile(
                icon: Icons.graphic_eq_rounded,
                iconColor: bank.active ? LiquidColors.green : LiquidColors.orange,
                title: context.tr('bank_title'),
                subtitle: bank.active
                    ? context.tr('monitoring_on_sub')
                    : context.tr('bank_permission_missing'),
                onTap: () => open(const BankSettingsScreen()),
              ),
          ],
        ),
        if (sync.phase != SyncPhase.error && (bank == null || bank.active))
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(context.tr('no_notifications'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

// =====================================================================
// Menu kính bên trái: 4 trang chính + chức năng mới
// =====================================================================

class _LiquidMenu extends ConsumerWidget {
  const _LiquidMenu({required this.current, required this.onTab});

  final int current;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final width = math.min(330.0, MediaQuery.sizeOf(context).width * 0.86);

    void open(Widget screen) {
      final nav = Navigator.of(context);
      Scaffold.of(context).closeDrawer();
      nav.push(MaterialPageRoute(builder: (_) => screen));
    }

    Widget tab(int i, Color color) => LiquidTile(
          icon: _tabs[i].selectedIcon,
          iconColor: color,
          title: context.tr(_tabs[i].labelKey),
          selected: current == i,
          showChevron: false,
          trailing: current == i
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: AppColors.accentGradient),
                  ),
                )
              : null,
          onTap: () => onTab(i),
        );

    return Drawer(
      width: width,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
          child: GlassCard(
            blur: true,
            radius: 32,
            opacity: 1.15,
            padding: EdgeInsets.zero,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 6),
                  child: Row(
                    children: [
                      const AppLogo(size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('app_name'),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18),
                            ),
                            Text(
                              session.displayName ?? session.email ?? context.tr('offline_mode'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 2, 18, 0),
                  child: Align(alignment: Alignment.centerLeft, child: SyncBadge()),
                ),
                _MenuHeader(context.tr('main_sections')),
                tab(0, LiquidColors.blue),
                tab(1, LiquidColors.indigo),
                tab(2, LiquidColors.orange),
                tab(3, LiquidColors.purple),
                tab(4, LiquidColors.gray),
                _MenuHeader(context.tr('new_features')),
                LiquidTile(
                  icon: Icons.map_rounded,
                  iconColor: LiquidColors.teal,
                  title: context.tr('nav_map'),
                  onTap: () => open(const MapScreen()),
                ),
                LiquidTile(
                  icon: Icons.category_rounded,
                  iconColor: LiquidColors.pink,
                  title: context.tr('nav_categories'),
                  onTap: () => open(const CategoryScreen()),
                ),
                if (BankChannel.supported)
                  LiquidTile(
                    icon: Icons.graphic_eq_rounded,
                    iconColor: LiquidColors.cyan,
                    title: context.tr('bank_title'),
                    onTap: () => open(const BankSettingsScreen()),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Text(
                    '${context.tr('app_name')} ${Env.appVersion}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
