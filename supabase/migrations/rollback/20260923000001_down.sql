-- Rollback toàn bộ schema v1 (CHỈ dùng cho development/staging).
-- Production: ưu tiên "forward migration" (tạo migration mới sửa lỗi) thay vì rollback.
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.purge_old_tombstones(int);
drop function if exists public.admin_dashboard_metrics();
drop function if exists public.is_admin();
drop function if exists public.sf_handle_new_user() cascade;
drop function if exists public.sf_track_attachment() cascade;
drop function if exists public.sf_sync_guard() cascade;
drop function if exists public.sf_touch_updated_at() cascade;
drop table if exists public.attachments;
drop table if exists public.transactions;
drop table if exists public.budgets;
drop table if exists public.recurring_transactions;
drop table if exists public.categories;
drop table if exists public.category_templates;
drop table if exists public.audit_logs;
drop table if exists public.app_admins;
drop table if exists public.profiles;
