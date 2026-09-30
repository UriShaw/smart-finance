package io.smartfinance.smart_finance;

/**
 * Test bộ nhận diện bằng JDK thuần (không cần Android):
 *   javac -d out native/android/Bank*.java native/android/VietnameseNumber.java native/android/test/BankParserTest.java
 *   java -cp out io.smartfinance.smart_finance.BankParserTest
 */
public final class BankParserTest {
    static int pass = 0, fail = 0;

    static void ok(String name, String pkg, String title, String text, int dir, long amount, long balance) {
        BankParser.Result r = BankParser.parse(pkg, title, text);
        boolean good = r.accepted && r.direction == dir && r.amount == amount
                && (balance == -2 || r.balance == balance);
        report(name, good, r);
    }

    static void no(String name, String pkg, String title, String text, String reason) {
        BankParser.Result r = BankParser.parse(pkg, title, text);
        boolean good = !r.accepted && (reason == null || reason.equals(r.reason));
        report(name, good, r);
    }

    static void report(String name, boolean good, Object r) {
        if (good) pass++;
        else fail++;
        System.out.println((good ? "  PASS " : "  FAIL ") + name + " -> " + r);
    }

    static void eq(String name, String a, String b) {
        report(name + " [" + a + "]", a.equals(b), b);
    }

    public static void main(String[] args) {
        final String SMS = "com.google.android.apps.messaging";
        System.out.println("== Chấp nhận");
        ok("VCB app", "com.VCB", "Thông báo biến động số dư",
                "TK 1234567890 +500,000 VND lúc 23-09-2026 20:15:01. SD 12,345,678 VND. Ref MBVCB.123456789.NGUYEN VAN A chuyen tien",
                1, 500000, 12345678);
        ok("VCB SMS", SMS, "Vietcombank",
                "SD TK 0071000123456 -150,000VND luc 23-09-2026 10:20:30. SD 1,234,567VND. Ref 123456.thanh toan QR",
                -1, 150000, 1234567);
        ok("Techcombank", "vn.com.techcombank.bb.app", "Techcombank",
                "Tài khoản 19036xxxxxx: +2,000,000 VND\nSố dư: 5,500,000 VND\nNội dung: LUONG THANG 9",
                1, 2000000, 5500000);
        ok("MB pipe", "com.mbmobile", "MB Bank",
                "TK 0123xxx789|GD: -35,000VND 23/09/26 12:01 |SD: 1,200,000VND|ND: MBVCB ca phe",
                -1, 35000, 1200000);
        ok("BIDV multi-line", "com.vnpay.bidv", "BIDV",
                "Thời gian: 23/09/2026 08:30\nTài khoản: 12510000123456\nGiao dịch: +1.000.000 VND\nSố dư hiện tại: 3.500.000 VND\nNội dung: tien an",
                1, 1000000, 3500000);
        ok("VietinBank", "com.vietinbank.ipay", "Biến động số dư",
                "Biến động số dư: TK 101012345678 | -200,000VND | SD: 800,000VND | ND: thanh toan hoa don dien",
                -1, 200000, 800000);
        ok("ACB space sign", SMS, "ACB",
                "ACB: TK 12345(VND) - 60,000 luc 09:15 23/09. So du 1,000,000. GD: NAP TIEN DIEN THOAI",
                -1, 60000, 1000000);
        ok("MoMo nhận", "com.mservice.momotransfer", "Nhận tiền thành công",
                "Bạn vừa nhận 100.000đ từ NGUYEN VAN B. Lời nhắn: tra tien com",
                1, 100000, -1);
        ok("MoMo thanh toán", "com.mservice.momotransfer", "Thanh toán thành công",
                "Thanh toán thành công 45.000đ cho Highlands Coffee",
                -1, 45000, -1);
        ok("Decimals", "com.VCB", "VCB", "TK 0071 +1,500,000.00 VND. SD 9,000,000.00 VND", 1, 1500000, 9000000);
        ok("Bị trừ", "vn.com.techcombank.bb.app", "Techcombank",
                "Số tiền: 250.000 VND. Tài khoản đã bị trừ. Nội dung: mua sach", -1, 250000, -2);
        ok("Unknown bank pkg", "vn.com.kienlongbank.mobile", "KienlongBank",
                "TK 123456789 +300.000 VND. SD 2.300.000 VND", 1, 300000, 2300000);
        ok("Unknown app brand + strong", "com.example.bankclone", "Techcombank",
                "+1,000,000 VND. Số dư 3,000,000 VND", 1, 1000000, 3000000);
        ok("Unicode minus", "com.VCB", "VCB", "TK 0071 −50.000 VND. SD 1.000.000 VND", -1, 50000, 1000000);
        ok("OTP word in content", "com.mbmobile", "MB",
                "GD: +20,000VND. SD: 520,000VND. ND: gui ma otp cho em", 1, 20000, 520000);
        ok("Cake no balance", "xyz.be.cake", "Cake", "+30.000 đ từ TRAN THI C - chuyen tien an trua", 1, 30000, -1);
        ok("Đã chuyển", "com.VCB", "Vietcombank", "Bạn đã chuyển 200.000đ đến NGUYEN VAN A", -1, 200000, -1);
        ok("Nhận CK", "com.vnpay.hdbank", "HDBank", "Nhận tiền chuyển khoản 500.000 VND từ LE VAN D", 1, 500000, -1);
        ok("Promo word in content", "com.VCB", "VCB", "TK 0071 +500,000 VND. SD 1,000,000 VND. ND: uu dai sinh nhat", 1, 500000, 1000000);
        ok("Timo", "io.lifestyle.plus", "Timo", "Tài khoản của bạn vừa được cộng 75.000 VND.", 1, 75000, -1);

        System.out.println("== Từ chối");
        no("OTP", "com.VCB", "Vietcombank",
                "Mã OTP của bạn là 123456, không chia sẻ cho bất kỳ ai. GD chuyển tiền 5,000,000 VND", "otp");
        no("Promo", "com.mservice.momotransfer", "Ưu đãi",
                "Ưu đãi: Hoàn tiền 50.000đ khi thanh toán hóa đơn điện", "promotion");
        no("Zalo chat", "com.zing.zalo", "Anh Nam", "+500,000 VND nhé", "blocked_app");
        no("Failed", "com.VCB", "Vietcombank",
                "Giao dịch chuyển tiền 1,000,000 VND không thành công", "failed");
        no("Credit statement", "com.vnpay.bidv", "BIDV",
                "Sao kê thẻ tín dụng tháng 9: dư nợ 5,000,000 VND. Hạn thanh toán 15/10", "reminder");
        no("Login", "com.VCB", "Vietcombank", "Tài khoản của bạn vừa đăng nhập trên thiết bị mới", "security");
        no("Shop app", "com.shopee.vn", "Shopee", "Đơn hàng 250.000đ đã giao thành công", "blocked_app");
        no("Unknown app no brand", "com.random.game", "Game", "Bạn nhận được +5,000 xu", "unknown_app");
        no("Balance only", "com.VCB", "Vietcombank", "Số dư tài khoản của bạn là 5,000,000 VND", null);
        no("SMS not bank", SMS, "0912345678", "Chuyen cho t 200,000 VND nhe", "sms_not_bank");
        no("Wallet topup", "com.mservice.momotransfer", "MoMo", "Nạp tiền vào ví thành công 200.000đ", "internal_transfer");
        no("Unknown app weak", "com.example.news", "Tin tức", "Vietcombank tăng lãi suất 0,5% cho khoản 1.000.000 VND", null);
        no("Promo with sign", "com.VCB", "Vietcombank", "Nhận ngay +50.000đ khi mở thẻ tín dụng VCB", "promotion");
        no("Reminder with sign", "com.vnpay.bidv", "BIDV", "Nhắc nợ: khoản vay cần thanh toán -2.000.000 VND", null);
        no("Account number only", "com.VCB", "VCB", "Tài khoản 0071000123456 đã được cập nhật thông tin", null);
        no("Game coins in bank-like pkg", "com.bankgame.fun", "Game", "Chúc mừng! Bạn có 5000 điểm", null);

        System.out.println("== Đọc số");
        eq("500000", "năm trăm nghìn", VietnameseNumber.toWords(500000));
        eq("1500000", "một triệu năm trăm nghìn", VietnameseNumber.toWords(1500000));
        eq("105000", "một trăm linh năm nghìn", VietnameseNumber.toWords(105000));
        eq("21500", "hai mươi mốt nghìn năm trăm", VietnameseNumber.toWords(21500));
        eq("15", "mười lăm", VietnameseNumber.toWords(15));
        eq("2005000", "hai triệu không trăm linh năm nghìn", VietnameseNumber.toWords(2005000));
        eq("1000000000", "một tỷ", VietnameseNumber.toWords(1000000000L));

        System.out.println("== Số tài khoản (tách số dư từng TK)");
        String[][] acc = {
            {"com.VCB", "TK 1234567890 +500,000 VND. SD 12,345,678 VND. Ref abc", "7890"},
            {SMS, "SD TK 0071000123456 -150,000VND luc 23-09-2026. SD 1,234,567VND", "3456"},
            {"com.mbmobile", "TK 0123xxx789|GD: -35,000VND|SD: 1,200,000VND|ND: ca phe", "3789"},
            {"vn.com.techcombank.bb.app", "Tài khoản 19036xxxxxx: +2,000,000 VND\nSố dư: 5,500,000 VND", "9036"},
            {"com.vnpay.bidv", "Tài khoản: 12510000123456\nGiao dịch: +1.000.000 VND\nSố dư hiện tại: 3.500.000 VND", "3456"},
            {"com.VCB", "Số dư TK VCB 0011000123456 +50,000 VND lúc 27-09-2026. Số dư 1,234,567 VND", "3456"},
            {"com.mservice.momotransfer", "Bạn vừa nhận 100.000đ từ NGUYEN VAN B", ""},
        };
        for (String[] a : acc) {
            BankParser.Result ra = BankParser.parse(a[0], "Vietcombank", a[1]);
            eq("acc " + a[1].substring(0, Math.min(24, a[1].length())), a[2], ra.account);
        }

        System.out.println("== Tên người chuyển");
        eq("ref có tên", "Nguyen Van A", SenderName.extract("Ref MBVCB.123456789.NGUYEN VAN A chuyen tien"));
        eq("ck tu", "Tran Thi Bich", SenderName.extract("CK tu TRAN THI BICH"));
        eq("có dấu", "Nguyễn Thị Hoa", SenderName.extract("Nguyễn Thị Hoa chuyển tiền học phí"));
        eq("qr sđt", "Hoang Anh Tuan", SenderName.extract("QR - 0987654321 - HOANG ANH TUAN"));
        eq("mã FT", "", SenderName.extract("FT24265ABC123"));
        eq("mã chấm", "", SenderName.extract("MBVCB.1234567.QR.PAY"));
        eq("lệ phí", "", SenderName.extract("LE PHI SMS BANKING"));
        eq("hoá đơn", "", SenderName.extract("thanh toan hoa don dien thang 9"));
        ok("VCB kèm tên", "com.VCB", "Vietcombank",
                "TK 1234567890 +500,000 VND. SD 1,000,000 VND. ND: PHAM MINH DUC chuyen tien", 1, 500000, 1000000);
        BankParser.Result rs = BankParser.parse("com.VCB", "Vietcombank",
                "TK 1234567890 +500,000 VND. SD 1,000,000 VND. ND: PHAM MINH DUC chuyen tien");
        eq("sender field", "Pham Minh Duc", rs.sender);
        BankParser.Result rc = BankParser.parse("com.VCB", "Vietcombank",
                "TK 1234567890 +200,000 VND. SD 1,200,000 VND. ND: FT26265XYZ889");
        eq("code => no sender", "", rc.sender);
        BankParser.Result re = BankParser.parse("com.VCB", "Vietcombank",
                "TK 1234567890 -200,000 VND. SD 1,000,000 VND. ND: NGUYEN VAN A");
        eq("expense => no sender", "", re.sender);

        System.out.println("== Câu đọc");
        eq("chuyển đi", "Bạn đã chuyển đi năm trăm nghìn đồng", VietnameseNumber.announcement(-1, 500000, ""));
        eq("nhận có tên", "Bạn đã nhận được năm trăm nghìn đồng từ Pham Minh Duc",
                VietnameseNumber.announcement(1, 500000, "Pham Minh Duc"));
        eq("nhận mã", "Bạn đã nhận được hai trăm nghìn đồng", VietnameseNumber.announcement(1, 200000, ""));

        System.out.println("\nKết quả: " + pass + " pass, " + fail + " fail");
        if (fail > 0) System.exit(1);
    }
}
