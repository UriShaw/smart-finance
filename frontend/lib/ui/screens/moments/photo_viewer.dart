import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../i18n/app_localizations.dart';
import '../../../logic/domain/entities/finance_transaction.dart';
import '../../../logic/state/app_providers.dart';
import '../../widgets/common.dart';

/// Đọc ảnh của giao dịch: ưu tiên file trên máy, không có thì tải từ cloud (signed URL).
Future<Uint8List?> loadPhotoBytes(WidgetRef ref, FinanceTransaction tx) async {
  final local = tx.localImagePath;
  if (local != null) {
    final f = File(local);
    if (await f.exists()) return f.readAsBytes();
  }
  final remote = tx.remoteImagePath;
  final gw = ref.read(remoteGatewayProvider);
  if (remote == null || gw == null) return null;
  final url = await gw.signedPhotoUrl(remote);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final b = BytesBuilder(copy: false);
    await for (final chunk in res) {
      b.add(chunk);
    }
    return b.takeBytes();
  } finally {
    client.close(force: true);
  }
}

String _fileName(FinanceTransaction tx) =>
    'SmartFinance_${DateFormat('yyyyMMdd_HHmmss').format(tx.date)}.jpg';

const _channel = MethodChannel('smart_finance/bank');

/// Tải ảnh về máy: Android -> Thư viện ảnh (Pictures/SmartFinance); máy tính -> chọn nơi lưu.
Future<void> downloadPhoto(BuildContext context, WidgetRef ref, FinanceTransaction tx,
    {Uint8List? bytes}) async {
  try {
    final data = bytes ?? await loadPhotoBytes(ref, tx);
    if (data == null) {
      if (context.mounted) showSnack(context, context.tr('photo_on_cloud'));
      return;
    }
    String? where;
    if (Platform.isAndroid) {
      where = await _channel.invokeMethod<String>('saveImage', {
        'bytes': data,
        'name': _fileName(tx),
      });
    } else {
      final loc = await getSaveLocation(
        suggestedName: _fileName(tx),
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JPEG', extensions: ['jpg', 'jpeg']),
        ],
      );
      if (loc == null) return;
      await File(loc.path).writeAsBytes(data, flush: true);
      where = loc.path;
    }
    if (context.mounted) {
      showSnack(context, context.tr('photo_saved', {'p': where ?? ''}));
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Xem ảnh toàn màn hình: chụm/kéo để phóng to, nút tải về.
Future<void> showPhotoViewer(BuildContext context, FinanceTransaction tx) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (context, a1, a2) => _PhotoViewer(tx: tx),
    transitionsBuilder: (context, a, a2, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _PhotoViewer extends ConsumerStatefulWidget {
  const _PhotoViewer({required this.tx});
  final FinanceTransaction tx;

  @override
  ConsumerState<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<_PhotoViewer> {
  late final Future<Uint8List?> _bytes = loadPhotoBytes(ref, widget.tx);
  bool _saving = false;

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _bytes;
      if (!mounted) return;
      await downloadPhoto(context, ref, widget.tx, bytes: bytes);
    } catch (_) {
      // downloadPhoto đã báo lỗi.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final sub = [
      if ((tx.locationName ?? '').isNotEmpty) tx.locationName!,
      DateFormat('HH:mm · dd/MM/yyyy').format(tx.date),
    ].join(' · ');
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: FutureBuilder<Uint8List?>(
              future: _bytes,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }
                final data = snap.data;
                if (data == null) {
                  return Center(
                    child: Text(context.tr('photo_on_cloud'),
                        style: const TextStyle(color: Colors.white70)),
                  );
                }
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(child: Image.memory(data, fit: BoxFit.contain)),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: context.tr('close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tx.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  _saving
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        )
                      : IconButton(
                          tooltip: context.tr('photo_download'),
                          onPressed: _download,
                          icon: const Icon(Icons.download_rounded, color: Colors.white),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
