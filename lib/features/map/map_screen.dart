import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/common.dart';
import '../../domain/entities/finance_transaction.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/glass.dart';
import '../moments/location_service.dart';
import '../transactions/photo_preview.dart';
import '../transactions/transaction_detail_sheet.dart';
import '../transactions/transaction_tile.dart';
import 'map_cluster.dart';
import 'map_markers.dart';
import 'map_service.dart';

final _locatedTxProvider = FutureProvider<List<FinanceTransaction>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionRepoProvider).withLocation();
});

/// Bản đồ kiểu Google Photos: ảnh khoảnh khắc hiện ngay trên bản đồ, điểm gần nhau
/// gộp thành nhóm có số đếm; bảng "Trong khu vực này" liệt kê theo địa chỉ những gì
/// đang nằm trong vùng nhìn thấy.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapViewController();
  final _sheet = DraggableScrollableController();
  MapViewport? _view;

  /// Nhóm vừa bấm khi đã phóng to hết cỡ (các điểm trùng nhau).
  List<FinanceTransaction>? _focus;

  /// PNG biểu tượng theo khoá (ảnh + số lượng), dùng lại khi phóng to/thu nhỏ.
  final _icons = <String, Uint8List>{};
  final _rendering = <String>{};

  /// Tên địa điểm tra từ toạ độ cho giao dịch chưa có tên (theo ô ~100 m).
  final _places = <String, String>{};
  final _geoQueue = <String, MapPoint>{};
  bool _geocoding = false;

  static bool get _canGeocode => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  static MapPoint _pt(FinanceTransaction t) => MapPoint(t.latitude!, t.longitude!);

  static String _cell(double lat, double lng) =>
      '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';

  void _open(FinanceTransaction t, Map<String, TxCategory> cats) =>
      showTransactionDetail(context, t, cats[t.categoryId]);

  // ------------------------------------------------------------------ biểu tượng

  Future<ImageProvider?> _photo(FinanceTransaction t) async {
    final local = t.localImagePath;
    if (local != null && File(local).existsSync()) return FileImage(File(local));
    final remote = t.remoteImagePath;
    final gw = ref.read(remoteGatewayProvider);
    if (remote != null && gw != null) {
      try {
        return NetworkImage(await gw.signedPhotoUrl(remote));
      } catch (_) {}
    }
    return null;
  }

  Future<void> _render(String key, FinanceTransaction? photoTx, Color color, int count) async {
    _rendering.add(key);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    try {
      final provider = photoTx == null ? null : await _photo(photoTx);
      final img = provider == null
          ? null
          : await MarkerIcons.load(provider, (MarkerIcons.size * dpr).round());
      final bytes = await MarkerIcons.render(photo: img, color: color, count: count, dpr: dpr);
      img?.dispose();
      if (mounted) setState(() => _icons[key] = bytes);
    } catch (_) {
      // Giữ ghim mặc định.
    } finally {
      _rendering.remove(key);
    }
  }

  List<MapMarkerData> _markers(
    List<FinanceTransaction> located,
    Map<String, TxCategory> cats,
  ) {
    final zoom = _view?.zoom ?? 12;
    final clusters = MapClusterer.cluster(located, _pt, zoom);
    return [
      for (final c in clusters) _marker(c, zoom, cats),
    ];
  }

  MapMarkerData _marker(
    MapCluster<FinanceTransaction> c,
    double zoom,
    Map<String, TxCategory> cats,
  ) {
    final rep = c.items.first;
    FinanceTransaction? photoTx;
    for (final t in c.items) {
      if (t.hasPhoto) {
        photoTx = t;
        break;
      }
    }
    final colorValue = cats[rep.categoryId]?.color ?? 0xFF4F7CFF;
    final color = Color(colorValue);
    final count = c.items.length;
    final iconKey = photoTx != null ? 'p|${photoTx.id}|$count' : 'c|$colorValue|$count';
    if (!_icons.containsKey(iconKey) && !_rendering.contains(iconKey)) {
      _render(iconKey, photoTx, color, count);
    }
    return MapMarkerData(
      id: '${rep.id}|$iconKey',
      point: c.center,
      color: color,
      icon: _icons[iconKey],
      onTap: () {
        if (count == 1) {
          _open(rep, cats);
        } else if (c.bounds.isPoint || zoom >= 17) {
          setState(() => _focus = List.of(c.items));
          if (_sheet.isAttached && _sheet.size < 0.5) {
            _sheet.animateTo(0.55,
                duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          }
        } else {
          setState(() => _focus = null);
          _map.fitBounds(c.bounds);
        }
      },
    );
  }

  // ------------------------------------------------------------------ địa chỉ

  String _address(FinanceTransaction t) {
    final name = t.locationName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final cell = _cell(t.latitude!, t.longitude!);
    final known = _places[cell];
    if (known != null) return known;
    if (_canGeocode && !_geoQueue.containsKey(cell)) {
      _geoQueue[cell] = _pt(t);
      _drainGeocode();
    }
    return LocationService.coords(t.latitude!, t.longitude!);
  }

  Future<void> _drainGeocode() async {
    if (_geocoding) return;
    _geocoding = true;
    try {
      while (mounted) {
        final pending = _geoQueue.entries.where((e) => !_places.containsKey(e.key));
        if (pending.isEmpty) break;
        final e = pending.first;
        final name = await LocationService.placeName(e.value.lat, e.value.lng);
        if (!mounted) return;
        setState(() => _places[e.key] = name);
      }
    } finally {
      _geocoding = false;
    }
  }

  // ------------------------------------------------------------------ giao diện

  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(_locatedTxProvider);
    final cats = ref.watch(categoryMapProvider).valueOrNull ?? const <String, TxCategory>{};
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    final provider = ref.watch(mapBackendProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('map_title'))),
      body: AsyncBody<List<FinanceTransaction>>(
        value: txs,
        builder: (list) {
          final located = list.where((t) => t.hasCoordinates).toList();
          final nameOnly = list.where((t) => !t.hasCoordinates).toList();
          final view = _view;
          final inView = _focus ??
              (view == null
                  ? located
                  : located.where((t) => view.bounds.contains(_pt(t))).toList());

          final mapArea = !online
              ? _Unavailable(message: context.tr('map_unavailable'))
              : provider.buildMap(
                  // Chưa có giao dịch nào có toạ độ -> mở quanh vị trí hiện tại.
                  center: located.isEmpty ? kDefaultMapCenter : _pt(located.first),
                  zoom: located.isEmpty ? 14 : 12,
                  initialBounds: located.isEmpty ? null : MapBounds.around(located.map(_pt)),
                  centerOnMe: located.isEmpty,
                  controller: _map,
                  markers: _markers(located, cats),
                  onViewportChanged: (v) => setState(() => _view = v),
                );

          return LayoutBuilder(builder: (context, c) {
            if (c.maxWidth >= 900) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md), child: mapArea),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: GlassCard(
                        padding: EdgeInsets.zero,
                        child: _panel(null, inView, nameOnly, cats, handle: false),
                      ),
                    ),
                  ],
                ),
              );
            }
            final theme = Theme.of(context);
            return Stack(
              children: [
                Positioned.fill(child: mapArea),
                DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: 0.3,
                  minChildSize: 0.1,
                  maxChildSize: 0.92,
                  snap: true,
                  snapSizes: const [0.3, 0.6],
                  builder: (context, scroll) => Material(
                    color: theme.colorScheme.surface,
                    elevation: 8,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                    clipBehavior: Clip.antiAlias,
                    child: _panel(scroll, inView, nameOnly, cats, handle: true),
                  ),
                ),
              ],
            );
          });
        },
      ),
    );
  }

  Widget _panel(
    ScrollController? scroll,
    List<FinanceTransaction> items,
    List<FinanceTransaction> nameOnly,
    Map<String, TxCategory> cats, {
    required bool handle,
  }) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    String money(int v) => formatMoney(ref, context, v);

    // Gom theo địa chỉ; nhóm có giao dịch mới nhất lên đầu (items đã sắp mới -> cũ).
    final groups = <String, List<FinanceTransaction>>{};
    for (final t in items) {
      groups.putIfAbsent(_address(t), () => []).add(t);
    }
    final spent =
        items.where((t) => t.type == TxType.expense).fold<int>(0, (a, t) => a + t.amountMinor);

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, AppSpacing.lg),
      children: [
        if (handle)
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(context.tr('map_area_title'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            if (_focus != null)
              TextButton(
                onPressed: () => setState(() => _focus = null),
                child: Text(context.tr('map_show_all')),
              ),
          ],
        ),
        Text(context.tr('map_area_summary', {'n': '${items.length}', 'm': money(spent)}),
            style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(context.tr('map_area_empty'),
                textAlign: TextAlign.center, style: TextStyle(color: muted)),
          ),
        for (final e in groups.entries) _group(e.key, e.value, cats),
        if (_focus == null && nameOnly.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.label_outline_rounded),
            title: Text('${context.tr('map_no_coords')} (${nameOnly.length})'),
            children: [
              for (final t in nameOnly)
                TransactionTile(tx: t, category: cats[t.categoryId], onTap: () => _open(t, cats)),
            ],
          ),
      ],
    );
  }

  Widget _group(String address, List<FinanceTransaction> txs, Map<String, TxCategory> cats) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final photos = txs.where((t) => t.hasPhoto).toList();
    final others = txs.where((t) => !t.hasPhoto).toList();
    final fmt = DateFormat('dd/MM/yyyy');
    final newest = fmt.format(txs.first.date);
    final oldest = fmt.format(txs.last.date);
    final spent =
        txs.where((t) => t.type == TxType.expense).fold<int>(0, (a, t) => a + t.amountMinor);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place_rounded, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(address,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      [
                        newest == oldest ? newest : '$oldest – $newest',
                        context.tr('map_area_summary',
                            {'n': '${txs.length}', 'm': formatMoney(ref, context, spent)}),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in photos)
                  GestureDetector(
                    onTap: () => _open(t, cats),
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: PhotoPreview(
                        localPath: t.localImagePath,
                        remotePath: t.remoteImagePath,
                        height: 84,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          for (final t in others)
            TransactionTile(tx: t, category: cats[t.categoryId], onTap: () => _open(t, cats)),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Center(
        child: EmptyState(icon: Icons.map_outlined, message: message),
      ),
    );
  }
}

/// Màn chọn vị trí trên bản đồ, trả về MapPoint.
class MapPickerScreen extends ConsumerStatefulWidget {
  const MapPickerScreen({super.key, this.initial});
  final MapPoint? initial;

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  MapPoint? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    final provider = ref.watch(mapBackendProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('pick_on_map')),
        actions: [
          TextButton(
            onPressed: _selected == null ? null : () => Navigator.of(context).pop(_selected),
            child: Text(context.tr('confirm')),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('map_tap_to_pick')),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: !online
                    ? _Unavailable(message: context.tr('map_unavailable'))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: provider.buildMap(
                          center: _selected ?? kDefaultMapCenter,
                          zoom: _selected == null ? 16 : 14,
                          centerOnMe: _selected == null,
                          selected: _selected,
                          onTap: (p) => setState(() => _selected = p),
                        ),
                      ),
              ),
              if (_selected != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    '${_selected!.lat.toStringAsFixed(6)}, ${_selected!.lng.toStringAsFixed(6)}',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
