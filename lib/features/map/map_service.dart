import 'dart:async';
import 'dart:typed_data';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/env.dart';
import '../../core/localization/app_localizations.dart';
import '../moments/location_service.dart';
import 'google_map_backend.dart';
import 'map_cluster.dart';
import 'map_markers.dart';

export 'map_cluster.dart' show MapBounds, MapPoint;

/// Abstraction bản đồ (spec N): đổi provider (OSM, Google, Mapbox...) chỉ cần
/// thêm 1 implementation của [MapBackend]. UI không phụ thuộc thư viện map.
class MapMarkerData {
  const MapMarkerData({
    required this.id,
    required this.point,
    required this.color,
    this.icon,
    this.onTap,
  });

  final String id;
  final MapPoint point;
  final Color color;

  /// PNG từ [MarkerIcons.render]; null -> ghim mặc định theo [color].
  /// Nội dung ảnh gắn với [id] (đổi ảnh thì đổi id) để backend lưu đệm được.
  final Uint8List? icon;
  final VoidCallback? onTap;
}

/// Vùng đang xem sau khi người dùng kéo / phóng to.
class MapViewport {
  const MapViewport(this.zoom, this.bounds);
  final double zoom;
  final MapBounds bounds;
}

/// Backend gắn vào để màn hình điều khiển camera.
abstract class MapHandle {
  void moveTo(MapPoint point, double zoom);
  void fitBounds(MapBounds bounds);
}

class MapViewController {
  MapHandle? _handle;

  void attach(MapHandle h) => _handle = h;
  void detach(MapHandle h) {
    if (identical(_handle, h)) _handle = null;
  }

  void moveTo(MapPoint point, double zoom) => _handle?.moveTo(point, zoom);

  /// Khung chỉ là 1 điểm -> phóng tới zoom 17 tại điểm đó.
  void fitBounds(MapBounds bounds) =>
      bounds.isPoint ? _handle?.moveTo(bounds.center, 17) : _handle?.fitBounds(bounds);
}

/// Kiểu nền bản đồ.
enum MapStyle { standard, terrain, satellite }

abstract class MapBackend {
  String get name;

  /// [centerOnMe]: lấy được GPS thì dời bản đồ về vị trí người dùng.
  /// [initialBounds]: mở bản đồ vừa khít khung này (ưu tiên hơn [center]).
  Widget buildMap({
    required MapPoint center,
    double zoom = 13,
    MapBounds? initialBounds,
    List<MapMarkerData> markers = const [],
    MapPoint? selected,
    void Function(MapPoint point)? onTap,
    bool centerOnMe = false,
    MapViewController? controller,
    void Function(MapViewport viewport)? onViewportChanged,
  });
}

/// Kiểu bản đồ đang chọn (giữ trong phiên, dùng chung cho mọi màn bản đồ).
final mapStyleProvider = StateProvider<MapStyle>((ref) => MapStyle.standard);

/// Android + có GOOGLE_MAPS_API_KEY (config/env.json) -> Google Maps; còn lại OSM.
final mapBackendProvider = Provider<MapBackend>((ref) {
  if (!kIsWeb && Platform.isAndroid && Env.googleMapsApiKey.isNotEmpty) {
    return const GoogleMapBackend();
  }
  return const OsmMapProvider();
});

/// Tâm mặc định: TP. Hồ Chí Minh.
const kDefaultMapCenter = MapPoint(10.7769, 106.7009);

/// Nút "kiểu bản đồ" + "vị trí của tôi" ở góc phải trên, dùng chung mọi backend.
class MapControls extends ConsumerWidget {
  const MapControls({
    super.key,
    required this.locating,
    required this.located,
    required this.onLocate,
  });

  final bool locating;
  final bool located;
  final VoidCallback onLocate;

  Future<void> _pickStyle(BuildContext anchor, WidgetRef ref) async {
    final current = ref.read(mapStyleProvider);
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await showMenu<MapStyle>(
      context: anchor,
      position: RelativeRect.fromRect(origin & box.size, Offset.zero & overlay.size),
      items: [
        for (final (style, icon, key) in const [
          (MapStyle.standard, Icons.map_outlined, 'map_style_standard'),
          (MapStyle.terrain, Icons.terrain_rounded, 'map_style_terrain'),
          (MapStyle.satellite, Icons.satellite_alt_rounded, 'map_style_satellite'),
        ])
          CheckedPopupMenuItem(
            value: style,
            checked: style == current,
            child: Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Text(anchor.tr(key)),
            ]),
          ),
      ],
    );
    if (picked != null) ref.read(mapStyleProvider.notifier).state = picked;
  }

  static Widget _button({
    required String tooltip,
    required VoidCallback? onPressed,
    required Widget icon,
  }) =>
      Material(
        color: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          color: const Color(0xFF1F2937),
          icon: icon,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Builder(
          builder: (anchor) => _button(
            tooltip: context.tr('map_style'),
            onPressed: () => _pickStyle(anchor, ref),
            icon: const Icon(Icons.layers_rounded),
          ),
        ),
        const SizedBox(height: 10),
        _button(
          tooltip: context.tr('map_my_location'),
          onPressed: locating ? null : onLocate,
          icon: locating
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(located ? Icons.my_location_rounded : Icons.location_searching_rounded),
        ),
      ],
    );
  }
}

/// Báo lỗi không lấy được vị trí (dùng chung).
void showLocationUnavailable(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(context.tr('map_location_unavailable'))));
}

/// OpenStreetMap qua flutter_map. Lưu ý chính sách sử dụng tile của OSM
/// (không dùng cho tải lớn/thương mại) - xem docs/phases/phase-04-07-architecture-design.md.
/// Địa hình: OpenTopoMap; vệ tinh: Esri World Imagery (miễn phí, cần ghi nguồn).
class OsmMapProvider implements MapBackend {
  const OsmMapProvider();

  @override
  String get name => 'OpenStreetMap';

  @override
  Widget buildMap({
    required MapPoint center,
    double zoom = 13,
    MapBounds? initialBounds,
    List<MapMarkerData> markers = const [],
    MapPoint? selected,
    void Function(MapPoint point)? onTap,
    bool centerOnMe = false,
    MapViewController? controller,
    void Function(MapViewport viewport)? onViewportChanged,
  }) =>
      _OsmMap(
        center: center,
        zoom: zoom,
        initialBounds: initialBounds,
        markers: markers,
        selected: selected,
        onTap: onTap,
        centerOnMe: centerOnMe,
        controller: controller,
        onViewportChanged: onViewportChanged,
      );
}

class _OsmMap extends ConsumerStatefulWidget {
  const _OsmMap({
    required this.center,
    required this.zoom,
    required this.initialBounds,
    required this.markers,
    required this.selected,
    required this.onTap,
    required this.centerOnMe,
    required this.controller,
    required this.onViewportChanged,
  });

  final MapPoint center;
  final double zoom;
  final MapBounds? initialBounds;
  final List<MapMarkerData> markers;
  final MapPoint? selected;
  final void Function(MapPoint point)? onTap;
  final bool centerOnMe;
  final MapViewController? controller;
  final void Function(MapViewport viewport)? onViewportChanged;

  @override
  ConsumerState<_OsmMap> createState() => _OsmMapState();
}

class _OsmMapState extends ConsumerState<_OsmMap> implements MapHandle {
  static const _meColor = Color(0xFF1A73E8);

  final _ctl = MapController();
  Timer? _idle;
  bool _ready = false;
  bool _locating = false;
  LatLng? _me;
  double _meAccuracy = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
    // Lấy vị trí ngay khi mở để hiện chấm xanh; chỉ dời bản đồ nếu được yêu cầu.
    _locate(move: widget.centerOnMe, silent: true);
  }

  @override
  void didUpdateWidget(covariant _OsmMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller?.detach(this);
      widget.controller?.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(this);
    _idle?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  static LatLng _ll(MapPoint p) => LatLng(p.lat, p.lng);

  @override
  void moveTo(MapPoint point, double zoom) {
    if (_ready) _ctl.move(_ll(point), zoom);
  }

  @override
  void fitBounds(MapBounds b) {
    if (!_ready) return;
    _ctl.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(LatLng(b.south, b.west), LatLng(b.north, b.east)),
      padding: const EdgeInsets.all(64),
      maxZoom: 17,
    ));
  }

  void _emitViewport() {
    final cb = widget.onViewportChanged;
    if (cb == null || !_ready) return;
    final cam = _ctl.camera;
    final vb = cam.visibleBounds;
    cb(MapViewport(cam.zoom, MapBounds(vb.south, vb.west, vb.north, vb.east)));
  }

  Future<void> _locate({required bool move, bool silent = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    final pos = await LocationService.position();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (pos != null) {
        _me = LatLng(pos.latitude, pos.longitude);
        _meAccuracy = pos.accuracy;
      }
    });
    if (pos == null) {
      if (!silent) showLocationUnavailable(context);
      return;
    }
    if (move && _ready) {
      final z = _ctl.camera.zoom;
      _ctl.move(_me!, z < 15 ? 16 : z);
    }
  }

  static List<Widget> _tiles(MapStyle style) => switch (style) {
        MapStyle.standard => [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'io.smartfinance.app',
              maxNativeZoom: 19,
            ),
          ],
        MapStyle.terrain => [
            TileLayer(
              urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'io.smartfinance.app',
              maxNativeZoom: 17,
            ),
          ],
        MapStyle.satellite => [
            TileLayer(
              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
                  'World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'io.smartfinance.app',
              maxNativeZoom: 19,
            ),
            // Tên đường/địa danh phủ lên ảnh vệ tinh.
            TileLayer(
              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
                  'Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'io.smartfinance.app',
              maxNativeZoom: 19,
            ),
          ],
      };

  static String _attribution(MapStyle style) => switch (style) {
        MapStyle.standard => '© OpenStreetMap contributors',
        MapStyle.terrain => '© OpenStreetMap contributors, SRTM · © OpenTopoMap (CC-BY-SA)',
        MapStyle.satellite => 'Tiles © Esri — Esri, Maxar, Earthstar Geographics',
      };

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(mapStyleProvider);
    final onTap = widget.onTap;
    final me = _me;
    final fit = widget.initialBounds;
    return Stack(
      children: [
        FlutterMap(
          mapController: _ctl,
          options: MapOptions(
            initialCenter: _ll(widget.center),
            initialZoom: widget.zoom,
            initialCameraFit: fit == null || fit.isPoint
                ? null
                : CameraFit.bounds(
                    bounds: LatLngBounds(LatLng(fit.south, fit.west), LatLng(fit.north, fit.east)),
                    padding: const EdgeInsets.all(64),
                    maxZoom: 16,
                  ),
            maxZoom: 19,
            onMapReady: () {
              _ready = true;
              // GPS trả về trước khi bản đồ sẵn sàng -> dời ngay lúc này.
              if (widget.centerOnMe && _me != null) _ctl.move(_me!, 16);
              _emitViewport();
            },
            onPositionChanged: (_, __) {
              _idle?.cancel();
              _idle = Timer(const Duration(milliseconds: 250), _emitViewport);
            },
            onTap: onTap == null
                ? null
                : (_, latLng) => onTap(MapPoint(latLng.latitude, latLng.longitude)),
          ),
          children: [
            ..._tiles(style),
            if (me != null && _meAccuracy > 0)
              CircleLayer(circles: [
                CircleMarker(
                  point: me,
                  radius: _meAccuracy,
                  useRadiusInMeter: true,
                  color: _meColor.withValues(alpha: 0.15),
                  borderColor: _meColor.withValues(alpha: 0.4),
                  borderStrokeWidth: 1,
                ),
              ]),
            MarkerLayer(
              markers: [
                if (me != null)
                  Marker(
                    point: me,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _meColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                    ),
                  ),
                for (final m in widget.markers)
                  m.icon != null
                      ? Marker(
                          key: ValueKey(m.id),
                          point: _ll(m.point),
                          width: MarkerIcons.size,
                          height: MarkerIcons.size,
                          child: GestureDetector(
                            onTap: m.onTap,
                            child: Image.memory(m.icon!, gaplessPlayback: true),
                          ),
                        )
                      : Marker(
                          key: ValueKey(m.id),
                          point: _ll(m.point),
                          width: 36,
                          height: 36,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: m.onTap,
                            child: Icon(Icons.location_on, color: m.color, size: 36),
                          ),
                        ),
                if (widget.selected != null)
                  Marker(
                    point: _ll(widget.selected!),
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.place, color: Colors.redAccent, size: 44),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 10,
          right: 10,
          child: MapControls(
            locating: _locating,
            located: me != null,
            onLocate: () => _locate(move: true),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Container(
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: Colors.white70,
            child: Text(_attribution(style),
                style: const TextStyle(fontSize: 11, color: Colors.black87)),
          ),
        ),
      ],
    );
  }
}
