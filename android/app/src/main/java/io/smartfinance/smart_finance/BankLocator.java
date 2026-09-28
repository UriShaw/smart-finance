package io.smartfinance.smart_finance;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Lấy vị trí hiện tại khi có thông báo giao dịch (không cần Google Play Services).
 * - Vị trí đã có trong máy còn mới (≤ 1 phút, sai số ≤ 100 m) -> dùng ngay.
 * - Không thì xin 1 lần vị trí mới, chờ tối đa [timeoutMs]; hết giờ dùng vị trí cũ ≤ 10 phút.
 * App đang đóng thì Android chỉ cho lấy vị trí khi người dùng chọn quyền "Luôn cho phép".
 * Mọi lỗi -> trả null (giao dịch vẫn được ghi, chỉ không có vị trí).
 */
final class BankLocator {
    private BankLocator() {}

    interface Callback {
        void done(Location location);
    }

    private static final long FRESH_MS = 60_000L;
    private static final long STALE_MS = 10L * 60_000L;

    static boolean hasPermission(Context c) {
        return c.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                || c.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    static void fetch(Context ctx, long timeoutMs, Callback cb) {
        final Context app = ctx.getApplicationContext();
        final Handler main = new Handler(Looper.getMainLooper());
        final AtomicBoolean fired = new AtomicBoolean(false);
        final Location[] cached = {null};
        final Callback once = loc -> {
            if (fired.compareAndSet(false, true)) main.post(() -> cb.done(loc));
        };
        if (!hasPermission(app)) {
            once.done(null);
            return;
        }
        LocationManager lm = (LocationManager) app.getSystemService(Context.LOCATION_SERVICE);
        if (lm == null) {
            once.done(null);
            return;
        }
        cached[0] = bestLastKnown(lm);
        Location last = cached[0];
        if (last != null && age(last) <= FRESH_MS && last.hasAccuracy() && last.getAccuracy() <= 100f) {
            once.done(last);
            return;
        }
        String provider = pickProvider(lm);
        if (provider == null) {
            once.done(fresh(last));
            return;
        }
        final CancellationSignal cancel = new CancellationSignal();
        final LocationListener[] legacy = {null};
        main.postDelayed(() -> {
            cancel.cancel();
            if (legacy[0] != null) lm.removeUpdates(legacy[0]);
            once.done(fresh(cached[0]));
        }, timeoutMs);
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                lm.getCurrentLocation(provider, cancel, app.getMainExecutor(),
                        loc -> once.done(loc != null ? loc : fresh(cached[0])));
            } else {
                legacy[0] = new LocationListener() {
                    @Override public void onLocationChanged(Location loc) { once.done(loc); }
                    @Override public void onStatusChanged(String p, int s, Bundle b) {}
                    @Override public void onProviderEnabled(String p) {}
                    @Override public void onProviderDisabled(String p) {}
                };
                lm.requestSingleUpdate(provider, legacy[0], Looper.getMainLooper());
            }
        } catch (SecurityException | IllegalArgumentException e) {
            once.done(fresh(cached[0]));
        }
    }

    private static String pickProvider(LocationManager lm) {
        try {
            if (Build.VERSION.SDK_INT >= 31 && lm.isProviderEnabled(LocationManager.FUSED_PROVIDER)) {
                return LocationManager.FUSED_PROVIDER;
            }
            // Mạng (wifi/trạm) nhanh hơn GPS trong nhà, đủ chính xác để ra địa chỉ.
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) return LocationManager.NETWORK_PROVIDER;
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) return LocationManager.GPS_PROVIDER;
        } catch (Exception ignored) {
        }
        return null;
    }

    private static Location bestLastKnown(LocationManager lm) {
        Location best = null;
        try {
            for (String p : lm.getProviders(true)) {
                Location l = lm.getLastKnownLocation(p);
                if (l != null && (best == null || l.getTime() > best.getTime())) best = l;
            }
        } catch (SecurityException ignored) {
        }
        return best;
    }

    private static long age(Location l) {
        return Math.abs(System.currentTimeMillis() - l.getTime());
    }

    private static Location fresh(Location l) {
        return l != null && age(l) <= STALE_MS ? l : null;
    }
}
