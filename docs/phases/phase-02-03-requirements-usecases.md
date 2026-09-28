# Phase 2 — Requirements & Phase 3 — Use Cases / Acceptance Criteria

## Phạm vi

| Nhóm | MVP (đã code) | Phase 2 (khung) | Future |
|---|---|---|---|
| Auth | Google qua Supabase, offline mode, logout, session | — | Apple/Email |
| Giao dịch | CRUD, ảnh, vị trí, ghi chú, tìm/lọc/phân trang | OCR | Nhiều ảnh |
| Danh mục | Mặc định + tùy chỉnh (tên/icon/màu), xóa mềm | Template từ admin | — |
| Lịch / Thống kê | Lịch chi theo ngày; ngày/tuần/tháng/năm/tùy chọn, theo danh mục, biểu đồ | — | Xuất PDF |
| Ngân sách | Theo danh mục/tổng, tuần/tháng/năm, cảnh báo % | Thông báo đẩy | — |
| Định kỳ | Ngày/tuần/tháng/năm, chống trùng | — | — |
| Bản đồ | OSM qua MapService abstraction, chọn vị trí | Google/Mapbox provider | — |
| AI/Voice | Parser tiếng Việt offline + preview | Edge Function AI, speech-to-text | Trợ lý hội thoại |
| Sync | Outbox, retry/backoff, LWW, tombstone, ảnh, dọn bộ nhớ tạm | Realtime | — |
| Settings | Theme, ngôn ngữ, tiền tệ, giảm hiệu ứng, PIN, retention, backup JSON/CSV, restore cloud | — | — |
| Web Admin | RBAC + RPC số liệu tổng hợp + trang khung | Quản lý template | — |

## Functional Requirements (rút gọn)

| ID | Yêu cầu |
|---|---|
| FR-01 | Đăng nhập Google; cùng tài khoản trên mọi thiết bị → cùng user id |
| FR-02 | Dùng được hoàn toàn offline, không cần tài khoản |
| FR-03 | Thêm/sửa/xóa giao dịch với tên, số tiền, loại, danh mục, ngày giờ, ghi chú, ảnh, địa điểm, tọa độ |
| FR-04 | Lịch sử phân trang, tìm kiếm, lọc loại/danh mục/khoảng ngày |
| FR-05 | Lịch chi tiêu: tổng chi theo ngày, chạm ngày xem giao dịch |
| FR-06 | Thống kê theo kỳ + cơ cấu danh mục + xu hướng |
| FR-07 | Ngân sách theo danh mục/kỳ với tiến độ và cảnh báo |
| FR-08 | Khoản định kỳ tự sinh giao dịch, không trùng |
| FR-09 | Bản đồ giao dịch có tọa độ; lỗi map không làm crash |
| FR-10 | Đồng bộ 2 chiều giữa thiết bị; ảnh lên Storage |
| FR-11 | **Dọn bộ nhớ tạm sau khi đồng bộ** (CR-002) |
| FR-12 | Sao lưu/khôi phục JSON (checksum), xuất CSV, khôi phục từ cloud |
| FR-13 | Cài đặt: theme, ngôn ngữ (vi/en/zh-Hans/zh-Hant/system), tiền tệ, PIN, thông báo ngân sách |

## Non-functional

Responsive 320px → desktop; không hard-code text (localization); Dark/Light; font scaling;
không log token/dữ liệu tài chính; không secret trong app; lỗi mạng/provider không crash; có test tự động.

## Use cases & Acceptance Criteria

| UC | Kịch bản | Acceptance Criteria |
|---|---|---|
| UC-01 Ghi chi tiêu offline | Mất mạng → thêm "Phở 50.000" | Hiện ngay ở Tổng quan; biểu tượng chờ đồng bộ; outbox có 1 mục |
| UC-02 Đồng bộ khi có mạng | Bật mạng | ≤ vài giây giao dịch lên cloud, trạng thái "Đã đồng bộ", outbox rỗng |
| UC-03 Ảnh hóa đơn | Chọn ảnh → lưu → có mạng | Ảnh nén ≤1280px, lên Storage `<uid>/<txId>.jpg`, file tạm bị xóa sau khi xác nhận |
| UC-04 Upload ảnh lỗi | Storage lỗi | Metadata vẫn lên; bản ghi KHÔNG đánh dấu synced; tự retry; file tạm giữ nguyên |
| UC-05 Đa thiết bị | Sửa trên máy A | Máy B thấy thay đổi sau lần sync kế tiếp |
| UC-06 Xóa | Xóa trên A | B cũng mất bản ghi (tombstone), không "sống lại" |
| UC-07 Định kỳ | Tiền nhà hàng tháng 31 | Sinh 31/1, 28/2, 31/3…; mở app nhiều lần / 2 máy không trùng |
| UC-08 Ngân sách | Hạn mức 1tr, cảnh báo 80% | Chi 850k → cảnh báo vàng; >1tr → đỏ |
| UC-09 Backup | Xuất JSON → nhập vào máy khác | Số bản ghi + tổng tiền bằng nhau; nhập lại lần 2 không trùng |
| UC-10 Khóa PIN | Bật PIN | Mở app phải nhập đúng PIN |
| UC-11 Bảo mật RLS | User B truy vấn | Không đọc/sửa/xóa được dữ liệu User A (pgTAP test) |
