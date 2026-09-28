-- =====================================================================
-- Smart Finance - TẠO TOÀN BỘ DATABASE TRONG 1 LẦN (dán vào Supabase SQL Editor)
--
-- Cách dùng: Supabase Dashboard -> SQL Editor -> New query -> dán TOÀN BỘ file
-- này -> Run. Chạy lại nhiều lần vẫn an toàn (dùng IF NOT EXISTS / OR REPLACE).
--
-- Gồm: bảng dữ liệu, trigger đồng bộ (LWW), tự tạo hồ sơ khi đăng ký,
-- bảo mật RLS (mỗi người chỉ thấy dữ liệu của mình), kho ảnh "receipts" (riêng tư),
-- danh mục mẫu. Tự sinh từ supabase/migrations/*.sql + supabase/seed/seed.sql.
-- =====================================================================


-- >>>>>>>>>>>>>>>>>>>> supabase/migrations/20260923000001_init_schema.sql
-- =====================================================================
-- Smart Finance - Migration 0001: schema cốt lõi
-- Quy tắc: KHÔNG sửa migration đã chạy trên production. Thay đổi -> file mới.
-- Rollback: xem supabase/migrations/rollback/20260923000001_down.sql
-- =====================================================================

-- ---------------------------------------------------------------- profiles
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_url   text,
  currency     text not null default 'VND',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Quyền admin tách riêng, client KHÔNG có policy ghi (chỉ service role / SQL).
-- Không dùng email làm khóa phân quyền (spec J, K).
create table if not exists public.app_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  granted_at timestamptz not null default now(),
  granted_by text
);

-- ---------------------------------------------------------------- categories
create table if not exists public.categories (
  id                uuid primary key,
  user_id           uuid not null references auth.users (id) on delete cascade,
  name              text not null default '' check (char_length(name) <= 60),
  type              text not null check (type in ('income', 'expense')),
  icon              text not null default 'category',
  color             bigint not null default 4287669422,
  default_key       text,
  sort_order        int not null default 0,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default clock_timestamp(),
  unique (id, user_id)
);
create index if not exists idx_categories_user_sync on public.categories (user_id, server_updated_at);

-- ---------------------------------------------------------------- recurring
create table if not exists public.recurring_transactions (
  id                uuid primary key,
  user_id           uuid not null references auth.users (id) on delete cascade,
  name              text not null check (char_length(name) between 1 and 200),
  amount_minor      bigint not null check (amount_minor > 0),
  type              text not null check (type in ('income', 'expense')),
  category_id       uuid,
  note              text check (char_length(note) <= 1000),
  frequency         text not null check (frequency in ('daily', 'weekly', 'monthly', 'yearly')),
  start_date        date not null,
  end_date          date,
  next_run_date     date not null,
  active            boolean not null default true,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default clock_timestamp(),
  unique (id, user_id),
  check (end_date is null or end_date >= start_date),
  -- Khóa ngoại kép: danh mục phải thuộc cùng user.
  foreign key (category_id, user_id) references public.categories (id, user_id) on delete set null (category_id)
);
create index if not exists idx_recurring_user_sync on public.recurring_transactions (user_id, server_updated_at);

-- ---------------------------------------------------------------- transactions
-- amount_minor = số tiền x100 (DEC-006). Luôn dương; dấu do type quyết định.
create table if not exists public.transactions (
  id                uuid primary key,
  user_id           uuid not null references auth.users (id) on delete cascade,
  name              text not null check (char_length(name) between 1 and 200),
  amount_minor      bigint not null check (amount_minor > 0),
  type              text not null check (type in ('income', 'expense')),
  category_id       uuid,
  note              text check (char_length(note) <= 1000),
  transaction_date  timestamptz not null,
  location_name     text check (char_length(location_name) <= 200),
  latitude          double precision check (latitude between -90 and 90),
  longitude         double precision check (longitude between -180 and 180),
  image_path        text,
  recurring_id      uuid,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default clock_timestamp(),
  check ((latitude is null) = (longitude is null)),
  foreign key (category_id, user_id) references public.categories (id, user_id) on delete set null (category_id),
  foreign key (recurring_id, user_id) references public.recurring_transactions (id, user_id) on delete set null (recurring_id)
);
create index if not exists idx_tx_user_sync on public.transactions (user_id, server_updated_at);
create index if not exists idx_tx_user_date on public.transactions (user_id, transaction_date desc) where deleted_at is null;

-- ---------------------------------------------------------------- budgets
create table if not exists public.budgets (
  id                uuid primary key,
  user_id           uuid not null references auth.users (id) on delete cascade,
  category_id       uuid,
  period            text not null check (period in ('weekly', 'monthly', 'yearly')),
  limit_minor       bigint not null check (limit_minor > 0),
  warn_percent      int not null default 80 check (warn_percent between 1 and 100),
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default clock_timestamp(),
  foreign key (category_id, user_id) references public.categories (id, user_id) on delete set null (category_id)
);
create index if not exists idx_budgets_user_sync on public.budgets (user_id, server_updated_at);

-- ---------------------------------------------------------------- attachments
-- Metadata ảnh (1 giao dịch hiện có tối đa 1 ảnh qua transactions.image_path;
-- bảng này giữ lịch sử/metadata và mở đường cho nhiều ảnh sau này).
create table if not exists public.attachments (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  transaction_id uuid not null references public.transactions (id) on delete cascade,
  storage_path   text not null,
  created_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  unique (transaction_id, storage_path)
);
create index if not exists idx_attachments_user on public.attachments (user_id);

-- ---------------------------------------------------------------- category templates (admin)
create table if not exists public.category_templates (
  key        text primary key,
  type       text not null check (type in ('income', 'expense')),
  icon       text not null,
  color      bigint not null,
  sort_order int not null default 0,
  active     boolean not null default true,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- audit (metadata only)
create table if not exists public.audit_logs (
  id         bigserial primary key,
  actor      uuid,
  action     text not null,
  entity     text,
  entity_id  text,
  metadata   jsonb not null default '{}'::jsonb, -- KHÔNG chứa số tiền / nội dung tài chính
  created_at timestamptz not null default now()
);


-- >>>>>>>>>>>>>>>>>>>> supabase/migrations/20260923000002_functions_triggers.sql
-- =====================================================================
-- Migration 0002: trigger đồng bộ, LWW guard, profile tự tạo, admin RPC
-- =====================================================================

-- LWW guard + con trỏ pull:
--  * Bản ghi tới có updated_at CŨ hơn bản đang lưu -> giữ bản đang lưu
--    (thiết bị offline lâu không ghi đè dữ liệu mới hơn).
--  * Mọi thay đổi được chấp nhận -> server_updated_at = clock_timestamp()
--    (dùng làm con trỏ pull tăng dần, khác nhau cả trong cùng 1 transaction).
--  * user_id không được đổi sau khi tạo.
create or replace function public.sf_sync_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id then
      raise exception 'user_id is immutable' using errcode = '42501';
    end if;
    if new.updated_at < old.updated_at then
      return old;
    end if;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['categories', 'transactions', 'budgets', 'recurring_transactions'] loop
    execute format('drop trigger if exists trg_%1$s_sync on public.%1$I', t);
    execute format(
      'create trigger trg_%1$s_sync before insert or update on public.%1$I
       for each row execute function public.sf_sync_guard()', t);
  end loop;
end $$;

-- Ghi metadata ảnh khi giao dịch có image_path mới.
create or replace function public.sf_track_attachment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.image_path is not null and (tg_op = 'INSERT' or new.image_path is distinct from old.image_path) then
    insert into public.attachments (user_id, transaction_id, storage_path)
    values (new.user_id, new.id, new.image_path)
    on conflict (transaction_id, storage_path) do nothing;
  end if;
  if new.deleted_at is not null then
    update public.attachments set deleted_at = coalesce(deleted_at, now())
    where transaction_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_transactions_attachment on public.transactions;
create trigger trg_transactions_attachment
after insert or update of image_path, deleted_at on public.transactions
for each row execute function public.sf_track_attachment();

-- Tự tạo profile khi có user mới (first login Google).
create or replace function public.sf_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    coalesce(new.raw_user_meta_data ->> 'avatar_url', new.raw_user_meta_data ->> 'picture')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.sf_handle_new_user();

create or replace function public.sf_touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_touch on public.profiles;
create trigger trg_profiles_touch before update on public.profiles
for each row execute function public.sf_touch_updated_at();

-- ---------------------------------------------------------------- RBAC helpers
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.app_admins a where a.user_id = auth.uid());
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Dashboard admin: CHỈ số liệu tổng hợp, không trả dữ liệu tài chính cá nhân.
create or replace function public.admin_dashboard_metrics()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'users_total',            (select count(*) from auth.users),
    'users_active_30d',       (select count(*) from auth.users where last_sign_in_at > now() - interval '30 days'),
    'transactions_total',     (select count(*) from public.transactions where deleted_at is null),
    'transactions_7d',        (select count(*) from public.transactions where created_at > now() - interval '7 days'),
    'tombstones_total',       (select count(*) from public.transactions where deleted_at is not null),
    'attachments_total',      (select count(*) from public.attachments where deleted_at is null),
    'storage_objects',        (select count(*) from storage.objects where bucket_id = 'receipts'),
    'storage_bytes',          (select coalesce(sum((metadata ->> 'size')::bigint), 0) from storage.objects where bucket_id = 'receipts'),
    'last_sync_activity',     (select max(server_updated_at) from public.transactions),
    'generated_at',           now()
  ) into result;

  insert into public.audit_logs (actor, action, entity)
  values (auth.uid(), 'admin.view_metrics', 'dashboard');
  return result;
end;
$$;

revoke all on function public.admin_dashboard_metrics() from public;
grant execute on function public.admin_dashboard_metrics() to authenticated;

-- Dọn tombstone cũ (chạy định kỳ bằng pg_cron hoặc thủ công). Các thiết bị đã
-- offline lâu hơn N ngày nên "Khôi phục toàn bộ từ cloud".
create or replace function public.purge_old_tombstones(days int default 90)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare n int := 0; c int;
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  delete from public.transactions where deleted_at < now() - make_interval(days => days);
  get diagnostics c = row_count; n := n + c;
  delete from public.budgets where deleted_at < now() - make_interval(days => days);
  get diagnostics c = row_count; n := n + c;
  delete from public.recurring_transactions where deleted_at < now() - make_interval(days => days);
  get diagnostics c = row_count; n := n + c;
  delete from public.categories where deleted_at < now() - make_interval(days => days);
  get diagnostics c = row_count; n := n + c;
  insert into public.audit_logs (actor, action, metadata)
  values (auth.uid(), 'system.purge_tombstones', jsonb_build_object('rows', n, 'days', days));
  return n;
end;
$$;

revoke all on function public.purge_old_tombstones(int) from public;
grant execute on function public.purge_old_tombstones(int) to authenticated;


-- >>>>>>>>>>>>>>>>>>>> supabase/migrations/20260923000003_rls_storage.sql
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


-- >>>>>>>>>>>>>>>>>>>> supabase/seed/seed.sql
-- Dữ liệu mẫu cho môi trường development (supabase db reset sẽ chạy file này).
insert into public.category_templates (key, type, icon, color, sort_order) values
  ('cat_food', 'expense', 'restaurant', 4294933081, 0),
  ('cat_transport', 'expense', 'directions_car', 4283403263, 1),
  ('cat_shopping', 'expense', 'shopping_bag', 4292892413, 2),
  ('cat_bills', 'expense', 'receipt_long', 4294946848, 3),
  ('cat_entertainment', 'expense', 'movie', 4288375807, 4),
  ('cat_health', 'expense', 'favorite', 4294921581, 5),
  ('cat_education', 'expense', 'school', 4281255094, 6),
  ('cat_home', 'expense', 'home', 4287458915, 7),
  ('cat_other_expense', 'expense', 'category', 4287669422, 8),
  ('cat_salary', 'income', 'payments', 4280468830, 9),
  ('cat_bonus', 'income', 'card_giftcard', 4279548070, 10),
  ('cat_investment', 'income', 'trending_up', 4279150057, 11),
  ('cat_other_income', 'income', 'savings', 4286893078, 12)
on conflict (key) do nothing;

-- Cấp quyền admin cho 1 user (thay UUID thật, chạy bằng SQL editor / service role):
-- insert into public.app_admins (user_id, granted_by) values ('<USER_UUID>', 'bootstrap');


-- Xong! Kiểm tra: Table Editor phải có các bảng profiles, categories, transactions...
