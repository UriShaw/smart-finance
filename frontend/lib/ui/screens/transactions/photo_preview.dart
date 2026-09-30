import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../../logic/state/app_providers.dart';

// autoDispose: link ký chỉ sống 1 giờ -> không giữ link cũ (đã hết hạn) suốt phiên app.
final _signedUrlProvider = FutureProvider.autoDispose.family<String?, String>((ref, path) async {
  final gw = ref.watch(remoteGatewayProvider);
  if (gw == null) return null;
  try {
    return await gw.signedPhotoUrl(path);
  } catch (_) {
    return null;
  }
});

/// Ưu tiên: ảnh mới chọn (bytes) -> file local tạm -> ảnh cloud (signed URL).
/// Offline + ảnh chỉ còn trên cloud -> hiển thị trạng thái, không crash.
class PhotoPreview extends ConsumerWidget {
  const PhotoPreview({
    super.key,
    this.bytes,
    this.localPath,
    this.remotePath,
    this.height = 180,
  });

  final Uint8List? bytes;
  final String? localPath;
  final String? remotePath;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget child;
    if (bytes != null) {
      child = Image.memory(bytes!, fit: BoxFit.cover);
    } else if (localPath != null && File(localPath!).existsSync()) {
      child = Image.file(File(localPath!), fit: BoxFit.cover);
    } else if (remotePath != null) {
      final url = ref.watch(_signedUrlProvider(remotePath!));
      child = url.when(
        data: (u) => u == null
            ? _placeholder(context, Icons.cloud_outlined, context.tr('photo_on_cloud'))
            : Image.network(
                u,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _placeholder(context, Icons.cloud_off_outlined, context.tr('photo_on_cloud')),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            _placeholder(context, Icons.cloud_off_outlined, context.tr('photo_on_cloud')),
      );
    } else {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(height: height, width: double.infinity, child: child),
    );
  }

  Widget _placeholder(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: scheme.outline),
          const SizedBox(height: 6),
          Text(text, style: TextStyle(color: scheme.outline)),
        ],
      ),
    );
  }
}
