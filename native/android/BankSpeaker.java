package io.smartfinance.smart_finance;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Đọc giao dịch bằng giọng tiếng Việt: âm báo "ting ting" -> giọng đọc.
 * Áp dụng cài đặt: giọng Nữ/Nam, tốc độ, cao độ, khuếch đại âm lượng (như app cũ).
 */
public final class BankSpeaker implements TextToSpeech.OnInitListener {
    private static BankSpeaker instance;

    private final Context ctx;
    private final TextToSpeech tts;
    private final Handler main = new Handler(Looper.getMainLooper());
    private boolean ready = false;
    private boolean failed = false;
    private final List<String> queue = new ArrayList<>();
    /** Các câu đang đọc (để trả lại âm lượng khi đọc xong). */
    private final Set<String> speaking = new HashSet<>();

    public static synchronized BankSpeaker get(Context c) {
        if (instance == null || instance.failed) instance = new BankSpeaker(c.getApplicationContext());
        return instance;
    }

    private BankSpeaker(Context c) {
        ctx = c;
        tts = new TextToSpeech(c, this);
    }

    @Override
    public synchronized void onInit(int status) {
        if (status != TextToSpeech.SUCCESS) {
            failed = true;
            for (int i = 0; i < queue.size(); i++) BankAudio.boostEnd(ctx);
            queue.clear();
            return;
        }
        int lang = tts.setLanguage(Locale.forLanguageTag("vi-VN"));
        if (lang == TextToSpeech.LANG_MISSING_DATA || lang == TextToSpeech.LANG_NOT_SUPPORTED) {
            // Máy chưa có giọng tiếng Việt -> dùng giọng mặc định thay vì im lặng.
            tts.setLanguage(Locale.getDefault());
        }
        tts.setAudioAttributes(BankAudio.attributes());
        tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
            @Override
            public void onStart(String id) {}

            @Override
            public void onDone(String id) {
                finished(id);
            }

            @Override
            public void onError(String id) {
                finished(id);
            }
        });
        ready = true;
        for (String s : queue) say(s);
        queue.clear();
    }

    /**
     * "Ting ting" phát NGAY (kể cả khi bộ đọc chưa sẵn sàng), đọc câu sau khi chuông dứt
     * để tiếng chuông không bị giọng đọc lấn át (giống app cũ).
     */
    public void speak(final String text) {
        if (text == null || text.isEmpty()) return;
        BankAudio.boostStart(ctx);
        long d = BankAudio.playChime(ctx, BankStore.chime(ctx));
        long delay = d <= 0 ? 0 : Math.min(d, 3500) + 120;
        main.postDelayed(() -> sayWhenReady(text), delay);
    }

    /** Chỉ phát âm báo (khi tắt giọng đọc). */
    public void chimeOnly() {
        BankAudio.boostStart(ctx);
        long d = BankAudio.playChime(ctx, BankStore.chime(ctx));
        main.postDelayed(() -> BankAudio.boostEnd(ctx), Math.max(d, 0) + 400);
    }

    private synchronized void sayWhenReady(String text) {
        if (failed) {
            BankAudio.boostEnd(ctx);
            return;
        }
        if (!ready) {
            if (queue.size() < 10) queue.add(text);
            else BankAudio.boostEnd(ctx);
            return;
        }
        say(text);
    }

    private synchronized void say(String text) {
        try {
            tts.setSpeechRate(BankStore.rate(ctx));
            tts.setPitch(BankStore.pitch(ctx));
            applyVoice(BankStore.voice(ctx));
        } catch (Throwable ignored) {
        }
        String id = "sf-" + System.nanoTime();
        speaking.add(id);
        int r;
        try {
            r = tts.speak(text, TextToSpeech.QUEUE_ADD, null, id);
        } catch (Throwable t) {
            r = TextToSpeech.ERROR;
        }
        if (r != TextToSpeech.SUCCESS) finished(id);
    }

    private void finished(String id) {
        boolean mine;
        synchronized (this) {
            mine = speaking.remove(id);
        }
        if (mine) BankAudio.boostEnd(ctx);
    }

    /**
     * Chọn giọng Việt theo giới tính mong muốn. Android không công bố giới tính của giọng,
     * nên dựa vào tên giọng (Google: gft/vic/vif ~ nữ, vid/vie ~ nam); không có thì giữ mặc định.
     */
    private void applyVoice(String pref) {
        Set<Voice> voices;
        try {
            voices = tts.getVoices();
        } catch (Throwable t) {
            return;
        }
        if (voices == null) return;
        boolean wantMale = "male".equals(pref);
        Voice best = null;
        int bestScore = Integer.MIN_VALUE;
        for (Voice v : voices) {
            Locale l = v.getLocale();
            if (l == null || !"vi".equals(l.getLanguage())) continue;
            String n = v.getName().toLowerCase(Locale.ROOT);
            boolean female = n.contains("female") || n.contains("gft") || n.contains("vic")
                    || n.contains("vif");
            boolean male = n.contains("#male") || n.contains("_male") || n.contains("-male")
                    || n.contains("vid") || n.contains("vie");
            int score = 0;
            if (wantMale ? male : female) score += 10;
            if (wantMale ? female : male) score -= 5;
            if (!v.isNetworkConnectionRequired()) score += 2;
            Set<String> f = v.getFeatures();
            if (f != null && f.contains("notInstalled")) score -= 20;
            if (score > bestScore) {
                best = v;
                bestScore = score;
            }
        }
        if (best != null && !best.equals(tts.getVoice())) tts.setVoice(best);
    }
}
