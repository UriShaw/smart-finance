package io.smartfinance.smart_finance;

import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Danh sách nguồn thông báo: app ngân hàng/ví đã biết, app SMS, app bị chặn
 * (chat, mạng xã hội, mua sắm...) và từ khóa thương hiệu ngân hàng.
 * Thuần Java (không phụ thuộc Android) để test được bằng JDK.
 */
public final class BankRegistry {
    private BankRegistry() {}

    public static final String OWN_PACKAGE = "io.smartfinance.smart_finance";

    /** Package app ngân hàng / ví điện tử -> tên hiển thị. */
    public static final Map<String, String> KNOWN_APPS;
    static {
        Map<String, String> m = new LinkedHashMap<>();
        m.put("com.VCB", "Vietcombank");
        m.put("com.vietinbank.ipay", "VietinBank");
        m.put("com.vnpay.bidv", "BIDV");
        m.put("com.vnpay.Agribank3g", "Agribank");
        m.put("vn.com.techcombank.bb.app", "Techcombank");
        m.put("com.mbmobile", "MB Bank");
        m.put("mobile.acb.com.vn", "ACB");
        m.put("com.vnpay.vpbankonline", "VPBank");
        m.put("com.vpbank.neo", "VPBank");
        m.put("com.tpb.mb.gprsandroid", "TPBank");
        m.put("com.sacombank.ewallet", "Sacombank");
        m.put("com.sacombank.mbanking", "Sacombank");
        m.put("com.vnpay.hdbank", "HDBank");
        m.put("vn.shb.mbanking", "SHB");
        m.put("vn.shb.saha.mbanking", "SHB");
        m.put("vn.com.msb.smartBanking", "MSB");
        m.put("vn.com.ocb.awe", "OCB");
        m.put("vn.com.seabank.mb1", "SeABank");
        m.put("com.vib.myvib2", "VIB");
        m.put("com.vnpay.EximBankOmni", "Eximbank");
        m.put("io.lifestyle.plus", "Timo");
        m.put("xyz.be.cake", "Cake");
        m.put("com.shinhan.global.vn.bank", "Shinhan Bank");
        m.put("com.mservice.momotransfer", "MoMo");
        m.put("vn.com.vng.zalopay", "ZaloPay");
        m.put("com.bplus.vtpay", "Viettel Money");
        KNOWN_APPS = Collections.unmodifiableMap(m);
    }

    /** App tin nhắn SMS: chỉ nhận khi người gửi/nội dung là ngân hàng. */
    public static final Set<String> SMS_APPS = set(
            "com.google.android.apps.messaging",
            "com.android.mms",
            "com.android.messaging",
            "com.samsung.android.messaging",
            "com.oneplus.mms",
            "com.coloros.mms",
            "com.microsoft.android.smsorganizer",
            "com.truecaller");

    /**
     * Không bao giờ đọc: chat, mạng xã hội, email, trình duyệt, mua sắm, hệ thống.
     * (Tránh người khác nhắn "+500.000đ" bị ghi nhầm.)
     */
    public static final Set<String> BLOCKED_APPS = set(
            OWN_PACKAGE,
            "android", "com.android.systemui", "com.android.vending",
            "com.zing.zalo", "com.facebook.orca", "com.facebook.katana", "com.facebook.lite",
            "com.facebook.mlite", "org.telegram.messenger", "org.thunderdog.challegram",
            "com.whatsapp", "com.whatsapp.w4b", "com.viber.voip", "com.skype.raider",
            "com.discord", "com.instagram.android", "com.twitter.android", "com.snapchat.android",
            "jp.naver.line.android", "com.kakao.talk", "com.tencent.mm",
            "com.google.android.gm", "com.microsoft.office.outlook", "com.samsung.android.email.provider",
            "com.android.chrome", "org.mozilla.firefox", "com.microsoft.emmx", "com.coccoc.trinhduyet",
            "com.google.android.youtube", "com.ss.android.ugc.trill", "com.zhiliaoapp.musically",
            "com.shopee.vn", "com.lazada.android", "vn.tiki.app", "com.ss.android.ugc.aweme",
            "com.grabtaxi.passenger", "com.gojek.app", "xyz.be.customer",
            "com.google.android.apps.photos", "com.google.android.calendar");

    /** Từ khóa thương hiệu (ASCII, chữ thường). Từ ngắn phải đứng riêng. */
    private static final String[][] BRANDS = {
            {"vietcombank", "Vietcombank"}, {"vcb", "Vietcombank"},
            {"vietinbank", "VietinBank"}, {"bidv", "BIDV"}, {"agribank", "Agribank"},
            {"techcombank", "Techcombank"}, {"tcb", "Techcombank"},
            {"mbbank", "MB Bank"}, {"mb bank", "MB Bank"}, {"acb", "ACB"},
            {"vpbank", "VPBank"}, {"tpbank", "TPBank"}, {"sacombank", "Sacombank"},
            {"hdbank", "HDBank"}, {"shb", "SHB"}, {"msb", "MSB"}, {"ocb", "OCB"},
            {"seabank", "SeABank"}, {"vib", "VIB"}, {"eximbank", "Eximbank"},
            {"lpbank", "LPBank"}, {"lienvietpostbank", "LPBank"}, {"namabank", "Nam A Bank"},
            {"nam a bank", "Nam A Bank"}, {"bvbank", "BVBank"}, {"timo", "Timo"},
            {"cake", "Cake"}, {"pvcombank", "PVcomBank"}, {"abbank", "ABBANK"},
            {"bac a bank", "BAC A BANK"}, {"bacabank", "BAC A BANK"}, {"scb", "SCB"},
            {"ncb", "NCB"}, {"vietabank", "VietABank"}, {"pgbank", "PGBank"},
            {"saigonbank", "Saigonbank"}, {"vietbank", "Vietbank"}, {"baovietbank", "BaoViet Bank"},
            {"gpbank", "GPBank"}, {"oceanbank", "OceanBank"}, {"cbbank", "CBBank"},
            {"kienlongbank", "KienlongBank"}, {"vikki", "Vikki"}, {"shinhan", "Shinhan Bank"},
            {"woori", "Woori Bank"}, {"hsbc", "HSBC"}, {"standard chartered", "Standard Chartered"},
            {"uob", "UOB"}, {"citibank", "Citibank"}, {"public bank", "Public Bank"},
            {"momo", "MoMo"}, {"zalopay", "ZaloPay"}, {"shopeepay", "ShopeePay"},
            {"viettel money", "Viettel Money"}, {"viettelpay", "Viettel Money"},
            {"vnpay", "VNPAY"}, {"vnpt pay", "VNPT Money"}, {"vnpt money", "VNPT Money"},
    };

    private static final Map<String, Pattern> BRAND_PATTERNS = new HashMap<>();
    static {
        for (String[] b : BRANDS) {
            BRAND_PATTERNS.put(b[0], Pattern.compile("(^|[^a-z0-9])" + Pattern.quote(b[0]) + "($|[^a-z0-9])"));
        }
    }

    /** Tìm thương hiệu ngân hàng trong đoạn văn bản ASCII chữ thường. */
    public static String findBrand(String asciiLower) {
        if (asciiLower == null) return null;
        for (String[] b : BRANDS) {
            Matcher m = BRAND_PATTERNS.get(b[0]).matcher(asciiLower);
            if (m.find()) return b[1];
        }
        return null;
    }

    /** Package trông giống app ngân hàng/ví (bao phủ ngân hàng chưa có trong danh sách). */
    public static boolean looksLikeBankPackage(String pkg) {
        if (pkg == null) return false;
        String p = pkg.toLowerCase();
        return p.contains("bank") || p.contains("banking") || p.contains("vnpay")
                || p.contains("ipay") || p.contains("ewallet") || p.contains(".mb.")
                || p.endsWith(".mb") || p.contains("wallet") || p.contains("momo");
    }

    public static String knownName(String pkg) {
        return pkg == null ? null : KNOWN_APPS.get(pkg);
    }

    private static Set<String> set(String... items) {
        return Collections.unmodifiableSet(new HashSet<>(java.util.Arrays.asList(items)));
    }
}
