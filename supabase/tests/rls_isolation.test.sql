-- Test RLS với 2 user khác nhau (spec J). Chạy: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- Hai user giả lập
insert into auth.users (id, email, raw_user_meta_data)
values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local', '{"full_name":"User A"}'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local', '{"full_name":"User B"}');

select is((select count(*)::int from public.profiles), 2, 'profile tự tạo cho user mới');

-- ============ User A tạo dữ liệu
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

insert into public.categories (id, user_id, name, type, icon, color, created_at, updated_at)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'Food A', 'expense', 'restaurant', 1, now(), now());

insert into public.transactions (id, user_id, name, amount_minor, type, category_id,
  transaction_date, created_at, updated_at)
values ('aaaaaaaa-0000-0000-0000-0000000000a1', '11111111-1111-1111-1111-111111111111',
        'Phở', 5000000, 'expense', 'aaaaaaaa-0000-0000-0000-000000000001', now(), now(), now());

select is((select count(*)::int from public.transactions), 1, 'A thấy giao dịch của mình');

select throws_ok(
  $$insert into public.transactions (id, user_id, name, amount_minor, type, transaction_date, created_at, updated_at)
    values ('aaaaaaaa-0000-0000-0000-0000000000a2', '22222222-2222-2222-2222-222222222222',
            'Giả mạo', 100, 'expense', now(), now(), now())$$,
  '42501', null, 'A không thể ghi dữ liệu mang user_id của B');

select throws_ok(
  $$insert into public.transactions (id, user_id, name, amount_minor, type, transaction_date, created_at, updated_at)
    values ('aaaaaaaa-0000-0000-0000-0000000000a3', '11111111-1111-1111-1111-111111111111',
            'Âm', -5, 'expense', now(), now(), now())$$,
  '23514', null, 'check constraint chặn số tiền <= 0');

-- LWW guard: bản cũ hơn không ghi đè
update public.transactions set name = 'Stale', updated_at = now() - interval '1 day'
  where id = 'aaaaaaaa-0000-0000-0000-0000000000a1';
select is((select name from public.transactions where id = 'aaaaaaaa-0000-0000-0000-0000000000a1'),
          'Phở', 'cập nhật cũ hơn bị bỏ qua (LWW guard)');

select throws_ok($$select public.admin_dashboard_metrics()$$, '42501', null,
  'user thường không gọi được admin RPC');

-- ============ User B
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is((select count(*)::int from public.transactions), 0, 'B KHÔNG thấy giao dịch của A');
select is((select count(*)::int from public.categories), 0, 'B KHÔNG thấy danh mục của A');

update public.transactions set name = 'Hacked' where id = 'aaaaaaaa-0000-0000-0000-0000000000a1';
delete from public.transactions where id = 'aaaaaaaa-0000-0000-0000-0000000000a1';

-- B dùng danh mục của A -> vi phạm khóa ngoại kép (category phải cùng user)
select throws_ok(
  $$insert into public.transactions (id, user_id, name, amount_minor, type, category_id, transaction_date, created_at, updated_at)
    values ('bbbbbbbb-0000-0000-0000-0000000000b1', '22222222-2222-2222-2222-222222222222',
            'Mượn danh mục', 100, 'expense', 'aaaaaaaa-0000-0000-0000-000000000001', now(), now(), now())$$,
  '23503', null, 'không thể tham chiếu danh mục của user khác');

select is((select count(*)::int from public.profiles), 1, 'B chỉ thấy profile của mình');

-- ============ Kiểm tra lại dưới quyền A: dữ liệu không bị B sửa/xóa
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select is((select name from public.transactions where id = 'aaaaaaaa-0000-0000-0000-0000000000a1'),
          'Phở', 'B không sửa được dữ liệu của A');
select is((select count(*)::int from public.transactions), 1, 'B không xóa được dữ liệu của A');

select * from finish();
rollback;
