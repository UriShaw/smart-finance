-- Giao dịch từng có ảnh nhưng hiện không còn trỏ tới ảnh (image_path trống).
-- File ảnh cũ thường vẫn còn trong Storage → bucket receipts theo đường dẫn anh_cu. Chỉ đọc.
select
  t.id, t.name, t.amount_minor / 100 as so_tien, t.transaction_date,
  t.location_name, a.storage_path as anh_cu, t.updated_at
from transactions t
join attachments a on a.transaction_id = t.id
where t.image_path is null
  and t.deleted_at is null
order by t.transaction_date desc;
