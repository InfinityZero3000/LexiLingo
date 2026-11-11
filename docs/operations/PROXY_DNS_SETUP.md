# Chuyển `api.lexilingo.me` sang VPS dùng chung (proxy + DNS + chứng chỉ)

Tài liệu này là các bước để đưa lưu lượng thật vào container LexiLingo trên VPS OVH (`ovh-vps`, 135.125.199.46). Các bước 1–2 chỉ đọc hoặc chuẩn bị. **Bước 4 (thêm vhost vào nginx dùng chung) và bước 5 (đổi DNS) mới ảnh hưởng tới người dùng thật hoặc dự án khác**, nên làm khi sẵn sàng.

## Hiện trạng

```
Trình duyệt / app ──HTTPS──▶ Cloudflare (proxy, cam)  ──HTTPS──▶ nginx dùng chung `api_gateway` (80/443)
                                                                       │ HTTP, theo server_name
                                                                       ▼
                                                  Container LXD `lexilingo` 10.77.0.10:80 (gateway LexiLingo, GATEWAY_TLS=off)
                                                                       ▼
                                                     backend-service / ai-service / worker / postgres / mongo / redis
```

- DNS của `lexilingo.me` do **Cloudflare** quản lý (`porter.ns.cloudflare.com`, `sloan.ns.cloudflare.com`). Các bản ghi `lexilingo.me`, `www`, `admin`, `api` đều đang là bản ghi proxy (IP 104.21.x / 172.67.x). Frontend (`lexilingo.me`, `admin`) chạy trên Vercel; chỉ `api` trỏ về máy chủ.
- Máy chủ cũ trước đây là `152.42.199.163` (DigitalOcean `sgp1-01-lexi`), nay đã ngừng dùng.
- Container LexiLingo đã chạy đủ stack và trả lời đúng qua `http://10.77.0.10` với header `Host: api.lexilingo.me`. Nginx dùng chung gọi được tới địa chỉ này (đã thử từ container `api_gateway`).
- nginx dùng chung đọc cấu hình ở `/home/ubuntu/workplace/gateway/` (`nginx.conf` nạp `conf.d/*.conf` và `conf.d/*/*.conf`), certbot ở `certbot/conf` (thư mục do root sở hữu).

## Bước 0: quyết định trước khi chuyển

1. **Dữ liệu chỉ tới 2026-09-04.** Mọi thứ phát sinh trên máy chủ cũ sau thời điểm đó (nếu nó còn nhận ghi) không có trong bản khôi phục. Xác nhận máy cũ đã thôi nhận lưu lượng ghi trước khi chuyển DNS.
2. **Xoay credential** (`SECRET_KEY`, mật khẩu Postgres/Redis, API key, rclone/B2) vì bộ backup cũ chứa chúng. Xoay `SECRET_KEY` sẽ đăng xuất mọi người dùng; làm cùng lúc chuyển DNS cho gọn.
3. **Thông báo cho chủ máy chung**: bước 4 thêm một vhost vào nginx của họ và reload nginx đó.

## Bước 1: kiểm tra container (chỉ đọc)

```bash
ssh ovh-vps 'sudo lxc exec lexilingo -- docker ps --format "{{.Names}}\t{{.Status}}"'
ssh ovh-vps 'curl -s -H "Host: api.lexilingo.me" http://10.77.0.10/health; echo; curl -s -o /dev/null -w "%{http_code}\n" -H "Host: api.lexilingo.me" "http://10.77.0.10/api/v1/courses?page_size=1"'
ssh ovh-vps 'docker exec api_gateway wget -q -T 6 -O - --header="Host: api.lexilingo.me" http://10.77.0.10/health'
```

Cả ba lệnh phải trả về `healthy` / `200`.

## Bước 2: chứng chỉ gốc (khuyến nghị: Cloudflare Origin Certificate)

Vì Cloudflare đứng trước, chứng chỉ ở nginx chỉ cần được Cloudflare tin. **Cloudflare Origin Certificate** (miễn phí, hạn tới 15 năm) tránh phải đụng vào certbot của dự án khác và không cần mở đường HTTP-01.

1. Cloudflare Dashboard → `lexilingo.me` → **SSL/TLS → Origin Server → Create Certificate** (RSA 2048, hostname `api.lexilingo.me`, 15 năm). Lưu `origin.pem` và `origin.key` (khoá chỉ hiện một lần).
2. **SSL/TLS → Overview** đặt chế độ **Full (strict)**.
3. Đặt file lên VPS, ngoài các thư mục certbot, ở chỗ nginx dùng chung đã mount và không bị nạp nhầm như cấu hình (chỉ `*.conf` được nạp):

```bash
scp origin.pem origin.key ovh-vps:/tmp/
ssh ovh-vps 'D=~/workplace/gateway/conf.d/lexilingo/ssl; mkdir -p $D && install -m 644 /tmp/origin.pem $D/origin.pem && install -m 600 /tmp/origin.key $D/origin.key && shred -u /tmp/origin.key /tmp/origin.pem; ls -l $D'
```

(Trong container nginx, đường dẫn là `/etc/nginx/conf.d/lexilingo/ssl/origin.pem`.)

Phương án khác: Let's Encrypt bằng DNS-01 qua API token Cloudflare. Chỉ dùng nếu cần chứng chỉ công khai (ví dụ truy cập trực tiếp không qua Cloudflare).

## Bước 3: tạo vhost (chưa nạp)

Chép `deploy/lxd/edge-vhost.example.conf` thành `~/workplace/gateway/conf.d/lexilingo/lexilingo.conf` (thư mục con để không lẫn với dự án khác). File mẫu đã dùng đường dẫn chứng chỉ ở bước 2. Chỉ cần `server_name` đúng và `proxy_pass http://10.77.0.10:80`.

Điểm quan trọng đã được xử lý sẵn trong mẫu:
- `Host`, `X-Forwarded-For`, `X-Forwarded-Proto` được chuyển tiếp; gateway LexiLingo tin địa chỉ 10.77.0.1 (`GATEWAY_TRUSTED_PROXY`) và lấy IP thật của người dùng từ `CF-Connecting-IP`, nên giới hạn tốc độ vẫn theo từng người dùng.
- `proxy_buffering off` và `proxy_read_timeout 300s` cho các câu trả lời AI dạng streaming.
- `client_max_body_size 25m` cho tải lên audio IELTS và content agent.
- `Upgrade`/`Connection` cho WebSocket (giọng nói), dùng biến riêng `$lexi_connection_upgrade` do chính file vhost khai báo, nên không phụ thuộc `nginx.conf` của dự án khác.

## Bước 4: nạp vhost (ảnh hưởng nginx dùng chung)

```bash
ssh ovh-vps 'docker exec api_gateway nginx -t'        # nếu lỗi: dừng, gỡ file vhost, KHÔNG reload
ssh ovh-vps 'docker exec api_gateway nginx -s reload'
ssh ovh-vps 'curl -sk --resolve api.lexilingo.me:443:127.0.0.1 https://api.lexilingo.me/health'
```

`nginx -t` kiểm tra cả cấu hình của các dự án khác; nếu chỉ vhost mới gây lỗi thì gỡ nó ra và nginx cũ không bị đụng tới (chưa reload). Một vhost trỏ tới file chứng chỉ không tồn tại sẽ làm nginx không khởi động lại được, đó là lý do chứng chỉ phải có trước.

Rollback: xoá thư mục `conf.d/lexilingo/` rồi `nginx -t && nginx -s reload`.

## Bước 5: đổi DNS

1. Cloudflare → **DNS** → bản ghi `api` (loại A): đổi giá trị từ `152.42.199.163` sang `135.125.199.46`, giữ **Proxied** (đám mây cam). Cloudflare tự đặt TTL; thay đổi có hiệu lực trong vài giây.
2. Không đổi `lexilingo.me`, `www`, `admin` (Vercel).
3. Kiểm tra:

```bash
dig +short api.lexilingo.me                       # vẫn ra IP Cloudflare (104.21.x/172.67.x) là đúng
curl -s https://api.lexilingo.me/health            # "healthy"
curl -s -o /dev/null -w "%{http_code}\n" "https://api.lexilingo.me/api/v1/courses?page_size=1"   # 200
```

Rollback DNS: đặt lại giá trị cũ cho bản ghi `api` (tức thì với bản ghi proxy). Dữ liệu ghi vào máy mới trong lúc đó sẽ không có ở máy cũ.

## Bước 6: sau khi chuyển

- Đăng nhập thử bằng Google trên app và trang admin; kiểm tra `https://admin.lexilingo.me` gọi được API (CORS dùng `ALLOWED_ORIGINS` trong `.env.production`, đã có `admin.lexilingo.me`).
- Mở **Trung tâm vận hành** trong admin: phải thấy Sao lưu "Tốt", worker và beat "đang chạy", các tác vụ nền có lần chạy.
- Bật nhắc học khi sẵn sàng: đặt `REMINDERS_ENABLED=true` (và `REMINDER_DRY_RUN=false` khi đã thử xong) trong `.env.production` của container rồi khởi động lại `backend-reminder-worker`, `backend-reminder-beat`.
- Bật bản sao ngoài máy cho backup (`OFFSITE_RCLONE_REMOTE`, `AGE_RECIPIENTS`), vì snapshot LXD cùng đĩa với dữ liệu.
- Khi ổn định vài ngày, xoá hoặc mã hoá lại thư mục backup cũ trên VPS (`~/lexilingo-data/backups`).

## Thêm dự án khác sau này

Mỗi dự án thêm: một container LXD (xem `MULTI_PROJECT_VPS.md`), một thư mục `conf.d/<tên>/` với file `.conf` và chứng chỉ riêng, một bản ghi DNS. Không sửa file của dự án khác.

## Xử lý sự cố

| Triệu chứng | Nguyên nhân thường gặp | Cách kiểm tra |
|---|---|---|
| Cloudflare 521 | nginx dùng chung không chạy hoặc không nghe 443 | `docker ps` trên VPS, `ss -ltn` cổng 443 |
| Cloudflare 525/526 | sai chế độ SSL hoặc chứng chỉ gốc sai | đặt Full (strict), kiểm tra file `origin.pem` khớp `origin.key` |
| 502 từ nginx | không tới được 10.77.0.10 | `docker exec api_gateway wget -qO- http://10.77.0.10/health`; kiểm tra luật `lxd-docker-fw.service` |
| 429 hàng loạt | gateway LexiLingo thấy mọi người dùng là cùng một IP | kiểm tra `GATEWAY_TRUSTED_PROXY` khớp `remote_addr` trong `gateway/nginx/logs/access.log` |
| App mất kết nối sau reboot VPS | luật tường lửa của lxdbr0 chưa nạp | `systemctl status lxd-docker-fw`, `iptables -S DOCKER-USER` |
