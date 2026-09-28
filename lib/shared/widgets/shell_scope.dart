import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import 'liquid.dart';

/// Cho các tab biết có menu bên (drawer) hay không và cách mở nó.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.openMenu, required super.child});

  /// null = màn rộng (đã có thanh bên), không cần nút menu.
  final VoidCallback? openMenu;

  static VoidCallback? menuOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()?.openMenu;

  @override
  bool updateShouldNotify(ShellScope oldWidget) => oldWidget.openMenu != openMenu;
}

/// Nút kính tròn mở menu chức năng bên cạnh.
class ShellMenuButton extends StatelessWidget {
  const ShellMenuButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  /// Trả về nút menu nếu đang ở màn điện thoại, ngược lại null (AppBar tự xử lý).
  static Widget? maybe(BuildContext context) {
    final open = ShellScope.menuOf(context);
    if (open == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Center(child: ShellMenuButton(onPressed: open)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassCircleButton(
      icon: Icons.menu_rounded,
      tooltip: context.tr('menu'),
      size: 42,
      onPressed: onPressed,
    );
  }
}
