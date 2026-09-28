-- =====================================================================
-- Migration 0003: Row Level Security + Storage policies (least privilege)
-- User chỉ SELECT/INSERT/UPDATE/DELETE dữ liệu có user_id = auth.uid().
-- Admin KHÔNG có policy đọc giao dịch cá nhân - chỉ RPC tổng hợp.
-- =====================================================================

alter table public.profiles               enable row level security;
alter table public.app_admins             enable row level security;
alter table public.categories             enable row level security;
alter table public.transactions           enable row level security;
alter table public.budgets                enable row level security;
alter table public.recurring_transactions enable row level security;
alter table public.attachments            enable row level security;
alter table public.category_templates     enable row level security;
alter table public.audit_logs             enable row level security;

-- ---------------------------------------------------------------- profiles
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------------------------------------------------------------- app_admins
-- Chỉ cho admin xem danh sách admin; không có policy ghi (quản lý bằng SQL/service role).
drop policy if exists app_admins_select on public.app_admins;
create policy app_admins_select on public.app_admins
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------- user-owned tables
do $$
declare t text;
begin
  foreach t in array array['categories', 'transactions', 'budgets', 'recurring_transactions'] loop
    execute format('drop policy if exists %1$s_select_own on public.%1$I', t);
    execute format('create policy %1$s_select_own on public.%1$I for select to authenticated
                    using (user_id = (select auth.uid()))', t);

    execute format('drop policy if exists %1$s_insert_own on public.%1$I', t);
    execute format('create policy %1$s_insert_own on public.%1$I for insert to authenticated
                    with check (user_id = (select auth.uid()))', t);

    execute format('drop policy if exists %1$s_update_own on public.%1$I', t);
    execute format('create policy %1$s_update_own on public.%1$I for update to authenticated
                    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);

    execute format('drop policy if exists %1$s_delete_own on public.%1$I', t);
    execute format('create policy %1$s_delete_own on public.%1$I for delete to authenticated
                    using (user_id = (select auth.uid()))', t);
  end loop;
end $$;

drop policy if exists attachments_select_own on public.attachments;
create policy attachments_select_own on public.attachments
  for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------- category templates
drop policy if exists templates_read on public.category_templates;
create policy templates_read on public.category_templates
  for select to authenticated using (true);

drop policy if exists templates_admin_write on public.category_templates;
create policy templates_admin_write on public.category_templates
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- audit logs
drop policy if exists audit_admin_read on public.audit_logs;
create policy audit_admin_read on public.audit_logs
  for select to authenticated using (public.is_admin());

-- Không cấp quyền cho anon trên dữ liệu người dùng.
revoke all on public.categories, public.transactions, public.budgets,
  public.recurring_transactions, public.attachments, public.profiles,
  public.app_admins, public.audit_logs from anon;

-- ---------------------------------------------------------------- storage
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Đường dẫn ảnh: <user_id>/<transaction_id>.jpg -> thư mục đầu tiên phải là uid.
drop policy if exists receipts_select_own on storage.objects;
create policy receipts_select_own on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists receipts_insert_own on storage.objects;
create policy receipts_insert_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists receipts_update_own on storage.objects;
create policy receipts_update_own on storage.objects
  for update to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists receipts_delete_own on storage.objects;
create policy receipts_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
