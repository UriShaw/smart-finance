import 'dart:math' as math;

/// Toạ độ độc lập thư viện bản đồ.
class MapPoint {
  const MapPoint(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// Khung toạ độ (nam, tây, bắc, đông).
class MapBounds {
  const MapBounds(this.south, this.west, this.north, this.east);

  /// Khung nhỏ nhất chứa mọi điểm (danh sách phải khác rỗng).
  factory MapBounds.around(Iterable<MapPoint> points) {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final p in points) {
      s = math.min(s, p.lat);
      n = math.max(n, p.lat);
      w = math.min(w, p.lng);
      e = math.max(e, p.lng);
    }
    return MapBounds(s, w, n, e);
  }

  final double south;
  final double west;
  final double north;
  final double east;

  MapPoint get center => MapPoint((south + north) / 2, (west + east) / 2);

  /// Mọi điểm gần như trùng nhau -> không thể "phóng to vào khung".
  bool get isPoint => (north - south).abs() < 1e-4 && (east - west).abs() < 1e-4;

  bool contains(MapPoint p) {
    if (p.lat < south || p.lat > north) return false;
    // Khung vắt qua kinh tuyến 180.
    return west <= east ? p.lng >= west && p.lng <= east : p.lng >= west || p.lng <= east;
  }
}

/// Nhóm các điểm nằm sát nhau trên màn hình ở mức zoom hiện tại.
class MapCluster<T> {
  MapCluster(this.items, this.points);

  /// Theo thứ tự đầu vào: phần tử đầu là đại diện (ảnh hiển thị).
  final List<T> items;
  final List<MapPoint> points;

  MapPoint get center {
    var lat = 0.0, lng = 0.0;
    for (final p in points) {
      lat += p.lat;
      lng += p.lng;
    }
    return MapPoint(lat / points.length, lng / points.length);
  }

  MapBounds get bounds => MapBounds.around(points);
}

class MapClusterer {
  const MapClusterer._();

  static const double tileSize = 256;

  /// Toạ độ pixel toàn cầu (Web Mercator) ở mức [zoom].
  static math.Point<double> project(MapPoint p, double zoom) {
    final scale = tileSize * math.pow(2, zoom);
    final lat = p.lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    final x = (p.lng + 180) / 360 * scale;
    final y = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * scale;
    return math.Point(x, y);
  }

  /// Gộp tham lam: mỗi điểm vào nhóm đầu tiên có điểm gốc cách < [radiusPx] pixel,
  /// không có thì mở nhóm mới. Giữ thứ tự đầu vào (đưa phần tử mới nhất lên trước
  /// để ảnh đại diện là ảnh mới nhất, giống Google Photos).
  static List<MapCluster<T>> cluster<T>(
    List<T> items,
    MapPoint Function(T item) pointOf,
    double zoom, {
    double radiusPx = 56,
  }) {
    final out = <MapCluster<T>>[];
    final anchors = <math.Point<double>>[];
    final r2 = radiusPx * radiusPx;
    for (final item in items) {
      final p = pointOf(item);
      final px = project(p, zoom);
      var placed = false;
      for (var i = 0; i < out.length; i++) {
        final a = anchors[i];
        final dx = a.x - px.x, dy = a.y - px.y;
        if (dx * dx + dy * dy <= r2) {
          out[i].items.add(item);
          out[i].points.add(p);
          placed = true;
          break;
        }
      }
      if (!placed) {
        out.add(MapCluster<T>([item], [p]));
        anchors.add(px);
      }
    }
    return out;
  }
}
