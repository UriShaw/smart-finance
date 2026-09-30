package io.smartfinance.smart_finance;

import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Nhận diện thông báo biến động số dư từ mọi ngân hàng / ví Việt Nam.
 *
 * Nguyên tắc chống nhận nhầm:
 *  1. Nguồn: chặn app chat/mạng xã hội/mua sắm; SMS chỉ nhận khi người gửi là ngân hàng;
 *     app lạ chỉ nhận khi có tên ngân hàng + chữ ký giao dịch mạnh (dấu +/- VÀ số dư).
 *  2. Nội dung: loại OTP, khuyến mãi, giao dịch thất bại, nhắc nợ/sao kê, đăng nhập,
 *     nạp/rút ví nội bộ.
 *  3. Số tiền: bỏ qua số tài khoản, mã tham chiếu, ngày giờ, số điện thoại; phân biệt
 *     số tiền giao dịch với số dư.
 *  4. Chiều tiền: ưu tiên dấu +/-; nếu không có thì dùng từ khóa đứng trước nội dung.
 *
 * Thuần Java - chạy được trên JDK để test (native/android/test/BankParserTest.java).
 */
public final class BankParser {
    private BankParser() {}

    public static final int INCOME = 1;
    public static final int EXPENSE = -1;

    /** Mức tin cậy nguồn. */
    public static final int TRUST_NONE = 0, TRUST_LOW = 1, TRUST_MEDIUM = 2, TRUST_HIGH = 3;

    public static final class Result {
        public boolean accepted;
        public String reason = "";
        public long amount;          // đồng
        public int direction;        // INCOME / EXPENSE
        public long balance = -1;    // -1 = không có
        public String bank = "";
        public String content = "";  // nội dung chuyển khoản (đã che số TK)
        /** Tên người chuyển (chỉ tiền vào, nội dung có dạng tên người), "" nếu là mã/không rõ. */
        public String sender = "";
        /** 4 số cuối tài khoản/thẻ nếu thông báo có (để tách số dư từng tài khoản), "" nếu không. */
        public String account = "";
        public int trust = TRUST_NONE;
        /** Văn bản có dạng tiền -> đáng ghi vào nhật ký dù bị từ chối. */
        public boolean looksFinancial;

        Result reject(String r) {
            accepted = false;
            reason = r;
            return this;
        }

        @Override
        public String toString() {
            return (accepted ? "OK " : "NO ") + reason + " amount=" + amount + " dir=" + direction
                    + " bal=" + balance + " bank=" + bank + " acc=" + account + " content=" + content
                    + " sender=" + sender;
        }
    }

    // ------------------------------------------------------------------ bảng từ khóa (ASCII)

    private static final String[] OTP = {
            "otp", "ma xac thuc", "ma xac nhan", "ma kich hoat", "khong chia se", "khong cung cap",
            "verification code", "one-time", "passcode", "smart otp"};

    private static final String[] PROMO = {
            "khuyen mai", "uu dai", "voucher", "giam gia", "giam ngay", "qua tang", "trung thuong",
            "co hoi", "moi ban", "dang ky ngay", "mo the", "khoan vay", "vay tien", "vay nhanh",
            "lai suat", "hoan tien len den", "hoan tien den", "hoan tien toi da", "khi thanh toan",
            "ap dung", "han su dung", "chuong trinh", "tich diem", "doi diem", "cashback up to",
            "flash sale", "mien phi", "nhan ngay", "chi tu"};

    private static final String[] FAILED = {
            "that bai", "khong thanh cong", "bi tu choi", "da huy", "huy giao dich", "dang xu ly",
            "cho xu ly", "cho duyet", "chua thanh cong", "failed", "declined", "khong du so du",
            "vuot han muc"};

    private static final String[] REMINDER = {
            "nhac", "sap den han", "den han", "han thanh toan", "du no", "sao ke",
            "thanh toan toi thieu", "qua han", "can thanh toan", "vui long thanh toan",
            "yeu cau chuyen tien", "yeu cau thanh toan", "de nghi thanh toan", "loi moi"};

    private static final String[] SECURITY = {
            "dang nhap", "thiet bi moi", "mat khau", "doi mat khau", "cap nhat ung dung",
            "sinh trac", "xac minh danh tinh"};

    /** Chuyển tiền nội bộ giữa ngân hàng <-> ví: dễ đếm trùng 2 lần. */
    private static final String[] INTERNAL = {
            "nap tien vao vi", "nap tien thanh cong vao vi", "rut tien ve", "rut tien tu vi",
            "lien ket ngan hang", "nap vi"};

    private static final String[] INCOME_KW = {
            "nhan tien", "da nhan", "vua nhan", "ban nhan", "nhan duoc", "ghi co", "duoc cong",
            "cong tien", "tien vao", "tien ve", "hoan tien", "hoan tra", "credit", "received",
            "incoming", "chuyen den ban", "chuyen cho ban"};

    private static final String[] EXPENSE_KW = {
            "ghi no", "tru tien", "bi tru", "da tru", "thanh toan", "chuyen tien", "chuyen khoan",
            "da chuyen", "rut tien", "tien ra", "debit", "chi tieu", "mua hang", "payment",
            "withdraw", "phi dich vu", "tra gop"};

    /** Nhãn đứng trước nội dung chuyển khoản. */
    private static final Pattern CONTENT_LABEL = Pattern.compile(
            "(?:^|[\\s|.;,(])(nd gd|nd ck|ndck|ndgd|nd|noi dung(?: ck| gd| chuyen khoan)?|loi nhan|mo ta|dien giai|content|description|remark)\\s*[:\\-]\\s*");

    private static final Pattern BALANCE_LABEL = Pattern.compile(
            "(?:^|[^a-z])(so du(?: kha dung| hien tai| cuoi| moi| tai khoan)?|sd(?:c|m|kd)?|balance|bal|kha dung)(?:$|[^a-z])");

    private static final Pattern AMOUNT_LABEL = Pattern.compile(
            "(?:^|[^a-z])(gd|ps|so tien|st|giao dich|amount|tien vao|tien ra|thay doi|bien dong)(?:$|[^a-z])");

    private static final Pattern NON_MONEY_LABEL = Pattern.compile(
            "(?:^|[^a-z])(tk|stk|so tk|tai khoan|account|acc|a/c|the|card|ma gd|ma giao dich|ref|trace|id|so ref|ft|mgd|ma|sdt|dt|hotline|tong dai)\\s*[:.#]?\\s*$");

    /** Số tiền: dấu (tùy chọn) + số có/không phân tách + phần thập phân + đơn vị (tùy chọn). */
    private static final Pattern MONEY = Pattern.compile(
            "([+\\-−–]\\s?)?(\\d{1,3}(?:[.,]\\d{3})+|\\d+)(?:[.,](\\d{1,2}))?(?!\\d)\\s?(vnd|vnđ|dong|d|₫)?(?![a-z0-9])");

    // ------------------------------------------------------------------ API

    public static Result parse(String pkg, String title, String text) {
        return parse(pkg, title, text, Collections.<String>emptySet(), Collections.<String>emptySet());
    }

    public static Result parse(String pkg, String title, String text,
                               Set<String> userAllow, Set<String> userBlock) {
        Result r = new Result();
        String t = title == null ? "" : title.trim();
        String b = text == null ? "" : text.trim();
        String original = t.isEmpty() ? b : (b.isEmpty() ? t : t + "\n" + b);
        if (original.isEmpty()) return r.reject("empty");
        if (original.length() > 2000) original = original.substring(0, 2000);

        String ascii = toAsciiLower(original);   // cùng độ dài với original
        String titleAscii = toAsciiLower(t);
        r.looksFinancial = MONEY.matcher(ascii).find() && ascii.matches("(?s).*\\d.*");

        // ---- 1. Nguồn
        if (pkg != null && userBlock.contains(pkg)) return r.reject("user_blocked");
        if (pkg != null && BankRegistry.BLOCKED_APPS.contains(pkg) && !userAllow.contains(pkg)) {
            return r.reject("blocked_app");
        }
        String brandInText = BankRegistry.findBrand(ascii);
        String known = BankRegistry.knownName(pkg);
        if (pkg != null && userAllow.contains(pkg)) {
            r.trust = TRUST_HIGH;
            r.bank = known != null ? known : (brandInText != null ? brandInText : pkg);
        } else if (known != null) {
            r.trust = TRUST_HIGH;
            r.bank = known;
        } else if (pkg != null && BankRegistry.SMS_APPS.contains(pkg)) {
            String sender = BankRegistry.findBrand(titleAscii);
            if (sender == null) {
                // Một số máy đặt tên người gửi ở đầu nội dung: "VCB: TK ..."
                String head = ascii.length() > 24 ? ascii.substring(0, 24) : ascii;
                sender = BankRegistry.findBrand(head);
            }
            if (sender == null) return r.reject("sms_not_bank");
            r.trust = TRUST_MEDIUM;
            r.bank = sender;
        } else if (BankRegistry.looksLikeBankPackage(pkg)) {
            r.trust = TRUST_MEDIUM;
            r.bank = brandInText != null ? brandInText : shortPkg(pkg);
        } else {
            if (brandInText == null) return r.reject("unknown_app");
            r.trust = TRUST_LOW;
            r.bank = brandInText;
        }

        // ---- 2. Nội dung bị loại (chỉ xét phần trước nhãn nội dung CK để người gửi
        //         ghi "nhac no"/"otp" trong lời nhắn không làm hỏng giao dịch thật)
        int contentStart = findContentStart(ascii);
        String head = contentStart >= 0 ? ascii.substring(0, contentStart) : ascii;
        if (containsAny(head, OTP)) return r.reject("otp");
        if (containsAny(head, FAILED)) return r.reject("failed");
        if (containsAny(head, SECURITY)) return r.reject("security");
        if (containsAny(head, INTERNAL)) return r.reject("internal_transfer");

        // ---- 3. Số tiền & số dư
        List<Money> monies = findMoney(ascii, contentStart);
        Money amount = null;
        Money balance = null;
        for (Money m : monies) {
            if (m.isBalance) {
                if (balance == null) balance = m;
                continue;
            }
            if (amount == null || m.score > amount.score) amount = m;
        }
        boolean hasSign = amount != null && amount.sign != 0;
        // Khuyến mãi / nhắc nợ: chỉ bỏ qua khi có đủ dấu +/- VÀ số dư (giao dịch thật).
        boolean strong = hasSign && balance != null;
        if (!strong && containsAny(head, PROMO)) return r.reject("promotion");
        if (!strong && containsAny(head, REMINDER)) return r.reject("reminder");
        if (amount == null) return r.reject(balance != null ? "balance_only" : "no_amount");
        if (amount.value <= 0 || amount.value >= 10_000_000_000_000L) return r.reject("bad_amount");

        // ---- 4. Chiều tiền
        int dir = amount.sign;
        if (dir == 0) dir = directionByKeyword(head);
        if (dir == 0) return r.reject("unknown_direction");

        // ---- 5. Chữ ký giao dịch
        boolean txWords = AMOUNT_LABEL.matcher(head).find() || containsAny(head, INCOME_KW)
                || containsAny(head, EXPENSE_KW);
        if (r.trust == TRUST_LOW && !(hasSign && balance != null)) return r.reject("weak_signature");
        if (r.trust == TRUST_MEDIUM && !(hasSign || balance != null || (txWords && amount.hasCurrency))) {
            return r.reject("weak_signature");
        }
        if (r.trust == TRUST_HIGH && !(hasSign || balance != null || txWords || amount.hasCurrency)) {
            return r.reject("weak_signature");
        }

        r.accepted = true;
        r.reason = "ok";
        r.amount = amount.value;
        r.direction = dir;
        r.balance = balance == null ? -1 : balance.value;
        r.content = contentStart >= 0 ? extractContent(original, contentStart) : "";
        r.account = extractAccount(head);
        if (dir > 0) {
            // Ưu tiên phần nội dung CK; không có nhãn ND thì tìm trong thân thông báo.
            String contentRaw = contentStart >= 0 ? original.substring(contentStart) : b;
            r.sender = SenderName.extract(contentRaw);
        }
        return r;
    }

    // ------------------------------------------------------------------ tài khoản

    /** "TK 0011000123456", "TK VCB 0011..789", "tk 03xxx789", "the *1234", "a/c: 19031234567". */
    private static final Pattern ACCOUNT = Pattern.compile(
            "(?:^|[^a-z0-9])(?:so tk|stk|tk|tai khoan|account|acc|a/c|the)\\s*(?:[a-z]{2,6}\\s+)?[:.#]?\\s*"
                    + "([0-9][0-9x*.]{1,}[0-9]|[x*.]+[0-9]{3,})");

    static String extractAccount(String ascii) {
        Matcher m = ACCOUNT.matcher(ascii);
        while (m.find()) {
            String raw = m.group(1);
            // "1.234.567" / theo sau là VND -> số tiền, không phải số tài khoản.
            if (raw.matches("\\d{1,3}(\\.\\d{3})+")) continue;
            String after = ascii.substring(m.end(1), Math.min(ascii.length(), m.end(1) + 5)).trim();
            if (after.startsWith("vnd") || after.startsWith("d") || after.startsWith("dong")) continue;
            String digits = raw.replaceAll("[^0-9]", "");
            if (digits.length() < 3) continue;
            return digits.length() > 4 ? digits.substring(digits.length() - 4) : digits;
        }
        return "";
    }

    // ------------------------------------------------------------------ số tiền

    static final class Money {
        long value;
        int sign;
        boolean hasCurrency;
        boolean isBalance;
        int score;
        int start;
    }

    private static List<Money> findMoney(String ascii, int contentStart) {
        List<Money> out = new ArrayList<>();
        // Cụm "biến động số dư" là tiêu đề, không phải nhãn số dư.
        String scan = ascii.replace("bien dong so du", "bien dong      ")
                .replace("thong bao so du", "thong bao      ");
        Matcher m = MONEY.matcher(scan);
        int limit = contentStart >= 0 ? contentStart : scan.length();
        while (m.find()) {
            int s = m.start();
            if (s >= limit) break;                                 // bỏ số trong lời nhắn
            String signStr = m.group(1);
            String intPart = m.group(2);
            String unit = m.group(4);
            int numStart = m.start(2);
            char before = numStart > 0 ? scan.charAt(numStart - 1) : ' ';
            char after = m.end(2) < scan.length() ? scan.charAt(m.end(2)) : ' ';
            int sign = 0;
            if (signStr != null) {
                char prev = s > 0 ? scan.charAt(s - 1) : ' ';
                // "23-09-2026": dấu '-' dính sau chữ số -> không phải dấu âm.
                if (!Character.isLetterOrDigit(prev)) {
                    sign = signStr.charAt(0) == '+' ? 1 : -1;
                }
            }
            // Ngày/giờ/phân số: 23/09, 20:15, 10.5.2026
            if (before == '/' || before == ':' || after == '/' || after == ':') continue;
            if (sign == 0 && (before == '-' && numStart >= 2 && Character.isDigit(scan.charAt(numStart - 2)))) continue;
            if (Character.isLetter(before)) continue;             // FT26266123, MBVCB123
            if (m.group(3) != null && m.group(3).length() == 1 && unit == null && sign == 0) continue; // 1.5

            String look = scan.substring(Math.max(0, s - 28), s);
            boolean hasCurrency = unit != null && !(unit.equals("d") && intPart.length() < 2);
            boolean nonMoneyLabel = NON_MONEY_LABEL.matcher(look).find();
            boolean amountLabel = lastMatchEnd(AMOUNT_LABEL, look) >= 0;
            int balEnd = lastMatchEnd(BALANCE_LABEL, look);
            int amtEnd = lastMatchEnd(AMOUNT_LABEL, look);
            boolean isBalance = sign == 0 && balEnd >= 0 && balEnd >= amtEnd;
            boolean separated = intPart.indexOf('.') >= 0 || intPart.indexOf(',') >= 0;

            if (nonMoneyLabel && !hasCurrency && sign == 0) continue; // số TK / mã GD
            if (!hasCurrency && sign == 0 && !amountLabel && !isBalance) continue;
            if (!separated && !hasCurrency && intPart.length() > 12) continue;
            if (!separated && intPart.length() >= 9 && intPart.startsWith("0") && !hasCurrency) continue; // SĐT

            long value = parseInt(intPart);
            if (value <= 0) continue;
            // "12,5 tr" hiếm gặp trong thông báo ngân hàng -> bỏ qua đơn vị chữ.
            Money mo = new Money();
            mo.value = value;
            mo.sign = sign;
            mo.hasCurrency = hasCurrency;
            mo.isBalance = isBalance;
            mo.start = s;
            mo.score = (sign != 0 ? 100 : 0) + (amountLabel ? 40 : 0) + (hasCurrency ? 20 : 0)
                    + (separated ? 5 : 0) - out.size();
            out.add(mo);
        }
        return out;
    }

    private static long parseInt(String intPart) {
        String digits = intPart.replace(".", "").replace(",", "");
        if (digits.length() > 15) return -1;
        try {
            return Long.parseLong(digits);
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    private static int lastMatchEnd(Pattern p, String s) {
        Matcher m = p.matcher(s);
        int end = -1;
        while (m.find()) end = m.end(1);
        return end;
    }

    // ------------------------------------------------------------------ chiều tiền & nội dung

    private static int directionByKeyword(String head) {
        int inc = firstIndex(head, INCOME_KW);
        int exp = firstIndex(head, EXPENSE_KW);
        if (inc < 0 && exp < 0) return 0;
        if (inc >= 0 && (exp < 0 || inc <= exp)) return INCOME;
        return EXPENSE;
    }

    private static int findContentStart(String ascii) {
        Matcher m = CONTENT_LABEL.matcher(ascii);
        return m.find() ? m.end() : -1;
    }

    private static String extractContent(String original, int start) {
        if (start >= original.length()) return "";
        String c = original.substring(start);
        int cut = c.length();
        for (String stop : new String[]{"\n", "|", " SD ", " SD:", "Số dư", "So du", ". Ref", " Ref "}) {
            int i = c.indexOf(stop);
            if (i >= 0 && i < cut) cut = i;
        }
        c = c.substring(0, cut).trim();
        // Che số tài khoản / số thẻ / SĐT trong nội dung.
        c = c.replaceAll("\\d{6,}", "***");
        if (c.length() > 120) c = c.substring(0, 120);
        return c.replaceAll("[\\s.;,]+$", "");
    }

    // ------------------------------------------------------------------ tiện ích

    /** Bỏ dấu tiếng Việt, chữ thường; GIỮ NGUYÊN độ dài để ánh xạ vị trí. */
    public static String toAsciiLower(String s) {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder(s.length());
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == 'đ' || c == 'Đ') {
                sb.append('d');
                continue;
            }
            if (c < 128) {
                sb.append(Character.toLowerCase(c));
                continue;
            }
            String d = Normalizer.normalize(String.valueOf(c), Normalizer.Form.NFD);
            char base = d.isEmpty() ? c : d.charAt(0);
            sb.append(Character.toLowerCase(base));
        }
        return sb.toString();
    }

    private static boolean containsAny(String s, String[] words) {
        return firstIndex(s, words) >= 0;
    }

    private static int firstIndex(String s, String[] words) {
        int best = -1;
        for (String w : words) {
            int i = indexOfWord(s, w);
            if (i >= 0 && (best < 0 || i < best)) best = i;
        }
        return best;
    }

    /** Tìm từ/cụm từ đứng riêng (không nằm giữa một từ khác). */
    private static int indexOfWord(String s, String w) {
        int from = 0;
        while (true) {
            int i = s.indexOf(w, from);
            if (i < 0) return -1;
            boolean okL = i == 0 || !Character.isLetterOrDigit(s.charAt(i - 1));
            int e = i + w.length();
            boolean okR = e >= s.length() || !Character.isLetterOrDigit(s.charAt(e));
            if (okL && okR) return i;
            from = i + 1;
        }
    }

    private static String shortPkg(String pkg) {
        if (pkg == null) return "";
        String[] parts = pkg.split("\\.");
        return parts.length == 0 ? pkg : parts[parts.length - 1];
    }
}
