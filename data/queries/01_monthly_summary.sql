-- Thu, chi, tiết kiệm theo từng tháng (giờ Việt Nam). Chỉ đọc.
-- Chạy trong Supabase → SQL Editor.
select
  to_char(date_trunc('month', t.transaction_date at time zone 'Asia/Ho_Chi_Minh'), 'YYYY-MM') as thang,
  sum(t.amount_minor) filter (where t.type = 'income')  / 100 as thu,
  sum(t.amount_minor) filter (where t.type = 'expense') / 100 as chi,
  (coalesce(sum(t.amount_minor) filter (where t.type = 'income'), 0)
   - coalesce(sum(t.amount_minor) filter (where t.type = 'expense'), 0)) / 100 as tiet_kiem,
  count(*) as so_giao_dich
from transactions t
where t.deleted_at is null
group by 1
order by 1 desc;
