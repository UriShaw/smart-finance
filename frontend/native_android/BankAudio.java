package io.smartfinance.smart_finance;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.MediaPlayer;
import android.media.audiofx.LoudnessEnhancer;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

/**
 * Âm báo "ting ting" + khuếch đại âm lượng (giữ tính năng của app cũ).
 * Âm báo mặc định là res/raw/ting_ting.mp3; "ting" là chuông tổng hợp bằng AudioTrack.
 */
public final class BankAudio {
    private BankAudio() {}

    private static final Object LOCK = new Object();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static int savedVolume = -1;
    private static int holders = 0;
    /** Giữ tham chiếu để trình phát không bị GC thu hồi giữa chừng (mất tiếng ting). */
    private static MediaPlayer player;
    private static LoudnessEnhancer enhancer;

    static AudioAttributes attributes() {
        return new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build();
    }

    /** Tăng âm lượng media lên tối đa (nếu bật khuếch đại). Gọi boostEnd() khi đọc xong. */
    static void boostStart(Context c) {
        synchronized (LOCK) {
            if (!BankStore.volumeBoost(c)) return;
            AudioManager am = (AudioManager) c.getSystemService(Context.AUDIO_SERVICE);
            if (am == null) return;
            if (holders == 0) {
                try {
                    savedVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC);
                    am.setStreamVolume(AudioManager.STREAM_MUSIC,
                            am.getStreamMaxVolume(AudioManager.STREAM_MUSIC), 0);
                } catch (Throwable ignored) {
                    // Chế độ Không làm phiền có thể chặn đổi âm lượng.
                    savedVolume = -1;
                }
            }
            holders++;
        }
    }

    static void boostEnd(Context c) {
        synchronized (LOCK) {
            if (holders == 0) return;
            holders--;
            if (holders > 0 || savedVolume < 0) return;
            AudioManager am = (AudioManager) c.getSystemService(Context.AUDIO_SERVICE);
            try {
                if (am != null) am.setStreamVolume(AudioManager.STREAM_MUSIC, savedVolume, 0);
            } catch (Throwable ignored) {
            }
            savedVolume = -1;
        }
    }

    /** Phát âm báo, trả về thời lượng (ms). */
    static long playChime(Context c, String chime) {
        if ("none".equals(chime)) return 0;
        if (!"ting".equals(chime)) {
            long d = playRaw(c);
            if (d >= 0) return d;
        }
        return playSynth();
    }

    private static long playRaw(Context c) {
        int id = c.getResources().getIdentifier("ting_ting", "raw", c.getPackageName());
        if (id == 0) return -1;
        try {
            final MediaPlayer mp = new MediaPlayer();
            mp.setAudioAttributes(attributes());
            AssetFileDescriptor afd = c.getResources().openRawResourceFd(id);
            mp.setDataSource(afd.getFileDescriptor(), afd.getStartOffset(), afd.getLength());
            afd.close();
            mp.prepare();
            mp.setVolume(1f, 1f);
            LoudnessEnhancer le = null;
            if (BankStore.volumeBoost(c)) {
                try {
                    // Khuếch đại thêm ~+9 dB (có giới hạn chống vỡ tiếng) cho "ting ting" to rõ.
                    le = new LoudnessEnhancer(mp.getAudioSessionId());
                    le.setTargetGain(900);
                    le.setEnabled(true);
                } catch (Throwable ignored) {
                    le = null;
                }
            }
            synchronized (LOCK) {
                releasePlayer();
                player = mp;
                enhancer = le;
            }
            mp.setOnCompletionListener(p -> {
                synchronized (LOCK) {
                    if (player == p) releasePlayer();
                    else p.release();
                }
            });
            mp.start();
            return Math.max(0, mp.getDuration());
        } catch (Throwable t) {
            return -1;
        }
    }

    private static void releasePlayer() {
        if (enhancer != null) {
            try {
                enhancer.release();
            } catch (Throwable ignored) {
            }
            enhancer = null;
        }
        if (player != null) {
            try {
                player.release();
            } catch (Throwable ignored) {
            }
            player = null;
        }
    }

    /** Hai nốt chuông trong trẻo (G6 rồi C7), tắt dần. */
    private static long playSynth() {
        final int sr = 44100;
        final int n = (int) (sr * 0.75);
        short[] buf = new short[n];
        final double[][] notes = {{0.0, 1568.0}, {0.17, 2093.0}};
        for (int i = 0; i < n; i++) {
            double t = (double) i / sr;
            double v = 0;
            for (double[] nt : notes) {
                double tt = t - nt[0];
                if (tt < 0) continue;
                double attack = tt < 0.004 ? tt / 0.004 : 1.0;
                double env = Math.exp(-tt * 6.5) * attack;
                double f = nt[1];
                v += env * (Math.sin(2 * Math.PI * f * tt)
                        + 0.35 * Math.sin(2 * Math.PI * f * 2.01 * tt)
                        + 0.12 * Math.sin(2 * Math.PI * f * 3.03 * tt));
            }
            v *= 0.42;
            if (v > 1) v = 1;
            if (v < -1) v = -1;
            buf[i] = (short) (v * 32767);
        }
        try {
            final AudioTrack track;
            if (Build.VERSION.SDK_INT >= 23) {
                track = new AudioTrack.Builder()
                        .setAudioAttributes(attributes())
                        .setAudioFormat(new AudioFormat.Builder()
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .setSampleRate(sr)
                                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                                .build())
                        .setBufferSizeInBytes(n * 2)
                        .setTransferMode(AudioTrack.MODE_STATIC)
                        .build();
            } else {
                track = new AudioTrack(AudioManager.STREAM_MUSIC, sr, AudioFormat.CHANNEL_OUT_MONO,
                        AudioFormat.ENCODING_PCM_16BIT, n * 2, AudioTrack.MODE_STATIC);
            }
            track.write(buf, 0, n);
            track.play();
            final long ms = n * 1000L / sr;
            MAIN.postDelayed(() -> {
                try {
                    track.stop();
                } catch (Throwable ignored) {
                }
                track.release();
            }, ms + 150);
            return ms;
        } catch (Throwable t) {
            return 0;
        }
    }
}
