import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/logic/location/map_cluster.dart';
import 'package:smart_finance/ui/screens/map/map_markers.dart';

void main() {
  MapPoint id(MapPoint p) => p;

  // 2 điểm cách nhau ~110 m ở Q.1 và 1 điểm ở Thủ Đức (~10 km).
  const a = MapPoint(10.7769, 106.7009);
  const b = MapPoint(10.7779, 106.7009);
  const far = MapPoint(10.8700, 106.8030);

  group('MapClusterer', () {
    test('zoom thấp gộp điểm gần, tách điểm xa', () {
      final cs = MapClusterer.cluster([a, b, far], id, 12);
      expect(cs.length, 2);
      expect(cs.first.items, [a, b]); // giữ thứ tự: phần tử đầu là đại diện
      expect(cs.last.items, [far]);
    });

    test('zoom cao tách hết', () {
      final cs = MapClusterer.cluster([a, b, far], id, 18);
      expect(cs.length, 3);
    });

    test('điểm trùng nhau luôn chung nhóm, khung là 1 điểm', () {
      final cs = MapClusterer.cluster([a, a, a], id, 19);
      expect(cs.single.items.length, 3);
      expect(cs.single.bounds.isPoint, isTrue);
    });

    test('tâm nhóm là trung bình', () {
      final c = MapClusterer.cluster([a, b], id, 10).single;
      expect(c.center.lat, closeTo(10.7774, 1e-9));
    });
  });

  group('MapBounds', () {
    test('around + contains', () {
      final bb = MapBounds.around([a, far]);
      expect(bb.contains(b), isTrue);
      expect(bb.contains(const MapPoint(21.0, 105.8)), isFalse);
      expect(bb.isPoint, isFalse);
    });

    test('khung vắt qua kinh tuyến 180', () {
      const bb = MapBounds(-10, 170, 10, -170);
      expect(bb.contains(const MapPoint(0, 175)), isTrue);
      expect(bb.contains(const MapPoint(0, -175)), isTrue);
      expect(bb.contains(const MapPoint(0, 0)), isFalse);
    });
  });

  testWidgets('MarkerIcons vẽ PNG đúng kích thước (có/không số đếm)', (tester) async {
    await tester.runAsync(() async {
      for (final count in [1, 7, 150]) {
        final png = await MarkerIcons.render(color: Colors.teal, count: count, dpr: 2);
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, (MarkerIcons.size * 2).ceil());
        expect(frame.image.height, (MarkerIcons.size * 2).ceil());
      }
    });
  });
}
