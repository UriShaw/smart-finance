-- Giao dịch có thể bị trùng: cùng loại, cùng số tiền, cách nhau không quá 10 phút.
-- Thường do 2 điện thoại cùng ghi 1 thông báo ngân hàng. Chỉ đọc — xoá trong app.
select
  a.id as ma_1, b.id as ma_2,
  a.name, a.amount_minor / 100 as so_tien, a.type,
  a.transaction_date as thoi_gian_1, b.transaction_date as thoi_gian_2,
  a.image_path is not null as anh_1, b.image_path is not null as anh_2
from transactions a
join transactions b
  on b.user_id = a.user_id
 and b.type = a.type
 and b.amount_minor = a.amount_minor
 and b.id > a.id
 and abs(extract(epoch from b.transaction_date - a.transaction_date)) <= 600
where a.deleted_at is null and b.deleted_at is null
order by a.transaction_date desc;
