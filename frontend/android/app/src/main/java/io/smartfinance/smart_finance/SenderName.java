package io.smartfinance.smart_finance;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Tìm tên người chuyển trong nội dung chuyển khoản.
 * Nội dung có dạng tên người ("NGUYEN VAN A chuyen tien", "CK tu Tran Thi B") -> trả về tên
 * để đọc "Bạn đã nhận được ... từ Nguyễn Văn A". Nội dung là mã ("FT24265ABC123",
 * "MBVCB.123456.QR") -> trả về "" (chỉ đọc "Bạn đã nhận được ...").
 * Quy tắc: 2-5 từ liền nhau, chỉ chữ cái, từ đầu là họ Việt Nam phổ biến, không chứa số.
 */
public final class SenderName {
    private SenderName() {}

    static final Set<String> SURNAMES = new HashSet<>(Arrays.asList(
            "nguyen", "tran", "le", "pham", "hoang", "huynh", "phan", "vu", "vo", "dang", "bui",
            "do", "ho", "ngo", "duong", "ly", "truong", "dinh", "mai", "ha", "cao", "lam", "trinh",
            "luong", "doan", "ta", "chu", "kieu", "quach", "thai", "luu", "ton", "tang", "vuong",
            "hua", "khuc", "au", "ong", "mac", "giang", "nghiem", "tong", "diep", "thach", "trieu",
            "tieu", "khong", "banh", "chau", "han", "kim", "lieu", "nong", "phung", "uong", "tat",
            "ninh", "thieu", "bach", "dam"));

    /** Từ không thể là một phần của tên (động từ, đơn vị, từ ngân hàng...). */
    static final Set<String> STOP = new HashSet<>(Arrays.asList(
            "chuyen", "tien", "khoan", "ck", "ct", "gd", "tu", "den", "cho", "thanh", "toan", "tt",
            "nap", "rut", "vnd", "dong", "sd", "tk", "stk", "luc", "ref", "nd", "so", "du", "qua",
            "tai", "ngan", "hang", "bank", "the", "phi", "tro", "gui", "nhan", "tra", "no", "luong",
            "thuong", "mua", "ban", "hoan", "don", "ma", "id", "trans", "transfer", "from",
            "to", "payment", "momo", "vi", "zalopay", "qr", "pay", "fee", "ibft", "napas", "ft",
            "mbvcb", "vcb", "bidv", "acb", "mb", "tcb", "vpb", "tpb", "shb", "msb", "ocb", "vib",
            "hdb", "gio", "ngay", "thang", "nam", "va", "voi", "cua", "tren", "duoi", "dau", "cuoi",
            "an", "uong", "com", "sang", "trua", "toi", "hoc", "phi", "dien", "nuoc", "internet",
            "mang", "online", "shopee", "lazada", "tiki", "grab", "be", "gojek", "hd", "sp", "dh",
            "order", "bill", "invoice", "cam", "on", "chuc", "mung", "sinh", "nhat", "ok", "lai",
            "tet", "le", "xin", "vay", "muon", "tro", "giup", "coc", "dat", "thue", "nha", "phong"));

    private static final Pattern TOKEN = Pattern.compile("[^\\s.,;:_/|()\\[\\]\\-+*#@!?\"']+");

    public static String extract(String text) {
        if (text == null || text.isEmpty()) return "";
        String ascii = BankParser.toAsciiLower(text);   // cùng độ dài với text
        List<int[]> spans = new ArrayList<>();
        List<String> words = new ArrayList<>();
        Matcher m = TOKEN.matcher(ascii);
        while (m.find()) {
            spans.add(new int[]{m.start(), m.end()});
            words.add(m.group());
        }
        for (int i = 0; i < words.size(); i++) {
            if (!SURNAMES.contains(words.get(i))) continue;
            // Họ phải là một từ riêng, không dính liền mã (VD "LE123").
            int j = i + 1;
            while (j < words.size() && j - i < 5 && isNameWord(words.get(j))
                    && adjacent(ascii, spans.get(j - 1), spans.get(j))) {
                j++;
            }
            if (j - i >= 2) {
                String raw = text.substring(spans.get(i)[0], spans.get(j - 1)[1]);
                return titleCase(raw.replaceAll("\\s+", " ").trim());
            }
        }
        return "";
    }

    private static boolean isNameWord(String w) {
        return w.length() <= 7 && w.matches("[a-z]+") && !STOP.contains(w);
    }

    /** Hai từ chỉ cách nhau bởi khoảng trắng (không qua dấu chấm/gạch của mã giao dịch). */
    private static boolean adjacent(String s, int[] a, int[] b) {
        for (int k = a[1]; k < b[0]; k++) {
            if (!Character.isWhitespace(s.charAt(k))) return false;
        }
        return true;
    }

    private static String titleCase(String s) {
        StringBuilder sb = new StringBuilder(s.length());
        boolean start = true;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (Character.isWhitespace(c)) {
                start = true;
                sb.append(' ');
            } else {
                sb.append(start ? Character.toUpperCase(c) : Character.toLowerCase(c));
                start = false;
            }
        }
        return sb.toString();
    }
}
