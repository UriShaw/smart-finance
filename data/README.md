# Data Analytics (DA) · Truy vấn phân tích

Các câu SQL **chỉ đọc** để xem số liệu trên Supabase. Mở Supabase → **SQL Editor**, dán file rồi bấm **Run**.

| File | Trả lời câu hỏi |
|---|---|
| `queries/01_monthly_summary.sql` | Mỗi tháng thu, chi, tiết kiệm bao nhiêu? |
| `queries/02_spending_by_category.sql` | Tháng này tiền đi vào danh mục nào nhiều nhất? |
| `queries/03_possible_duplicates.sql` | Giao dịch nào có thể bị ghi trùng (2 máy cùng nhận thông báo)? |
| `queries/04_lost_photos.sql` | Giao dịch nào từng có ảnh nhưng giờ mất liên kết ảnh? |
| `queries/05_spending_by_place.sql` | Chi tiêu nhiều nhất ở đâu? |

Lưu ý:
- `amount_minor` là số tiền × 100, các câu đã chia sẵn.
- Giờ tính theo `Asia/Ho_Chi_Minh`.
- Muốn sửa dữ liệu thì sửa trong app, không sửa thẳng trên bảng. App đồng bộ theo `updated_at`, sửa tay dễ bị ghi đè.
