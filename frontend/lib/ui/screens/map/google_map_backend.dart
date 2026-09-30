import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;

import '../../../logic/location/location_service.dart';
import 'map_markers.dart';
import 'map_service.dart';

/// Google Maps (chỉ Android, cần GOOGLE_MAPS_API_KEY). Hiển thị bản đồ trên app
/// di động không tính phí; KHÔNG dùng Places/Geocoding của Google (có tính phí) —
/// tên địa điểm vẫn tra bằng dịch vụ có sẵn của điện thoại (LocationService).
class GoogleMapBackend implements MapBackend {
  const GoogleMapBackend();

  @override
  String get name => 'Google Maps';

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
      _GoogleMap(
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

class _GoogleMap extends ConsumerStatefulWidget {
  const _GoogleMap({
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
  ConsumerState<_GoogleMap> createState() => _GoogleMapState();
}

class _GoogleMapState extends ConsumerState<_GoogleMap> implements MapHandle {
  gm.GoogleMapController? _c;
  late double _zoom = widget.zoom;
  bool _locating = false;
  bool _hasPermission = false;
  gm.LatLng? _me;

  /// BitmapDescriptor theo id điểm (id đổi khi ảnh/số lượng đổi).
  final _icons = <String, gm.BitmapDescriptor>{};

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
    _locate(move: widget.centerOnMe, silent: true);
  }

  @override
  void didUpdateWidget(covariant _GoogleMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller?.detach(this);
      widget.controller?.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(this);
    _c?.dispose();
    super.dispose();
  }

  static gm.LatLng _ll(MapPoint p) => gm.LatLng(p.lat, p.lng);

  static gm.LatLngBounds _bounds(MapBounds b) =>
      gm.LatLngBounds(southwest: gm.LatLng(b.south, b.west), northeast: gm.LatLng(b.north, b.east));

  @override
  void moveTo(MapPoint point, double zoom) =>
      _c?.animateCamera(gm.CameraUpdate.newLatLngZoom(_ll(point), zoom));

  @override
  void fitBounds(MapBounds b) => _c?.animateCamera(gm.CameraUpdate.newLatLngBounds(_bounds(b), 64));

  Future<void> _locate({required bool move, bool silent = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    final pos = await LocationService.position();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (pos != null) {
        // Có toạ độ nghĩa là đã được cấp quyền -> bật chấm xanh của Google.
        _hasPermission = true;
        _me = gm.LatLng(pos.latitude, pos.longitude);
      }
    });
    if (pos == null) {
      if (!silent) showLocationUnavailable(context);
      return;
    }
    if (move) {
      await _c?.animateCamera(gm.CameraUpdate.newLatLngZoom(_me!, _zoom < 15 ? 16 : _zoom));
    }
  }

  Future<void> _onCreated(gm.GoogleMapController c) async {
    _c = c;
    final fit = widget.initialBounds;
    if (widget.centerOnMe && _me != null) {
      await c.moveCamera(gm.CameraUpdate.newLatLngZoom(_me!, 16));
    } else if (fit != null && !fit.isPoint) {
      // Bản đồ có thể chưa đo xong kích thước ngay lúc tạo -> đợi 1 nhịp.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        await c.moveCamera(gm.CameraUpdate.newLatLngBounds(_bounds(fit), 64));
      } catch (_) {}
    }
  }

  Future<void> _emitViewport() async {
    final cb = widget.onViewportChanged;
    final c = _c;
    if (cb == null || c == null) return;
    try {
      final r = await c.getVisibleRegion();
      if (!mounted) return;
      cb(MapViewport(
        _zoom,
        MapBounds(r.southwest.latitude, r.southwest.longitude, r.northeast.latitude,
            r.northeast.longitude),
      ));
    } catch (_) {}
  }

  gm.BitmapDescriptor _iconFor(MapMarkerData m) {
    final bytes = m.icon;
    if (bytes == null) {
      return gm.BitmapDescriptor.defaultMarkerWithHue(HSVColor.fromColor(m.color).hue);
    }
    return _icons.putIfAbsent(
      m.id,
      () => gm.BitmapDescriptor.bytes(bytes, width: MarkerIcons.size, height: MarkerIcons.size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    // Bỏ đệm của các điểm không còn trên bản đồ (sau khi phóng to/thu nhỏ).
    final live = {for (final m in widget.markers) m.id};
    _icons.removeWhere((id, _) => !live.contains(id));
    return Stack(
      children: [
        gm.GoogleMap(
          initialCameraPosition: gm.CameraPosition(
              target: _ll(widget.initialBounds?.center ?? widget.center), zoom: widget.zoom),
          // Chỉ dùng ảnh vệ tinh (kèm tên đường).
          mapType: gm.MapType.hybrid,
          myLocationEnabled: _hasPermission,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          // Chỉ kéo + phóng to/thu nhỏ, không xoay / nghiêng bản đồ.
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          compassEnabled: false,
          onMapCreated: _onCreated,
          onCameraMove: (p) => _zoom = p.zoom,
          onCameraIdle: _emitViewport,
          onTap: onTap == null ? null : (p) => onTap(MapPoint(p.latitude, p.longitude)),
          markers: {
            for (final m in widget.markers)
              gm.Marker(
                markerId: gm.MarkerId(m.id),
                position: _ll(m.point),
                icon: _iconFor(m),
                anchor: m.icon == null ? const Offset(0.5, 1) : const Offset(0.45, 0.55),
                consumeTapEvents: true,
                onTap: m.onTap,
              ),
            if (widget.selected != null)
              gm.Marker(
                markerId: const gm.MarkerId('__selected'),
                position: _ll(widget.selected!),
              ),
          },
        ),
        Positioned(
          top: 10,
          right: 10,
          child: MapControls(
            locating: _locating,
            located: _me != null,
            onLocate: () => _locate(move: true),
          ),
        ),
      ],
    );
  }
}
