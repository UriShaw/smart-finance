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
