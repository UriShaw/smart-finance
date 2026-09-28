import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/common.dart';
import '../../domain/entities/finance_transaction.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/liquid.dart';
import '../settings/settings_controller.dart';
import '../transactions/photo_preview.dart';
import 'location_service.dart';

/// Cắt ảnh thành hình vuông ở giữa (giống Locket), tối đa 1440px.
Uint8List _cropSquare(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final oriented = img.bakeOrientation(decoded);
  final side = math.min(oriented.width, oriented.height);
  final size = math.min(side, 1440);
  final square = img.copyResizeCropSquare(oriented, size: size);
  return Uint8List.fromList(img.encodeJpg(square, quality: 88));
}

/// Chụp "khoảnh khắc" cho giao dịch (kiểu Locket): ảnh vuông + vị trí lúc chụp + lời nhắn.
/// Lưu vào máy ngay (offline được); có mạng thì bộ đồng bộ tự đẩy ảnh + vị trí lên cloud.
/// Trả về giao dịch đã cập nhật, hoặc null nếu người dùng huỷ.
Future<FinanceTransaction?> captureMoment(
  BuildContext context,
  WidgetRef ref,
  FinanceTransaction tx,
) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  // Lấy vị trí song song với lúc mở camera để khi chụp xong là có ngay.
  final locationFuture = LocationService.current();
  XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: mobile ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 2000,
    );
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
  if (file == null) return null;
  final raw = await file.readAsBytes();
  final square = await compute(_cropSquare, raw);
  if (!context.mounted) return null;

  final result = await showGlassSheet<_MomentDraft>(
    context: context,
    builder: (_) => _MomentPreview(tx: tx, bytes: square, location: locationFuture),
  );
  if (result == null) return null;
  if (result.retake) {
    if (!context.mounted) return null;
    return captureMoment(context, ref, tx);
  }

  final photos = ref.read(photoServiceProvider);
  final repo = ref.read(transactionRepoProvider);
  final oldLocal = tx.localImagePath;
  final local = await photos.saveCompressed(square);
  final caption = result.caption.trim();
  final note = caption.isEmpty
      ? tx.note
      : ((tx.note == null || tx.note!.trim().isEmpty) ? caption : '$caption\n${tx.note}');
  final fix = result.fix;
  final updated = await repo.save(tx.copyWith(
    localImagePath: local,
    remoteImagePath: null, // ảnh mới -> cần tải lên lại
    note: note,
    latitude: fix?.lat ?? tx.latitude,
    longitude: fix?.lng ?? tx.longitude,
    locationName: fix?.place ?? tx.locationName,
  ));
  if (oldLocal != null && oldLocal != local) await photos.deleteLocal(oldLocal);
  return updated;
}

class _MomentDraft {
  const _MomentDraft({this.caption = '', this.fix, this.retake = false});
  final String caption;
  final GeoFix? fix;
  final bool retake;
}

class _MomentPreview extends StatefulWidget {
  const _MomentPreview({required this.tx, required this.bytes, required this.location});
  final FinanceTransaction tx;
  final Uint8List bytes;
  final Future<GeoFix?> location;

  @override
  State<_MomentPreview> createState() => _MomentPreviewState();
}

class _MomentPreviewState extends State<_MomentPreview> {
  final _caption = TextEditingController();
  GeoFix? _fix;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    widget.location.then((f) {
      if (mounted) {
        setState(() {
          _fix = f;
          _locating = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('moment_title'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _caption,
                builder: (context, v, _) => MomentCard(
                  tx: widget.tx,
                  bytes: widget.bytes,
                  caption: v.text,
                  place: _locating ? null : (_fix?.place ?? ''),
                  locating: _locating,
                  time: DateTime.now(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _caption,
            maxLength: 40,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: context.tr('moment_caption_hint'),
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
          if (!_locating && _fix == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.tr('moment_no_location'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.hint, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(const _MomentDraft(retake: true)),
                  icon: const Icon(Icons.cameraswitch_rounded),
                  label: Text(context.tr('moment_retake')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _locating
                      ? null
                      : () => Navigator.of(context)
                          .pop(_MomentDraft(caption: _caption.text, fix: _fix)),
                  icon: _locating
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(context.tr(_locating ? 'moment_locating' : 'save')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Thẻ ảnh vuông kiểu Locket: ảnh bo góc lớn, vị trí ở trên, lời nhắn ở giữa dưới,
/// số tiền + giờ ở góc. Dùng cho cả xem trước và chi tiết giao dịch.
class MomentCard extends ConsumerWidget {
  const MomentCard({
    super.key,
    required this.tx,
    this.bytes,
    this.caption,
    this.place,
    this.locating = false,
    this.time,
    this.onRetake,
  });

  final FinanceTransaction tx;

  /// Ảnh vừa chụp (chưa lưu). null = dùng ảnh đã lưu của giao dịch.
  final Uint8List? bytes;
  final String? caption;

  /// null = dùng vị trí đã lưu của giao dịch.
  final String? place;
  final bool locating;
  final DateTime? time;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final income = tx.type == TxType.income;
    final amount = Money.format(income ? tx.amountMinor : -tx.amountMinor, currency,
        locale: context.l10n.intlLocale, signed: true);
    final where = place ?? tx.locationName ?? '';
    final firstNoteLine = (tx.note ?? '').split('\n').first.trim();
    final text = caption ?? (bytes == null && tx.hasPhoto ? firstNoteLine : '');
    final when = DateFormat('HH:mm · dd/MM').format(time ?? tx.date);

    Widget chip(Widget child, {Color? color}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (color ?? Colors.black).withValues(alpha: color == null ? 0.38 : 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: DefaultTextStyle.merge(
            style:
                const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
            child: IconTheme.merge(
              data: const IconThemeData(color: Colors.white, size: 14),
              child: child,
            ),
          ),
        );

    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bytes != null)
                Image.memory(bytes!, fit: BoxFit.cover)
              else
                LayoutBuilder(
                  builder: (context, c) => PhotoPreview(
                    localPath: tx.localImagePath,
                    remotePath: tx.remoteImagePath,
                    height: c.maxHeight,
                  ),
                ),
              // Viền kính sáng.
              const IgnorePointer(
                child: CustomPaint(painter: GlassRimPainter(radius: 40, strength: 0.8)),
              ),
              // Vị trí lúc chụp.
              if (locating || where.isNotEmpty)
                Positioned(
                  left: 14,
                  top: 14,
                  right: 60,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: chip(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.place_rounded),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            locating ? context.tr('moment_locating') : where,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )),
                  ),
                ),
              if (onRetake != null)
                Positioned(
                  right: 12,
                  top: 10,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.38),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: context.tr('moment_retake'),
                      onPressed: onRetake,
                      icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              // Lời nhắn ở giữa phía dưới (giống Locket).
              if (text.isNotEmpty)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 58,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(text,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ),
              Positioned(
                left: 14,
                bottom: 14,
                child: chip(Text(amount), color: income ? AppColors.income : AppColors.expense),
              ),
              Positioned(right: 14, bottom: 14, child: chip(Text(when))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ô trống mời chụp khoảnh khắc (khi giao dịch chưa có ảnh).
class MomentPlaceholder extends StatelessWidget {
  const MomentPlaceholder({super.key, required this.onCapture});
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return AspectRatio(
      aspectRatio: 1.6,
      child: Material(
        color: dark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.lightBlue.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(32),
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onCapture,
          child: CustomPaint(
            painter: GlassRimPainter(radius: 32, dark: dark, strength: 0.8),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: AppColors.accentGradient),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 10),
                  Text(context.tr('moment_capture'),
                      style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(context.tr('moment_capture_sub'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
