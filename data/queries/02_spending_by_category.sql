-- Chi tiêu theo danh mục trong tháng hiện tại (giờ Việt Nam), kèm tỉ lệ %. Chỉ đọc.
-- Danh mục mặc định có name rỗng -> hiện default_key (vd. cat_food).
with thang_nay as (
  select t.*
  from transactions t
  where t.deleted_at is null
    and t.type = 'expense'
    and date_trunc('month', t.transaction_date at time zone 'Asia/Ho_Chi_Minh')
        = date_trunc('month', now() at time zone 'Asia/Ho_Chi_Minh')
)
select
  coalesce(nullif(c.name, ''), c.default_key, '(chưa phân loại)') as danh_muc,
  sum(t.amount_minor) / 100 as tong_chi,
  round(100.0 * sum(t.amount_minor) / sum(sum(t.amount_minor)) over (), 1) as ti_le_phan_tram,
  count(*) as so_giao_dich
from thang_nay t
left join categories c on c.id = t.category_id
group by 1
order by tong_chi desc;
