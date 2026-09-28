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
