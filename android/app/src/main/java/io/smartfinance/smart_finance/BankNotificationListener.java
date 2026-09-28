package io.smartfinance.smart_finance;

import android.app.Notification;
import android.content.ComponentName;
import android.content.Context;
import android.os.Build;
import android.os.Bundle;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;

import org.json.JSONException;
import org.json.JSONObject;

import java.security.MessageDigest;

/**
 * Nghe thông báo hệ thống, chỉ xử lý thông báo biến động số dư ngân hàng/ví.
 * Giao dịch hợp lệ -> hàng chờ (Flutter lưu vào DB) + đọc giọng nói ngay.
 * Người dùng phải cấp quyền "Truy cập thông báo" trong Cài đặt Android.
 */
public class BankNotificationListener extends NotificationListenerService {

    /** Cửa sổ chống trùng: cùng ngân hàng + số tiền + số dư. */
    private static final long WINDOW_WITH_BALANCE = 30L * 60 * 1000;
    /** Cửa sổ chống trùng: cùng ngân hàng + số tiền (thông báo app + SMS). */
    private static final long WINDOW_AMOUNT = 3L * 60 * 1000;

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        try {
            if (sbn == null || !BankStore.enabled(this)) return;
            String pkg = sbn.getPackageName();
            if (BankRegistry.OWN_PACKAGE.equals(pkg) || getPackageName().equals(pkg)) return;
            Notification n = sbn.getNotification();
            if (n == null) return;
            if ((n.flags & Notification.FLAG_GROUP_SUMMARY) != 0) return;
            if ((n.flags & Notification.FLAG_ONGOING_EVENT) != 0) return;
            Bundle ex = n.extras;
            if (ex == null) return;
            String title = str(ex.getCharSequence(Notification.EXTRA_TITLE));
            String body = str(ex.getCharSequence(Notification.EXTRA_BIG_TEXT));
            if (body.isEmpty()) body = str(ex.getCharSequence(Notification.EXTRA_TEXT));
            if (body.isEmpty()) {
                CharSequence[] lines = ex.getCharSequenceArray(Notification.EXTRA_TEXT_LINES);
                if (lines != null) {
                    StringBuilder sb = new StringBuilder();
                    for (CharSequence l : lines) sb.append(l).append('\n');
                    body = sb.toString().trim();
                }
            }
            handle(this, pkg, title, body, sbn.getPostTime(), true);
        } catch (Throwable ignored) {
            // Không bao giờ làm sập service vì một thông báo lạ.
        }
    }

    /**
     * Xử lý 1 thông báo. [record] = false khi chỉ thử nhận diện (màn "Thử nhận diện").
     * @return kết quả phân tích.
     */
    static BankParser.Result handle(Context ctx, String pkg, String title, String body,
                                    long postTime, boolean record) {
        BankParser.Result r = BankParser.parse(pkg, title, body,
                BankStore.allow(ctx), BankStore.block(ctx));
        if (!record) return r;

        if (!r.accepted) {
            // Chỉ ghi nhật ký những thông báo có dạng tiền (giúp người dùng tin cậy/chặn app).
            if (r.looksFinancial && !"blocked_app".equals(r.reason) && !"empty".equals(r.reason)) {
                BankStore.log(ctx, logEntry(pkg, title, body, r, postTime, false));
            }
            return r;
        }

        String bankKey = r.bank.toLowerCase();
        String dupKeyBalance = "b|" + bankKey + "|" + r.direction + "|" + r.amount + "|" + r.balance;
        String dupKeyAmount = "a|" + bankKey + "|" + r.direction + "|" + r.amount;
        long now = postTime > 0 ? postTime : System.currentTimeMillis();
        // Có số dư: 2 giao dịch cùng số tiền liên tiếp vẫn khác số dư -> không bị gộp nhầm.
        // Không có số dư: gộp các thông báo trùng số tiền trong 3 phút (app + SMS, cập nhật lại).
        boolean dupAmount = BankStore.seenRecently(ctx, dupKeyAmount, now, WINDOW_AMOUNT);
        boolean dup = r.balance >= 0
                ? BankStore.seenRecently(ctx, dupKeyBalance, now, WINDOW_WITH_BALANCE)
                : dupAmount;
        if (dup) {
            r.reason = "duplicate";
            BankStore.log(ctx, logEntry(pkg, title, body, r, postTime, false));
            return r;
        }

        try {
            JSONObject ev = new JSONObject();
            ev.put("id", sha1(pkg + "|" + dupKeyAmount + "|" + r.balance + "|" + now));
            ev.put("pkg", pkg);
            ev.put("bank", r.bank);
            ev.put("direction", r.direction);
            ev.put("amount", r.amount);
            ev.put("balance", r.balance);
            ev.put("content", r.content);
            ev.put("sender", r.sender);
            ev.put("account", r.account);
            // Thông báo gốc (chỉ lưu trên máy) để xem lại trong Chi tiết giao dịch.
            ev.put("title", clip(title, 200));
            ev.put("text", clip(body, 2000));
            ev.put("postedAt", now);
            ev.put("trust", r.trust);
            BankStore.addPending(ctx, ev);
        } catch (JSONException ignored) {
        }
        BankStore.log(ctx, logEntry(pkg, title, body, r, postTime, true));

        if (BankStore.speak(ctx) && (r.direction > 0 || BankStore.speakExpense(ctx))) {
            BankSpeaker.get(ctx).speak(VietnameseNumber.announcement(r.direction, r.amount, r.sender));
        } else if (r.direction > 0) {
            // Tắt giọng đọc vẫn "ting ting" khi có tiền về.
            BankSpeaker.get(ctx).chimeOnly();
        }
        BankChannel.notifyNewEvent();
        return r;
    }

    private static String clip(String s, int max) {
        if (s == null) return "";
        return s.length() > max ? s.substring(0, max) : s;
    }

    private static JSONObject logEntry(String pkg, String title, String body, BankParser.Result r,
                                       long time, boolean saved) {
        JSONObject o = new JSONObject();
        try {
            o.put("time", time > 0 ? time : System.currentTimeMillis());
            o.put("pkg", pkg == null ? "" : pkg);
            o.put("bank", r.bank);
            o.put("accepted", r.accepted);
            o.put("saved", saved);
            o.put("reason", r.reason);
            o.put("amount", r.amount);
            o.put("direction", r.direction);
            String preview = ((title == null ? "" : title) + " · " + (body == null ? "" : body))
                    .replaceAll("\\d{6,}", "***").replace('\n', ' ');
            if (preview.length() > 140) preview = preview.substring(0, 140) + "…";
            o.put("preview", preview);
        } catch (JSONException ignored) {
        }
        return o;
    }

    @Override
    public void onListenerDisconnected() {
        super.onListenerDisconnected();
        rebind(this);
    }

    static void rebind(Context ctx) {
        if (Build.VERSION.SDK_INT >= 24) {
            try {
                requestRebind(new ComponentName(ctx, BankNotificationListener.class));
            } catch (Throwable ignored) {
            }
        }
    }

    private static String str(CharSequence cs) {
        return cs == null ? "" : cs.toString().trim();
    }

    private static String sha1(String s) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-1");
            byte[] d = md.digest(s.getBytes("UTF-8"));
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (Exception e) {
            return Integer.toHexString(s.hashCode()) + Long.toHexString(System.nanoTime());
        }
    }
}
