# Nhiều dự án trên một VPS: mỗi dự án một container LXD

Mục đích: LexiLingo và các dự án khác dùng chung một VPS mà không dẫm lên nhau về cổng, RAM, đĩa, chứng chỉ và sự cố. Tài liệu này mô tả cấu trúc và cách làm; **chưa có bước nào được áp lên server**.

## Mô hình

Máy chủ chỉ làm lớp mỏng. Mỗi dự án là một container LXD riêng. Một reverse proxy ở rìa giữ cổng 80/443 và phân luồng theo tên miền.

```
                         Internet
                            │ 80 / 443
                 ┌──────────▼───────────┐
   Máy chủ       │  Edge proxy (nginx)  │  giữ 80/443, chứng chỉ Let's Encrypt,
   (lớp mỏng)    │                      │  mỗi tên miền → một upstream
                 └───┬──────────┬───────┘
        tên miền A   │          │   tên miền B
        ┌────────────▼──┐   ┌───▼──────────────────────────┐
        │ Docker sẵn có │   │ Container LXD: lexilingo      │
        │ (giữ nguyên)  │   │  IP cố định 10.77.0.10        │
        └───────────────┘   │  Docker + compose riêng       │
                            │  giới hạn RAM / CPU / đĩa     │
                            └───────────────────────────────┘
        Dự án tiếp theo = thêm container `proj-<tên>` cùng khuôn
```

Lợi ích:
- Cổng 5432, 6379, 80, 443… bên trong container là của riêng nó.
- Giới hạn RAM, CPU, đĩa đặt ở cấp container.
- Snapshot cả container trước mỗi lần deploy, rollback bằng một lệnh.
- Mỗi dự án có ranh giới backup riêng; di chuyển sang VPS khác bằng `lxc export` / `lxc import`.

Giới hạn cần biết: container dùng chung kernel với máy chủ. Nếu RAM máy cạn thì OOM-killer có thể chọn bất kỳ tiến trình nào, kể cả của dự án khác. Cần bật swap và đặt trần RAM từng container. Với dự án của người ngoài, dùng máy ảo (`lxc launch ... --vm`, khoảng 0,5–1 GB RAM thêm mỗi máy) thay vì container.

## Số liệu máy OVH (`ovh-vps`, đo ngày 2026-11-10, chỉ đọc)

| Mục | Giá trị |
|---|---|
| RAM | 7,6 GB; các container Docker sẵn có dùng khoảng 1,3 GB; khả dụng khoảng 5 GB |
| Đĩa | 73,9 GB một phân vùng, còn khoảng 33 GB, không có đĩa riêng cho LXD |
| Ảo hoá | KVM (`/dev/kvm` có), nên chạy được máy ảo LXD |
| Tường lửa | `ufw` bật, chỉ cho OpenSSH; cổng Docker publish vẫn vào được vì Docker tự chèn iptables |
| Proxy sẵn có | container nginx `api_gateway`, cấu hình ở `/home/ubuntu/workplace/gateway/{nginx.conf,conf.d,certbot}` |
| Mạng đã dùng | bridge Docker 172.18–172.28.x/16, WireGuard `wg0` 10.66.66.0/24 |

## Ngân sách RAM (ước lượng, đo lại sau tuần đầu)

| Phần | RAM |
|---|---|
| Hệ điều hành, Docker, LXD, proxy | khoảng 1 GB |
| Dự án sẵn có | khoảng 1,3 GB đo được, chừa 2 GB |
| Container LexiLingo | trần 4 GB |
| Dự phòng cho máy chủ | tối thiểu 1,5 GB |

Tổng sát ngưỡng: bật swap (`scripts/setup-vps-swap.sh`) và theo dõi. Tổng trần RAM của mọi container không nên quá khoảng 80% RAM máy. Nếu thường xuyên gần trần, chuyển LexiLingo sang VPS riêng.

## Các bước (chỉ làm khi chủ máy đồng ý)

### 1. Khởi tạo LXD

Snap `lxd` có thể đã được cài sẵn (xem "Ghi chú về trạng thái hiện tại"). Khởi tạo với pool btrfs để có quota và snapshot rẻ:

```bash
sudo lxd init --minimal
sudo lxc storage create default btrfs size=24GiB     # nếu --minimal đã tạo pool 'default' kiểu khác, xoá nó trước khi có container
sudo lxc network create lxdbr0 ipv4.address=10.77.0.1/24 ipv4.nat=true ipv6.address=none
sudo lxc profile device add default eth0 nic network=lxdbr0 name=eth0
```

Subnet 10.77.0.0/24 được chọn để không trùng bridge Docker (172.18–172.28) và WireGuard (10.66.66.0/24). Kiểm tra lại bằng `ip -br a` trước khi đặt.

### 2. Cho Docker và LXD cùng tồn tại

Docker đặt chính sách FORWARD là DROP, nên mạng của container LXD bị chặn. Cho phép `lxdbr0` đi qua, và cũng cho phép `ufw`:

```bash
sudo iptables -I DOCKER-USER -i lxdbr0 -j ACCEPT
sudo iptables -I DOCKER-USER -o lxdbr0 -j ACCEPT
sudo ufw allow in on lxdbr0
sudo ufw route allow in on lxdbr0
sudo ufw route allow out on lxdbr0
```

Hai luật `iptables` mất khi khởi động lại: lưu bằng `netfilter-persistent` hoặc một unit systemd chạy sau `docker.service`. **Làm sai bước này có thể làm đứt mạng của các dự án khác**, nên thử ngoài giờ cao điểm và giữ sẵn lệnh gỡ (`iptables -D ...`).

Kiểm tra: từ container mới `curl -sI https://example.com` phải trả về, và `curl -I` vào từng tên miền sẵn có phải cho kết quả như trước khi làm.

### 3. Tạo container LexiLingo

```bash
sudo lxc profile create lexilingo
sudo lxc profile edit lexilingo < deploy/lxd/lexilingo.profile.yaml
sudo lxc launch ubuntu:24.04 lexilingo -p default -p lexilingo
sudo lxc exec lexilingo -- bash -lc 'curl -fsSL https://get.docker.com | sh'
```

Bên trong container, cấu hình LexiLingo theo các tài liệu sẵn có: repo ở `/opt/lexilingo`, `.env.production` và secrets, cài các unit trong `deploy/systemd/`, chạy `scripts/deploy-one-shot.sh`. Backup, healthcheck Celery và thư mục trạng thái `/var/lib/lexilingo` nằm trong container nên Ops Center hoạt động nguyên vẹn.

### 4. Phân luồng ở rìa

Hướng dẫn chi tiết (chứng chỉ Cloudflare Origin, vhost, DNS, rollback): `PROXY_DNS_SETUP.md`. Tóm tắt:

1. Lấy chứng chỉ bằng certbot của proxy rìa cho `api.lexilingo.me`.
2. Chép `deploy/lxd/edge-vhost.example.conf` thành `conf.d/lexilingo.conf` của proxy rìa, sửa tên miền và IP nếu khác.
3. Container nginx rìa phải tới được 10.77.0.10: thử `docker exec api_gateway wget -qO- http://10.77.0.10/health`. Nếu không tới được, thêm luật `-o lxdbr0` ở bước 2 hoặc nối container nginx vào mạng phù hợp.
4. `nginx -t` rồi reload. Không sửa các vhost sẵn có.

### 5. LexiLingo chạy HTTP sau proxy

Gateway của LexiLingo hiện tự làm TLS (certbot, `api.lexilingo.me`). Khi đứng sau proxy rìa, cần chế độ chỉ nghe HTTP cổng 80 và tin `X-Forwarded-*`. Đặt `GATEWAY_TLS=off` trong `.env.production`: `gateway/nginx/render-http-only.sh` biến cấu hình đã render thành bản chỉ nghe cổng 80 (bỏ khối chuyển hướng HTTPS và các chỉ thị `ssl_*`) và tin địa chỉ của proxy rìa (`GATEWAY_TRUSTED_PROXY`, mặc định 10.77.0.1) để giới hạn tốc độ vẫn theo từng người dùng qua `CF-Connecting-IP`. Có test trong `backend-service/tests/test_gateway_http_only.py`.

### 6. Snapshot

```bash
# trước mỗi lần deploy
sudo lxc snapshot lexilingo pre-deploy-$(date +%F-%H%M)
# giữ 7 bản hằng đêm
sudo lxc config set lexilingo snapshots.schedule "0 3 * * *"
sudo lxc config set lexilingo snapshots.expiry 7d
# quay lại
sudo lxc restore lexilingo <tên-snapshot>
```

Snapshot nằm cùng đĩa với dữ liệu, không thay thế backup ngoài máy. Vẫn cần bật `OFFSITE_RCLONE_REMOTE` và `AGE_RECIPIENTS` (xem `BACKUP_RESTORE_POLICY.md`).

## Công thức thêm dự án thứ hai, thứ ba

1. Chọn IP tĩnh tiếp theo (10.77.0.11…) và tên miền.
2. Sao `deploy/lxd/lexilingo.profile.yaml` thành profile mới, đổi `ipv4.address`, RAM, CPU, đĩa.
3. `lxc launch ubuntu:24.04 proj-<tên> -p default -p <profile>`.
4. Cài ứng dụng bên trong, chỉ nghe HTTP trên một cổng.
5. Thêm `conf.d/<tên>.conf` ở proxy rìa (mẫu: `deploy/lxd/edge-vhost.example.conf`), cấp chứng chỉ, reload.
6. Ghi RAM, CPU, đĩa đã cấp vào bảng ngân sách phía trên.

## Gỡ bỏ

- Proxy rìa: xoá file vhost của dự án, `nginx -t`, reload.
- Container: `lxc stop <tên>` rồi `lxc delete <tên>` (giữ snapshot nếu cần).
- Luật tường lửa: `iptables -D DOCKER-USER ...`, `ufw delete ...`.
- Toàn bộ LXD: `sudo snap remove lxd --purge`.

## Ghi chú về trạng thái hiện tại

Trong lúc khảo sát chỉ đọc ngày 2026-11-10, lệnh `lxc list` đã khiến Ubuntu tự cài snap LXD trên `ovh-vps` (lệnh `lxc` ở đó là stub cài khi chạy lần đầu). LXD đang chạy nhưng chưa `lxd init`, chưa có pool, chưa có bridge do LXD quản lý và chưa có container. Khi cần khảo sát chỉ đọc trên máy chưa có LXD, hãy kiểm tra bằng `snap list lxd` thay vì gọi `lxc`.

## Việc chưa làm

- Vhost và chứng chỉ ở proxy rìa (bước 4): chỉ thêm khi đã quyết định chuyển DNS `api.lexilingo.me`, vì vhost trỏ tới chứng chỉ chưa có sẽ làm nginx của dự án khác không khởi động được sau lần reload kế tiếp.
- Quyết định giữ hay gỡ snap LXD hiện có, và sự đồng ý của chủ máy cho các bước 1, 2, 4.
- Đo lại RAM thực tế sau tuần đầu để chốt trần 4 GB của container.
