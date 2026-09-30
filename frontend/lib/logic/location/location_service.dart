import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

/// Vị trí lúc chụp ảnh khoảnh khắc.
class GeoFix {
  const GeoFix(this.lat, this.lng, this.place);
  final double lat;
  final double lng;

  /// Tên địa điểm (phường, quận, tỉnh) hoặc toạ độ nếu không tra được.
  final String place;
}

/// Lấy vị trí hiện tại (GPS) + tên địa điểm. Mọi lỗi (tắt GPS, từ chối quyền,
/// không có mạng để tra tên) đều trả về null / toạ độ thô — không làm hỏng việc chụp ảnh.
class LocationService {
  const LocationService._();

  static Future<GeoFix?> current({Duration timeout = const Duration(seconds: 12)}) async {
    final pos = await position(timeout: timeout);
    if (pos == null) return null;
    final place = await placeName(pos.latitude, pos.longitude);
    return GeoFix(pos.latitude, pos.longitude, place);
  }

  /// Chỉ lấy toạ độ GPS (không tra tên) — dùng cho chấm "vị trí của tôi" trên bản đồ.
  static Future<Position?> position({Duration timeout = const Duration(seconds: 12)}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(timeout);
      } catch (_) {
        try {
          return await Geolocator.getLastKnownPosition();
        } catch (_) {
          return null;
        }
      }
    } catch (_) {
      return null;
    }
  }

  /// Xin quyền "Luôn cho phép" (lấy vị trí cả khi app đang đóng). Trả về quyền cuối cùng.
  /// Android 11+: lần xin thứ hai mở trang cài đặt để người dùng tự chọn "Luôn cho phép".
  static Future<LocationPermission> requestAlways() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.whileInUse) perm = await Geolocator.requestPermission();
      return perm;
    } catch (_) {
      return LocationPermission.denied;
    }
  }

  /// Xin quyền vị trí sớm (khi mở app) để lúc chụp/ghi giao dịch lấy được ngay.
  static Future<void> ensurePermission() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) await Geolocator.requestPermission();
    } catch (_) {}
  }

  static String coords(double lat, double lng) =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  /// Tên địa điểm dễ đọc; không tra được (offline, Windows) thì trả toạ độ.
  static Future<String> placeName(double lat, double lng) async {
    try {
      final marks =
          await geo.placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 6));
      if (marks.isEmpty) return coords(lat, lng);
      final m = marks.first;
      final parts = <String>[];
      for (final s in [m.street, m.subLocality, m.subAdministrativeArea, m.administrativeArea]) {
        final v = (s ?? '').trim();
        if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
      }
      if (parts.isEmpty) return coords(lat, lng);
      return parts.take(3).join(', ');
    } catch (_) {
      return coords(lat, lng);
    }
  }
}
