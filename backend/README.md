# Backend (BE) · Supabase

Máy chủ của app: cơ sở dữ liệu PostgreSQL, đăng nhập, lưu ảnh. Dự án Supabase: `smart-finance`.

| Thư mục | Nội dung |
|---|---|
| `supabase/migrations/` | Tạo bảng, trigger đồng bộ (LWW), phân quyền RLS, bucket ảnh `receipts`. Chạy theo thứ tự tên file |
| `supabase/migrations/rollback/` | Hoàn tác migration (chỉ dùng cho môi trường dev) |
| `supabase/setup_all.sql` | Gộp mọi migration + seed: dán vào SQL Editor để dựng project mới |
| `supabase/seed/` | Dữ liệu mẫu (danh mục mặc định) |
| `supabase/tests/` | Test phân quyền: người này không đọc được dữ liệu người kia |
| `supabase/config.toml` | Cấu hình Supabase CLI |

Logic đồng bộ phía app (đẩy/kéo, hàng đợi, xung đột) nằm ở `frontend/lib/logic/data/sync/`.

Hướng dẫn dựng Supabase: [docs/guides/HUONG_DAN_SUPABASE.md](../docs/guides/HUONG_DAN_SUPABASE.md).
