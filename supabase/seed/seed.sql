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
