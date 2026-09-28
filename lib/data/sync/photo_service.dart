import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/storage/file_paths.dart';
import '../../core/utils/ids.dart';

/// Pipeline ảnh (spec I): chọn ảnh -> lưu local (đã nén) -> gắn vào giao dịch ->
/// Sync Engine upload -> chỉ xóa file local khi upload + metadata đã xác nhận.
class PhotoService {
  const PhotoService();

  static String remotePath(String userId, String txId) => '$userId/$txId.jpg';

  /// Nén/resize trong isolate rồi lưu vào thư mục ảnh tạm. Trả về đường dẫn file.
  Future<String> saveCompressed(Uint8List original) async {
    final bytes = await compute(_compress, original);
    final dir = await FilePaths.photosDir();
    final file = File(p.join(dir.path, '${Ids.newId()}.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List?> read(String? path) async {
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  Future<bool> exists(String? path) async => path != null && await File(path).exists();

  Future<void> deleteLocal(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Không crash nếu file đang bị khóa; lần dọn sau sẽ thử lại.
    }
  }
}

Uint8List _compress(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const FormatException('unsupported_image');
  }
  final maxSide = AppConstants.photoMaxSide;
  img.Image out = decoded;
  if (decoded.width > maxSide || decoded.height > maxSide) {
    out = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxSide)
        : img.copyResize(decoded, height: maxSide);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: AppConstants.photoJpegQuality));
}
