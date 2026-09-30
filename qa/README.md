# QA · Kiểm thử

| Ở đâu | Nội dung |
|---|---|
| [TEST_PLAN.md](TEST_PLAN.md) | Kế hoạch kiểm thử: phạm vi, kịch bản thủ công, tiêu chí phát hành |
| `frontend/test/` | Test tự động của app (đơn vị + widget) — chạy `devops\check.bat` |
| `frontend/integration_test/` | Test luồng app chạy thật |
| `backend/supabase/tests/` | Test phân quyền RLS trên máy chủ |

Mỗi lần build, `devops\build.bat` chạy `flutter analyze` + toàn bộ test và ghi kết quả vào `CHANGELOG.md`.
