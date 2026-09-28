package io.smartfinance.smart_finance;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.Settings;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Cầu nối Flutter <-> Android cho tính năng thông báo ngân hàng. */
public final class BankChannel {
    private BankChannel() {}

    public static final String NAME = "smart_finance/bank";

    private static MethodChannel channel;
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    public static void register(FlutterEngine engine, final Activity activity) {
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), NAME);
        final Context ctx = activity.getApplicationContext();
        channel.setMethodCallHandler((call, result) -> {
            try {
                handle(activity, ctx, call, result);
            } catch (Throwable t) {
                result.error("bank_error", String.valueOf(t.getMessage()), null);
            }
        });
    }

    public static void unregister() {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
    }

    /** Service báo có giao dịch mới -> Flutter (nếu đang mở) lấy hàng chờ ngay. */
    public static void notifyNewEvent() {
        MAIN.post(() -> {
            if (channel != null) channel.invokeMethod("pendingChanged", null);
        });
    }

    private static void handle(Activity activity, Context ctx, MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "isPermissionGranted":
                result.success(isGranted(ctx));
                break;
            case "openPermissionSettings":
                start(activity, new Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"));
                result.success(null);
                break;
            case "openAppDetails":
                start(activity, new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:" + ctx.getPackageName())));
                result.success(null);
                break;
            case "openBatterySettings":
                start(activity, new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
                result.success(null);
                break;
            case "getConfig": {
                Map<String, Object> m = new HashMap<>();
                m.put("enabled", BankStore.enabled(ctx));
                m.put("speak", BankStore.speak(ctx));
                m.put("speakExpense", BankStore.speakExpense(ctx));
                m.put("allow", new ArrayList<>(BankStore.allow(ctx)));
                m.put("block", new ArrayList<>(BankStore.block(ctx)));
                m.put("pending", BankStore.pendingCount(ctx));
                m.put("volumeBoost", BankStore.volumeBoost(ctx));
                m.put("voice", BankStore.voice(ctx));
                m.put("chime", BankStore.chime(ctx));
                m.put("rate", (double) BankStore.rate(ctx));
                m.put("pitch", (double) BankStore.pitch(ctx));
                m.put("batteryIgnored", isIgnoringBattery(ctx));
                result.success(m);
                break;
            }
            case "setAudio": {
                Boolean boost = call.argument("volumeBoost");
                String voice = call.argument("voice");
                String chime = call.argument("chime");
                Number rate = call.argument("rate");
                Number pitch = call.argument("pitch");
                BankStore.setAudio(ctx, !Boolean.FALSE.equals(boost), voice, chime,
                        rate == null ? 1f : rate.floatValue(), pitch == null ? 1f : pitch.floatValue());
                result.success(null);
                break;
            }
            case "preview": {
                String text = call.argument("text");
                BankSpeaker.get(ctx).speak(text);
                result.success(null);
                break;
            }
            case "simulate": {
                String text = call.argument("text");
                BankParser.Result r = BankNotificationListener.handle(ctx, "vn.test.mobilebanking",
                        "Giả lập", text, System.currentTimeMillis(), true);
                result.success(resultMap(r));
                break;
            }
            case "restartListener": {
                restartListener(ctx);
                result.success(null);
                break;
            }
            case "openTtsSettings": {
                try {
                    Intent i = new Intent("com.android.settings.TTS_SETTINGS");
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    activity.startActivity(i);
                } catch (Throwable t) {
                    start(activity, new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));
                }
                result.success(null);
                break;
            }
            case "openAutostart": {
                openAutostart(activity);
                result.success(null);
                break;
            }
            case "requestIgnoreBattery": {
                if (Build.VERSION.SDK_INT >= 23 && !isIgnoringBattery(ctx)) {
                    try {
                        activity.startActivity(new Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:" + ctx.getPackageName())));
                    } catch (Throwable t) {
                        start(activity, new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
                    }
                }
                result.success(null);
                break;
            }
            case "setConfig": {
                Boolean enabled = call.argument("enabled");
                Boolean speak = call.argument("speak");
                Boolean speakExpense = call.argument("speakExpense");
                List<String> allow = call.argument("allow");
                List<String> block = call.argument("block");
                BankStore.setConfig(ctx, Boolean.TRUE.equals(enabled), !Boolean.FALSE.equals(speak),
                        !Boolean.FALSE.equals(speakExpense), allow, block);
                if (Boolean.TRUE.equals(enabled)) BankNotificationListener.rebind(ctx);
                result.success(null);
                break;
            }
            case "getPending":
                result.success(toList(BankStore.peekPending(ctx)));
                break;
            case "ackPending": {
                List<String> ids = call.argument("ids");
                BankStore.ackPending(ctx, ids == null ? null : new java.util.HashSet<>(ids));
                result.success(null);
                break;
            }
            case "getLog":
                result.success(toList(BankStore.getLog(ctx)));
                break;
            case "clearLog":
                BankStore.clearLog(ctx);
                result.success(null);
                break;
            case "testParse": {
                String pkg = call.argument("pkg");
                String title = call.argument("title");
                String text = call.argument("text");
                BankParser.Result r = BankNotificationListener.handle(ctx, pkg, title, text, 0, false);
                result.success(resultMap(r));
                break;
            }
            case "speak": {
                String text = call.argument("text");
                BankSpeaker.get(ctx).speak(text);
                result.success(null);
                break;
            }
            case "saveImage": {
                byte[] bytes = call.argument("bytes");
                String name = call.argument("name");
                try {
                    result.success(PhotoSaver.save(ctx, bytes, name));
                } catch (Throwable t) {
                    result.error("save_failed", String.valueOf(t.getMessage()), null);
                }
                break;
            }
            case "supportedBanks": {
                Set<String> names = new LinkedHashSet<>(BankRegistry.KNOWN_APPS.values());
                result.success(new ArrayList<>(names));
                break;
            }
            default:
                result.notImplemented();
        }
    }

    private static Map<String, Object> resultMap(BankParser.Result r) {
        Map<String, Object> m = new HashMap<>();
        m.put("accepted", r.accepted);
        m.put("reason", r.reason);
        m.put("amount", r.amount);
        m.put("direction", r.direction);
        m.put("balance", r.balance);
        m.put("bank", r.bank);
        m.put("content", r.content);
        m.put("sender", r.sender);
        m.put("trust", r.trust);
        m.put("announcement", r.accepted
                ? VietnameseNumber.announcement(r.direction, r.amount, r.sender) : "");
        return m;
    }

    static boolean isIgnoringBattery(Context ctx) {
        if (Build.VERSION.SDK_INT < 23) return true;
        PowerManager pm = (PowerManager) ctx.getSystemService(Context.POWER_SERVICE);
        return pm != null && pm.isIgnoringBatteryOptimizations(ctx.getPackageName());
    }

    /** Tắt rồi bật lại service đọc thông báo (khi hệ thống "quên" kết nối lại). */
    private static void restartListener(Context ctx) {
        PackageManager pm = ctx.getPackageManager();
        ComponentName cn = new ComponentName(ctx, BankNotificationListener.class);
        try {
            pm.setComponentEnabledSetting(cn, PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP);
            pm.setComponentEnabledSetting(cn, PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP);
        } catch (Throwable ignored) {
        }
        BankNotificationListener.rebind(ctx);
    }

    /** Màn "Tự khởi động" của từng hãng (Xiaomi, Oppo, Vivo, Huawei...), không có thì mở thông tin app. */
    private static void openAutostart(Activity activity) {
        String[][] targets = {
                {"com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"},
                {"com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"},
                {"com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"},
                {"com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"},
                {"com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"},
                {"com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"},
                {"com.asus.mobilemanager", "com.asus.mobilemanager.MainActivity"},
        };
        for (String[] t : targets) {
            try {
                // Không cần kiểm tra trước (Android 11+ ẩn gói khác); không có thì ném lỗi -> thử tiếp.
                Intent i = new Intent();
                i.setComponent(new ComponentName(t[0], t[1]));
                activity.startActivity(i);
                return;
            } catch (Throwable ignored) {
            }
        }
        start(activity, new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:" + activity.getPackageName())));
    }

    private static boolean isGranted(Context ctx) {
        String flat = Settings.Secure.getString(ctx.getContentResolver(), "enabled_notification_listeners");
        return flat != null && flat.contains(ctx.getPackageName());
    }

    private static void start(Activity activity, Intent intent) {
        try {
            activity.startActivity(intent);
        } catch (Throwable t) {
            // Một số máy không có màn cài đặt này -> mở thông tin ứng dụng.
            Intent fallback = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + activity.getPackageName()));
            activity.startActivity(fallback);
        }
    }

    private static List<Map<String, Object>> toList(JSONArray arr) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (int i = 0; i < arr.length(); i++) {
            JSONObject o = arr.optJSONObject(i);
            if (o == null) continue;
            Map<String, Object> m = new HashMap<>();
            Iterator<String> keys = o.keys();
            while (keys.hasNext()) {
                String k = keys.next();
                Object v = o.opt(k);
                if (v == null || v == JSONObject.NULL) continue;
                if (v instanceof Integer) v = ((Integer) v).longValue();
                m.put(k, v);
            }
            out.add(m);
        }
        return out;
    }
}
