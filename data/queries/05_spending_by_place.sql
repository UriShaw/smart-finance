-- Nơi chi tiêu nhiều nhất (theo tên địa điểm đã gắn vào giao dịch). Chỉ đọc.
select
  t.location_name as dia_diem,
  count(*) as so_lan,
  sum(t.amount_minor) / 100 as tong_chi,
  max(t.transaction_date) as lan_gan_nhat
from transactions t
where t.deleted_at is null
  and t.type = 'expense'
  and t.location_name is not null
group by t.location_name
order by tong_chi desc
limit 20;
