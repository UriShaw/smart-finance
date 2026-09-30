# Change Requests

## CR-001 — Tự ghi giao dịch từ thông báo ngân hàng (Android)
- **Mô tả:** App cũ có `BankNotificationListenerService` đọc thông báo ngân hàng, regex số tiền, đọc TTS.
- **Lý do:** Tiện lợi, là điểm mạnh của app cũ.
- **Ảnh hưởng UI:** màn cấp quyền Notification Access, danh sách ngân hàng hỗ trợ, cài đặt âm thanh.
- **Database:** thêm cột `source` ('manual'|'notification'|'recurring'), `raw_hash` để chống trùng (không lưu nguyên văn tin nhắn).
- **Sync:** như giao dịch thường.
- **Security:** quyền đọc mọi thông báo – rất nhạy cảm; Google Play hạn chế; chỉ Android (không có trên Windows).
- **Timeline/độ phức tạp:** Cao (parser theo từng ngân hàng, test lớn, foreground service).
- **Khuyến nghị:** Module Android riêng qua MethodChannel.
- **Trạng thái:** ✅ Người dùng xác nhận (23/09/2026) — đã triển khai:
  - `native/android/` (chép tự động vào `android/` bởi `scripts/patch_platforms.ps1`):
    `BankNotificationListener` (NotificationListenerService), `BankParser` + `BankRegistry`
    (nhận diện thuần Java, có test JDK: `native/android/test/BankParserTest.java`), `BankStore`
    (hàng chờ/nhật ký/chống trùng), `BankSpeaker` (TTS tiếng Việt, đọc số thành chữ), `BootReceiver`,
    `BankChannel` (MethodChannel `smart_finance/bank`).
  - Dart: `lib/features/bank/` — nhập giao dịch id xác định (không trùng), màn cài đặt, thử nhận diện, nhật ký, tin cậy/chặn app.
  - Chống nhận nhầm: chặn app chat/mạng xã hội/mua sắm; SMS chỉ nhận khi người gửi là ngân hàng; app lạ cần tên ngân hàng + dấu +/- + số dư;
    loại OTP, khuyến mãi, giao dịch thất bại, nhắc nợ/sao kê, đăng nhập, nạp/rút ví nội bộ; bỏ qua số TK, mã tham chiếu, ngày giờ, SĐT;
    chống trùng app+SMS và thông báo cập nhật lại.
  - Không lưu nguyên văn tin nhắn vào giao dịch; số TK trong nội dung được che.

## CR-002 — Lưu tạm khi offline, đẩy lên khi có mạng rồi xóa dữ liệu tạm
- **Mô tả:** Người dùng yêu cầu (23/09/2026): khi offline lưu vào bộ nhớ tạm của máy; có mạng thì upload và xóa dữ liệu tạm để tránh đầy bộ nhớ.
- **Ảnh hưởng UI:** Cài đặt → "Bộ nhớ tạm trên máy": dung lượng, số thay đổi chờ, thời gian giữ chi tiết (30/90/180/365/tất cả), giữ ảnh gốc, nút dọn ngay.
- **Database:** bảng `tx_archive` + view `v_ledger`; outbox xóa ngay khi đồng bộ.
- **Sync:** CacheJanitor chạy sau mỗi lần sync; chỉ dọn dữ liệu đã xác nhận trên cloud.
- **Security:** không ảnh hưởng.
- **Khuyến nghị:** Triển khai trong MVP (DEC-011).
- **Trạng thái:** ✅ Đã triển khai.
