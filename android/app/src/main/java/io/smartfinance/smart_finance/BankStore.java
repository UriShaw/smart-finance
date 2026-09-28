package io.smartfinance.smart_finance;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;

/**
 * Lưu trữ phía Android cho tính năng đọc thông báo ngân hàng:
 * cấu hình, hàng chờ giao dịch (Flutter lấy ra khi mở app), nhật ký, bộ nhớ chống trùng.
 * Dữ liệu chỉ nằm trên máy (SharedPreferences riêng của app).
 */
public final class BankStore {
    private BankStore() {}

    private static final String PREFS = "sf_bank";
    private static final String K_ENABLED = "enabled";
    private static final String K_SPEAK = "speak";
    private static final String K_SPEAK_EXPENSE = "speak_expense";
    private static final String K_ALLOW = "allow";
    private static final String K_BLOCK = "block";
    private static final String K_PENDING = "pending";
    private static final String K_LOG = "log";
    private static final String K_RECENT = "recent";
    private static final String K_BOOST = "volume_boost";
    private static final String K_VOICE = "voice";
    private static final String K_CHIME = "chime";
    private static final String K_RATE = "speech_rate";
    private static final String K_PITCH = "speech_pitch";

    private static final int MAX_PENDING = 1000;
    private static final int MAX_LOG = 150;

    private static SharedPreferences prefs(Context c) {
        return c.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    // ------------------------------------------------------------------ cấu hình

    public static boolean enabled(Context c) {
        return prefs(c).getBoolean(K_ENABLED, false);
    }

    public static boolean speak(Context c) {
        return prefs(c).getBoolean(K_SPEAK, true);
    }

    public static boolean speakExpense(Context c) {
        return prefs(c).getBoolean(K_SPEAK_EXPENSE, true);
    }

    public static Set<String> allow(Context c) {
        return new HashSet<>(prefs(c).getStringSet(K_ALLOW, new HashSet<String>()));
    }

    public static Set<String> block(Context c) {
        return new HashSet<>(prefs(c).getStringSet(K_BLOCK, new HashSet<String>()));
    }

    public static void setConfig(Context c, boolean enabled, boolean speak, boolean speakExpense,
                                 List<String> allow, List<String> block) {
        prefs(c).edit()
                .putBoolean(K_ENABLED, enabled)
                .putBoolean(K_SPEAK, speak)
                .putBoolean(K_SPEAK_EXPENSE, speakExpense)
                .putStringSet(K_ALLOW, new HashSet<>(allow == null ? new ArrayList<String>() : allow))
                .putStringSet(K_BLOCK, new HashSet<>(block == null ? new ArrayList<String>() : block))
                .apply();
    }

    // ------------------------------------------------------------------ âm thanh

    /** Khuếch đại: tăng âm lượng media lên tối đa khi đọc, xong thì trả lại như cũ. */
    public static boolean volumeBoost(Context c) {
        return prefs(c).getBoolean(K_BOOST, true);
    }

    /** "female" | "male". */
    public static String voice(Context c) {
        return prefs(c).getString(K_VOICE, "female");
    }

    /** "default" (ting_ting.mp3) | "ting" (chuông tổng hợp) | "none". */
    public static String chime(Context c) {
        return prefs(c).getString(K_CHIME, "default");
    }

    public static float rate(Context c) {
        return prefs(c).getFloat(K_RATE, 1.0f);
    }

    public static float pitch(Context c) {
        return prefs(c).getFloat(K_PITCH, 1.0f);
    }

    public static void setAudio(Context c, boolean boost, String voice, String chime,
                                float rate, float pitch) {
        prefs(c).edit()
                .putBoolean(K_BOOST, boost)
                .putString(K_VOICE, "male".equals(voice) ? "male" : "female")
                .putString(K_CHIME, chime == null ? "default" : chime)
                .putFloat(K_RATE, clamp(rate))
                .putFloat(K_PITCH, clamp(pitch))
                .apply();
    }

    private static float clamp(float v) {
        if (Float.isNaN(v)) return 1.0f;
        return Math.max(0.5f, Math.min(2.0f, v));
    }

    // ------------------------------------------------------------------ chống trùng

    /**
     * true nếu khóa đã xuất hiện trong [windowMs] gần đây. Ghi nhận khóa nếu chưa có.
     * Ngân hàng thường cập nhật lại cùng một thông báo, hoặc gửi cả thông báo app + SMS.
     */
    public static synchronized boolean seenRecently(Context c, String key, long now, long windowMs) {
        JSONObject recent = readObject(c, K_RECENT);
        // Dọn khóa cũ hơn 1 giờ.
        List<String> old = new ArrayList<>();
        Iterator<String> it = recent.keys();
        while (it.hasNext()) {
            String k = it.next();
            if (now - recent.optLong(k, 0) > 3_600_000L) old.add(k);
        }
        for (String k : old) recent.remove(k);
        long last = recent.optLong(key, -1);
        boolean dup = last >= 0 && now - last <= windowMs;
        try {
            recent.put(key, now);
        } catch (JSONException ignored) {
        }
        prefs(c).edit().putString(K_RECENT, recent.toString()).apply();
        return dup;
    }

    // ------------------------------------------------------------------ hàng chờ

    public static synchronized void addPending(Context c, JSONObject event) {
        JSONArray arr = readArray(c, K_PENDING);
        arr.put(event);
        while (arr.length() > MAX_PENDING) arr.remove(0);
        prefs(c).edit().putString(K_PENDING, arr.toString()).apply();
    }

    /** Đọc hàng chờ (không xóa). Flutter lưu vào DB xong mới gọi [ackPending]. */
    public static synchronized JSONArray peekPending(Context c) {
        return readArray(c, K_PENDING);
    }

    /** Xóa các sự kiện đã được Flutter lưu thành công (theo id). */
    public static synchronized void ackPending(Context c, Set<String> ids) {
        if (ids == null || ids.isEmpty()) return;
        JSONArray arr = readArray(c, K_PENDING);
        JSONArray keep = new JSONArray();
        for (int i = 0; i < arr.length(); i++) {
            JSONObject o = arr.optJSONObject(i);
            if (o == null) continue;
            if (!ids.contains(o.optString("id", ""))) keep.put(o);
        }
        prefs(c).edit().putString(K_PENDING, keep.toString()).commit();
    }

    public static synchronized int pendingCount(Context c) {
        return readArray(c, K_PENDING).length();
    }

    // ------------------------------------------------------------------ nhật ký

    public static synchronized void log(Context c, JSONObject entry) {
        JSONArray arr = readArray(c, K_LOG);
        arr.put(entry);
        while (arr.length() > MAX_LOG) arr.remove(0);
        prefs(c).edit().putString(K_LOG, arr.toString()).apply();
    }

    public static synchronized JSONArray getLog(Context c) {
        return readArray(c, K_LOG);
    }

    public static synchronized void clearLog(Context c) {
        prefs(c).edit().remove(K_LOG).apply();
    }

    // ------------------------------------------------------------------ tiện ích

    private static JSONArray readArray(Context c, String key) {
        String s = prefs(c).getString(key, null);
        if (s == null) return new JSONArray();
        try {
            return new JSONArray(s);
        } catch (JSONException e) {
            return new JSONArray();
        }
    }

    private static JSONObject readObject(Context c, String key) {
        String s = prefs(c).getString(key, null);
        if (s == null) return new JSONObject();
        try {
            return new JSONObject(s);
        } catch (JSONException e) {
            return new JSONObject();
        }
    }
}
