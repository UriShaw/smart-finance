# Changelog

## [1.0.0+22] - 2026-09-30
- Hien ma loi dang nhap Google goc, nut dang nhap qua trinh duyet (quality: analyze=PASSED, tests=PASSED)

## [1.0.0+21] - 2026-09-30
- Dang nhap Google kieu goc tren Android (quality: analyze=PASSED, tests=PASSED)

## [1.0.0+20] - 2026-09-30
- Sua mat anh va vi tri khi may thu 2 nhan thong bao muon (quality: analyze=PASSED, tests=PASSED)

## [1.0.0+19] - 2026-09-29
- Ban do chi dung ve tinh (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+18] - 2026-09-29
- Trang chu: thu nhap, chi tieu, tiet kiem theo thang (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+17] - 2026-09-29
- Tu gan vi tri hien tai khi nhan thong bao giao dich (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+16] - 2026-09-29
- Tu xoa giao dich trung, lich thu-chi theo ngay, an may chu, ban do khong xoay (quality: analyze=PASSED, tests=SKIPPED)

## [Unreleased] - 2026-09-29
- Tự xoá giao dịch trùng khi 2 máy cùng tài khoản nhận cùng lúc (lệch ≤ 60 giây), giữ bản có ảnh.
- Lịch: mỗi ngày hiện chênh lệch thu - chi (+150k / −320k), ngày không có giao dịch để trống.
- Ẩn cấu hình máy chủ khỏi màn đăng nhập và Cài đặt (chỉ đặt lúc build).
- Bản đồ: chỉ kéo và phóng to/thu nhỏ, không xoay.
- Dọn mã: xoá Ngân sách, Định kỳ, Nhập nhanh AI, Admin web, Edge Functions (không còn dùng),
  68 chuỗi dịch thừa, code không được gọi; định dạng lại toàn bộ bằng `dart format` (100 cột).
- Sửa cảnh báo phân tích (publishableKey, BuildContext sau await).

## [1.0.0+15] - 2026-09-29
- Nhieu tai khoan: chuyen nhanh kieu Gmail, du lieu tach rieng (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+14] - 2026-09-29
- Gan san may chu Supabase, quen mat khau bang link (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+13] - 2026-09-28
- Ban do kieu Google Photos + Google Maps, chong trung giao dich giua nhieu may (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+12] - 2026-09-28
- Ban do kieu Google Photos + Google Maps, chong trung giao dich giua nhieu may (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+11] - 2026-09-28
- Ban do: vi tri cua toi, dia hinh, ve tinh (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+10] - 2026-09-28
- So du theo ngan hang + xem thong bao goc (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+9] - 2026-09-24
- Dang nhap email + ket noi may chu trong app (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+8] - 2026-09-24
- Tu lay vi tri khi nhap giao dich (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+7] - 2026-09-24
- Sua tieng ting ting to ro nhu app cu (quality: analyze=PASSED, tests=SKIPPED)

## [1.0.0+6] - 2026-09-24
- Khoanh khac anh + vi tri, tab Lich, doc ten nguoi chuyen (quality: analyze=PASSED, tests=SKIPPED)

## [Unreleased] - 2026-09-24
- Khoảnh khắc kiểu Locket trong Chi tiết giao dịch: chụp ảnh vuông + lời nhắn, tự lưu vị trí/tên nơi chụp;
  lưu trên máy trước, có mạng tự đẩy ảnh + vị trí lên cloud. Trang chủ có dải "Khoảnh khắc" + nút Bản đồ.
- Thanh điều hướng 5 tab: Trang chủ · Lịch sử · Lịch · Thống kê · Cài đặt.
- Bỏ nút Thêm giao dịch, Nhập nhanh, Ngân sách, Định kỳ (ngừng tự sinh giao dịch định kỳ).
- Đọc thông báo ngân hàng: "Bạn đã chuyển đi X đồng"; tiền vào đọc "Bạn đã nhận được X đồng từ <Tên>" khi nội dung
  giống tên người, còn nội dung là mã thì chỉ đọc "Bạn đã nhận được X đồng". Tên người gửi hiện trong tên giao dịch.
- Liquid Glass v2 (tham khảo iOS 26): công tắc kính lỏng (giọt kính co giãn khi bấm/kéo), danh sách cài đặt nhóm
  với icon màu, thanh chọn có viên kính trượt, bảng chọn kính nổi thay menu thả xuống, hộp thoại/menu kính,
  thanh điều hướng có giọt kính trượt, menu chức năng bên trái (điện thoại) và thanh bên kính (Windows, thêm Danh mục).
  Kính tăng bão hoà màu nền phía sau. Thêm `check.bat` (analyze + test nhanh).

## [1.0.0+2] - 2026-09-23
- Liquid Glass + doc thong bao ngan hang (quality: analyze=PASSED, tests=PASSED)
- Giao diện Liquid Glass mới: nền chất lỏng chuyển động, thẻ kính viền phản quang, thanh điều hướng kính nổi,
  thẻ số dư gradient, số tiền chạy mượt, chuyển tab mượt; bảng màu tươi sáng; tùy chọn làm mờ mọi thẻ / nền chuyển động.
- (Android) Ghi tự động từ thông báo ngân hàng + đọc giọng tiếng Việt, nhận mọi ngân hàng/ví, chống nhận nhầm
  (OTP, khuyến mãi, chat, giao dịch lỗi...), chống trùng, nhật ký, thử nhận diện, tin cậy/chặn ứng dụng (CR-001).

## [1.0.0+1] - 2026-09-23
- MVP Smart Finance: offline-first SQLite + outbox sync Supabase, dọn bộ nhớ tạm sau đồng bộ,
  Google login, giao dịch (ảnh/vị trí), lịch sử, lịch, thống kê, ngân sách, định kỳ, bản đồ OSM,
  nhập nhanh tiếng Việt, backup JSON/CSV, khóa PIN, 4 ngôn ngữ, Liquid Glass responsive.
- Supabase migrations v1 (schema, trigger LWW, RLS, storage), Edge Functions ai-assistant/admin-metrics.
- Build 1 lệnh `build.bat` → releases\<phiên bản>\.
