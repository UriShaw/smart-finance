import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../../logic/state/settings_controller.dart';

/// Màn khóa PIN khi mở app (nếu bật trong Cài đặt).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pin = TextEditingController();
  String? _error;
  int _fails = 0;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(settingsProvider.notifier).verifyPin(_pin.text)) {
      widget.onUnlocked();
      return;
    }
    _fails++;
    _pin.clear();
    setState(() => _error = context.tr('pin_wrong'));
    // Chậm dần sau nhiều lần sai để chống dò PIN.
    if (_fails >= 5) {
      await Future<void>.delayed(Duration(seconds: _fails));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: GlassCard(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const SizedBox(height: AppSpacing.md),
                    Text(context.tr('enter_pin'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _pin,
                      autofocus: true,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(errorText: _error, counterText: ''),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submit,
                        child: Text(context.tr('unlock')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
