package io.smartfinance.smart_finance;

/** Đọc số tiền thành chữ tiếng Việt cho giọng nói: 1500000 -> "một triệu năm trăm nghìn". */
public final class VietnameseNumber {
    private VietnameseNumber() {}

    private static final String[] DIGITS = {
            "không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"};
    private static final String[] UNITS = {"", " nghìn", " triệu", " tỷ", " nghìn tỷ", " triệu tỷ"};

    public static String toWords(long n) {
        if (n == 0) return "không";
        if (n < 0) return "âm " + toWords(-n);
        StringBuilder sb = new StringBuilder();
        int[] groups = new int[6];
        int count = 0;
        long x = n;
        while (x > 0 && count < 6) {
            groups[count++] = (int) (x % 1000);
            x /= 1000;
        }
        boolean started = false;
        for (int i = count - 1; i >= 0; i--) {
            int g = groups[i];
            if (g == 0) continue;
            if (sb.length() > 0) sb.append(' ');
            sb.append(readGroup(g, started)).append(UNITS[i]);
            started = true;
        }
        return sb.toString().trim();
    }

    /** Đọc 3 chữ số; full = true khi phía trước đã có nhóm lớn hơn ("không trăm linh năm"). */
    private static String readGroup(int g, boolean full) {
        int h = g / 100, t = (g / 10) % 10, u = g % 10;
        StringBuilder sb = new StringBuilder();
        if (h > 0 || full) {
            sb.append(DIGITS[h]).append(" trăm");
        }
        if (t == 0) {
            if (u > 0) {
                if (sb.length() > 0) sb.append(" linh");
                sb.append(sb.length() > 0 ? " " : "").append(DIGITS[u]);
            }
            return sb.toString();
        }
        if (sb.length() > 0) sb.append(' ');
        if (t == 1) sb.append("mười");
        else sb.append(DIGITS[t]).append(" mươi");
        if (u == 0) return sb.toString();
        sb.append(' ');
        if (u == 1) sb.append(t == 1 ? "một" : "mốt");
        else if (u == 4) sb.append(t == 1 ? "bốn" : "tư");
        else if (u == 5) sb.append("lăm");
        else sb.append(DIGITS[u]);
        return sb.toString();
    }

    /**
     * Câu đọc khi có giao dịch:
     *  - Chuyển đi: "Bạn đã chuyển đi ... đồng".
     *  - Nhận, nội dung có tên người: "Bạn đã nhận được ... đồng từ Nguyễn Văn A".
     *  - Nhận, nội dung là mã: "Bạn đã nhận được ... đồng".
     */
    public static String announcement(int direction, long amount, String sender) {
        String money = toWords(amount) + " đồng";
        if (direction < 0) return "Bạn đã chuyển đi " + money;
        if (sender != null && !sender.isEmpty()) return "Bạn đã nhận được " + money + " từ " + sender;
        return "Bạn đã nhận được " + money;
    }
}
