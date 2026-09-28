# Hướng dẫn tạo máy chủ đồng bộ MIỄN PHÍ (Supabase) cho Smart Finance

Mục tiêu: điện thoại và máy tính cùng đăng nhập 1 tài khoản → dữ liệu, ảnh khoảnh khắc tự đồng bộ.
Thời gian: khoảng 10–15 phút. Không cần thẻ ngân hàng, không cần build lại app.

---

## Bước 1 — Tạo tài khoản và project

1. Vào **https://supabase.com** → **Start your project** → đăng nhập bằng GitHub hoặc email.
2. Bấm **New project**:
   - **Name**: `smart-finance` (tuỳ ý)
   - **Database Password**: bấm *Generate a password* rồi **lưu lại** (chỉ dùng khi quản trị, app không cần).
   - **Region**: chọn **Southeast Asia (Singapore)** cho nhanh nhất ở Việt Nam.
   - Gói: **Free**.
3. Bấm **Create new project**, chờ 1–2 phút cho project khởi tạo xong.

## Bước 2 — Tạo database (1 lần dán là xong)

1. Menu trái → **SQL Editor** → **New query**.
2. Mở file **`supabase/setup_all.sql`** trong thư mục dự án (`D:\vi_ca_nhan\smart_finance\supabase\setup_all.sql`)
   bằng Notepad → **Ctrl+A**, **Ctrl+C** → dán vào ô SQL → bấm **Run** (hoặc Ctrl+Enter).
3. Thấy dòng **Success. No rows returned** là xong. Nếu Supabase hỏi xác nhận vì có lệnh
   "destructive" (drop policy/trigger), bấm **Run this query** — các lệnh đó chỉ tạo lại cho đúng.
4. Kiểm tra:
   - **Table Editor**: có các bảng `profiles`, `categories`, `transactions`, `attachments`...
   - **Storage**: có bucket **`receipts`** (Private) — nơi chứa ảnh khoảnh khắc.

> File này chạy lại nhiều lần vẫn an toàn. Nó bật bảo mật RLS: mỗi tài khoản chỉ đọc/ghi được
> dữ liệu và ảnh của chính mình.

## Bước 3 — Bật đăng nhập bằng email

1. Menu trái → **Authentication** → **Sign In / Providers** (hoặc *Providers*) → **Email**: bật **Enable Email provider**.
2. **Confirm email** (xác nhận email khi đăng ký):
   - **Dùng cá nhân / gia đình → nên TẮT**: đăng ký xong là vào app ngay.
   - Nếu BẬT: sau khi đăng ký phải mở email bấm link xác nhận rồi mới đăng nhập được.
     Máy chủ email miễn phí của Supabase chỉ gửi được **rất ít email mỗi giờ**, nên dễ bị báo
     "thao tác quá nhiều lần".
3. Bấm **Save**.

### "Quên mật khẩu?"

Không cần cấu hình gì: bấm *Quên mật khẩu?* trong app → mở email **trên điện thoại** → bấm link →
app tự mở hộp **Đặt mật khẩu mới**.

- Gói Free không cho sửa mẫu email nếu chưa có SMTP riêng, nên email chỉ có link (không có mã).
  Có SMTP riêng thì thêm `<b>{{ .Token }}</b>` vào mẫu *Reset Password* để nhận thêm mã 6 số.
- Máy chủ email mặc định của Supabase chỉ gửi tới email thành viên project và rất ít email mỗi giờ.

## Bước 4 — Khai báo địa chỉ quay về (cho đăng nhập Google / link trong email)

**Authentication** → **URL Configuration** → **Redirect URLs** → **Add URL**, thêm 2 dòng:

```
io.smartfinance.app://login-callback
http://localhost:3789/auth-callback
```

(Dòng 1 cho điện thoại Android, dòng 2 cho app Windows.) Bấm **Save**.

## Bước 5 — Lấy 2 thông tin để app kết nối

1. **Project URL** — dạng `https://abcdxyz....supabase.co`
   - Bấm nút **Connect** ở thanh trên cùng của project, hoặc **Project Settings → Data API**.
2. **Publishable key** — dạng `sb_publishable_...`
   - **Project Settings → API Keys** → copy **Publishable key**.
   - Project cũ có thể chỉ thấy **anon public** (chuỗi dài bắt đầu bằng `eyJ...`) — dùng được như nhau.

> ⚠️ **TUYỆT ĐỐI KHÔNG** dùng **Secret key** (`sb_secret_...`) hay **service_role**. Khóa đó có toàn quyền
> database. App sẽ tự từ chối nếu bạn lỡ dán nhầm.
>
> Publishable/anon key là khóa **công khai** — để trong app là an toàn vì dữ liệu được RLS bảo vệ.

## Bước 6 — Gắn máy chủ vào app (build lại)

Máy chủ **chỉ đặt lúc build**, không sửa được trong app (tránh trẻ con / người khác đổi nhầm trên điện thoại).

1. Tạo `config\env.json` (copy từ `config\env.example.json`) và điền:

   ```json
   {
     "SUPABASE_URL": "https://abcdxyz....supabase.co",
     "SUPABASE_ANON_KEY": "sb_publishable_...",
     "OAUTH_DESKTOP_PORT": "3789",
     "GOOGLE_MAPS_API_KEY": ""
   }
   ```
2. Chạy `build_apk.bat` (hoặc `build.bat`) rồi cài bản mới. File `env.json` nằm trong `.gitignore`.
3. Mở app → **Đăng ký** / **Đăng nhập Google**. Trên máy thứ hai đăng nhập cùng tài khoản → dữ liệu tự kéo về.

Dữ liệu đã nhập khi còn offline sẽ được **gộp vào tài khoản** ở lần đăng nhập đầu tiên rồi đẩy lên cloud.

## Bước 7 (tuỳ chọn) — Đăng nhập bằng Google

Không bắt buộc: email + mật khẩu đã đủ dùng. Nếu muốn nút **Đăng nhập Google** hoạt động:

1. **https://console.cloud.google.com** → tạo project → **APIs & Services → OAuth consent screen**:
   chọn *External*, điền tên app + email → thêm email của bạn vào **Test users**.
2. **Credentials → Create credentials → OAuth client ID** → loại **Web application** →
   **Authorized redirect URIs** thêm: `https://<mã-project>.supabase.co/auth/v1/callback`
   (lấy đúng dòng *Callback URL* hiển thị trong Supabase ở bước 3 dưới đây).
3. Supabase → **Authentication → Sign In / Providers → Google** → bật, dán **Client ID** và **Client Secret** → Save.
4. Bước 4 (Redirect URLs) ở trên đã có sẵn cho Android và Windows.

## Dùng nhiều điện thoại cùng nhận thông báo ngân hàng

Đăng nhập **cùng một tài khoản** (Google hoặc email) trên mọi máy. Nếu 2 điện thoại cùng cài app ngân hàng
và cùng bật *Đọc thông báo*, app tự chống trùng: giao dịch được đặt mã theo nội dung thông báo
(số tiền + số dư sau giao dịch), nên máy nào nhận chậm hơn sẽ **không tạo thêm giao dịch** mà chỉ gắn
tin nhắn gốc vào giao dịch đã có. Không cần cài đặt gì thêm.

- Thông báo có ghi số dư: 2 máy lệch nhau tới 6 giờ vẫn nhận ra là một.
- Thông báo không ghi số dư: chỉ gộp khi lệch nhau dưới 30 phút.
- Giao dịch trùng tạo ra **trước** bản cập nhật này không tự xoá — xoá tay 1 lần.

## Bước 8 (tuỳ chọn) — Bản đồ Google Maps trên Android

Không có khoá thì app dùng bản đồ OpenStreetMap (vẫn có vị trí của tôi, địa hình, vệ tinh).
Muốn nền **Google Maps**:

1. **https://console.cloud.google.com** → chọn project (có thể dùng chung project ở Bước 7).
2. **Billing** → liên kết tài khoản thanh toán (Google bắt buộc có thẻ; hiển thị bản đồ trong app
   Android hiện **không tính phí** — xem lại trang giá Google Maps Platform khi tạo).
3. **APIs & Services → Library** → tìm **Maps SDK for Android** → **Enable**.
   Chỉ bật đúng API này (Places / Geocoding có tính phí, app không dùng).
4. **Credentials → Create credentials → API key** → mở khoá vừa tạo:
   - **Application restrictions**: *Android apps* → **Add** → Package name `io.smartfinance.smart_finance`
     + SHA-1 của khoá ký app. Lấy SHA-1 bằng lệnh (mật khẩu trong `android\key.properties`):
     ```
     keytool -list -v -keystore android\app\smartfinance-keystore.jks
     ```
   - **API restrictions**: *Restrict key* → chỉ chọn **Maps SDK for Android** → **Save**.
5. Dán khoá vào `config\env.json`: `"GOOGLE_MAPS_API_KEY": "AIza..."` rồi chạy `build_apk.bat`.
   (Khác máy chủ Supabase, khoá này **phải build lại app** mới có hiệu lực.)

## Giới hạn gói Free (tham khảo trang giá Supabase, 09/2026)

| Mục | Miễn phí |
|---|---|
| Dung lượng database | 500 MB / project (hàng trăm nghìn giao dịch) |
| Lưu trữ ảnh | 1 GB (ảnh app đã nén còn vài trăm KB → vài nghìn ảnh) |
| Người dùng hoạt động | 50.000 / tháng |
| Băng thông tải xuống | 5 GB / tháng |
| Số project miễn phí | 2 project đang hoạt động |
| **Tạm dừng** | Project **bị tạm dừng nếu 1 tuần không có hoạt động** |

**Nếu project bị tạm dừng**: app vẫn chạy offline bình thường, chỉ không đồng bộ. Vào supabase.com →
chọn project → **Restore project**, chờ vài phút là đồng bộ lại (dữ liệu không mất).
Dùng app hằng ngày (có đồng bộ) thì project luôn hoạt động.

## Lỗi thường gặp

| App báo | Cách xử lý |
|---|---|
| Project URL không đúng / Không kết nối được máy chủ | Kiểm tra URL dạng `https://xxxx.supabase.co`, điện thoại có mạng, project không bị tạm dừng |
| Khóa không hợp lệ | Copy lại **Publishable key** (không thiếu ký tự đầu/cuối) |
| Đây là khóa BÍ MẬT | Bạn dán nhầm Secret/service_role → dùng Publishable key |
| Sai email hoặc mật khẩu | Kiểm tra lại, hoặc bấm *Quên mật khẩu?* |
| Email chưa được xác nhận | Mở email bấm link, hoặc tắt *Confirm email* (Bước 3) |
| Thao tác quá nhiều lần | Giới hạn email miễn phí — chờ khoảng 1 giờ, hoặc tắt *Confirm email* |
| Cách đăng nhập này chưa được bật | Bật Email/Google provider ở Bước 3 / Bước 7 |
| Bấm link khôi phục không mở app | Mở email trên chính điện thoại đã bấm *Quên mật khẩu?*; kiểm tra Redirect URLs (Bước 4) |
| Đăng nhập Google mở trình duyệt nhưng không quay về app | Thiếu Redirect URLs ở Bước 4 |
| Ảnh không lên cloud | Kiểm tra Storage có bucket `receipts` (chạy lại `setup_all.sql`) |

## Bảo mật — tóm tắt

- App chỉ giữ **Publishable/anon key** (công khai). Secret/service_role key chỉ dùng trên máy chủ.
- RLS đảm bảo tài khoản A không đọc được dữ liệu/ảnh của tài khoản B dù có cùng khóa.
- Ảnh nằm trong bucket **riêng tư**; app xem ảnh bằng link ký tạm thời (hết hạn sau 1 giờ).
- Mật khẩu do Supabase Auth mã hoá; app không lưu mật khẩu.
