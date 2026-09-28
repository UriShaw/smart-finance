package io.smartfinance.smart_finance;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

/** Lưu ảnh khoảnh khắc vào Thư viện ảnh (Pictures/SmartFinance). Không cần quyền trên Android 10+. */
public final class PhotoSaver {
    private PhotoSaver() {}

    /** Trả về vị trí dễ đọc (vd. "Pictures/SmartFinance/xxx.jpg"). Ném lỗi nếu thất bại. */
    public static String save(Context ctx, byte[] bytes, String name) throws Exception {
        if (name == null || name.isEmpty()) name = "SmartFinance_" + System.currentTimeMillis() + ".jpg";
        if (!name.toLowerCase().endsWith(".jpg")) name = name + ".jpg";
        String folder = "SmartFinance";
        if (Build.VERSION.SDK_INT >= 29) {
            ContentResolver cr = ctx.getContentResolver();
            ContentValues v = new ContentValues();
            v.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
            v.put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg");
            v.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/" + folder);
            v.put(MediaStore.MediaColumns.IS_PENDING, 1);
            Uri uri = cr.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
            if (uri == null) throw new IllegalStateException("MediaStore insert failed");
            try (OutputStream os = cr.openOutputStream(uri)) {
                if (os == null) throw new IllegalStateException("open failed");
                os.write(bytes);
            } catch (Exception e) {
                cr.delete(uri, null, null);
                throw e;
            }
            ContentValues done = new ContentValues();
            done.put(MediaStore.MediaColumns.IS_PENDING, 0);
            cr.update(uri, done, null, null);
            return Environment.DIRECTORY_PICTURES + "/" + folder + "/" + name;
        }
        // Android 9 trở xuống: thư mục ảnh của app (không cần quyền), rồi quét để hiện trong Thư viện.
        File dir = new File(ctx.getExternalFilesDir(Environment.DIRECTORY_PICTURES), folder);
        if (!dir.exists() && !dir.mkdirs()) throw new IllegalStateException("mkdir failed");
        File f = new File(dir, name);
        try (FileOutputStream fos = new FileOutputStream(f)) {
            fos.write(bytes);
        }
        MediaScannerConnection.scanFile(ctx, new String[]{f.getAbsolutePath()},
                new String[]{"image/jpeg"}, null);
        return f.getAbsolutePath();
    }
}
