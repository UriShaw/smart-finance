import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';

class FilePaths {
  const FilePaths._();

  static Directory? _override;

  /// Cho test: dùng thư mục tạm thay vì path_provider.
  static void overrideForTest(Directory dir) => _override = dir;

  static Future<Directory> appDataDir() async {
    if (_override != null) return _override!;
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Thư mục ảnh tạm (bộ nhớ tạm) - được dọn sau khi upload cloud thành công.
  static Future<Directory> photosDir() async {
    final dir = Directory(p.join((await appDataDir()).path, AppConstants.photosDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<int> directorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  static String humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
