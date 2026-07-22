# LexiLingo VPS Deployment Guide (2-3 VPS) + Nginx + SSL

Tài liệu này gồm:
- Sơ đồ triển khai đề xuất cho 2 VPS và 3 VPS
- Mẫu Nginx config cho api.lexilingo.me và ai.lexilingo.me
- Checklist deploy theo từng bước, có lệnh copy chạy được luôn

## 1) Kiến trúc đề xuất

### Option A: 2 VPS (Nhanh, tiết kiệm)

- VPS-1: Nginx Gateway + backend-service
- VPS-2: ai-service
- Domain:
  - api.lexilingo.me -> VPS-1
  - ai.lexilingo.me -> VPS-1 (Nginx proxy sang VPS-2 nội bộ)

```text
Internet
   |
   v
[ api.lexilingo.me / ai.lexilingo.me ]
   |
   v
[VPS-1: Nginx + backend-service]
   |                     |
   |                     +--> backend-service:8000 (localhost)
   |
   +--> proxy_pass ---> [VPS-2: ai-service:8001]
```

Ưu điểm:
- Chi phí thấp, triển khai nhanh
- Chỉ cần 1 điểm public 80/443

Nhược điểm:
- VPS-1 vừa làm gateway vừa chạy backend

### Option B: 3 VPS (Production khuyến nghị)

- VPS-1: Nginx Gateway (public)
- VPS-2: backend-service
- VPS-3: ai-service
- Domain:
  - api.lexilingo.me -> VPS-1
  - ai.lexilingo.me -> VPS-1

```text
Internet
   |
   v
[ api.lexilingo.me / ai.lexilingo.me ]
   |
   v
[VPS-1: Nginx + SSL]
   |                |
   |                +--> proxy_pass to VPS-2:8000 (backend)
   |
   +--> proxy_pass to VPS-3:8001 (ai)
```

Ưu điểm:
- Tách biệt rõ ràng gateway/app/ai
- Dễ scale từng service độc lập
- Dễ harden security

Nhược điểm:
- Tốn chi phí hơn 2 VPS

## 2) DNS records (bắt buộc)

Trên DNS provider của domain lexilingo.me:

- Type A, Name api, Value <PUBLIC_IP_VPS_1>
- Type A, Name ai, Value <PUBLIC_IP_VPS_1>

Kiểm tra:

```bash
dig +short api.lexilingo.me
dig +short ai.lexilingo.me
```

## 3) Chuẩn bị server (Ubuntu 22.04/24.04)

### 3.1 Trên VPS-1 (Gateway)

```bash
sudo apt update && sudo apt -y upgrade
sudo apt -y install nginx certbot python3-certbot-nginx ufw curl

sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

sudo systemctl enable nginx
sudo systemctl start nginx
```

### 3.2 Trên VPS chạy backend/ai

Mở firewall tối thiểu:

- VPS backend: chỉ cho phép inbound 8000 từ private IP của VPS-1
- VPS ai: chỉ cho phép inbound 8001 từ private IP của VPS-1

Ví dụ UFW (chạy trên VPS backend):

```bash
sudo ufw allow from <PRIVATE_IP_VPS_1> to any port 8000 proto tcp
sudo ufw --force enable
```

Ví dụ UFW (chạy trên VPS ai):

```bash
sudo ufw allow from <PRIVATE_IP_VPS_1> to any port 8001 proto tcp
sudo ufw --force enable
```

## 4) Chạy service bằng systemd (khuyến nghị)

## 4.1 Backend service (trên VPS backend hoặc VPS-1 nếu chọn Option A)

```bash
# 1) Clone code
cd /opt
sudo git clone https://github.com/InfinityZero3000/LexiLingo.git
sudo chown -R $USER:$USER /opt/LexiLingo

# 2) Setup Python env
cd /opt/LexiLingo/backend-service
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 3) Env file
cp .env.example .env 2>/dev/null || true
# Sửa .env theo production
```

Tạo file systemd /etc/systemd/system/lexilingo-backend.service:

```ini
[Unit]
Description=LexiLingo Backend FastAPI
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/opt/LexiLingo/backend-service
Environment="PATH=/opt/LexiLingo/backend-service/venv/bin"
EnvironmentFile=/opt/LexiLingo/backend-service/.env
ExecStart=/opt/LexiLingo/backend-service/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable lexilingo-backend
sudo systemctl restart lexilingo-backend
sudo systemctl status lexilingo-backend --no-pager
```

## 4.2 AI service (trên VPS ai)

```bash
cd /opt
sudo git clone https://github.com/InfinityZero3000/LexiLingo.git
sudo chown -R $USER:$USER /opt/LexiLingo

cd /opt/LexiLingo/ai-service
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

cp .env.example .env 2>/dev/null || true
# Sửa .env, đặc biệt GEMINI_API_KEY và các biến model
```

Tạo file systemd /etc/systemd/system/lexilingo-ai.service:

```ini
[Unit]
Description=LexiLingo AI FastAPI
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/opt/LexiLingo/ai-service
Environment="PATH=/opt/LexiLingo/ai-service/venv/bin"
EnvironmentFile=/opt/LexiLingo/ai-service/.env
ExecStart=/opt/LexiLingo/ai-service/venv/bin/uvicorn api.main:app --host 0.0.0.0 --port 8001 --workers 1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable lexilingo-ai
sudo systemctl restart lexilingo-ai
sudo systemctl status lexilingo-ai --no-pager
```

## 5) Nginx config cho api.lexilingo.me và ai.lexilingo.me

Tạo file /etc/nginx/sites-available/lexilingo:

```nginx
# Tăng giới hạn body cho audio/file upload
client_max_body_size 25m;

# Backend API
server {
    listen 80;
    server_name api.lexilingo.me;

    location / {
        proxy_pass http://127.0.0.1:8000;
        # Nếu backend ở VPS-2 hoặc máy khác, thay bằng:
        # proxy_pass http://<PRIVATE_IP_VPS_2>:8000;

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 15s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# AI API
server {
    listen 80;
    server_name ai.lexilingo.me;

    location / {
        # Nếu AI chạy cùng VPS-1:
        # proxy_pass http://127.0.0.1:8001;

        # Nếu AI chạy VPS riêng:
        proxy_pass http://<PRIVATE_IP_VPS_AI>:8001;

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # AI thường lâu hơn backend bình thường
        proxy_connect_timeout 30s;
        proxy_send_timeout 180s;
        proxy_read_timeout 180s;
    }
}
```

Enable config:

```bash
sudo ln -sf /etc/nginx/sites-available/lexilingo /etc/nginx/sites-enabled/lexilingo
sudo nginx -t
sudo systemctl reload nginx
```

## 6) Cấp SSL Let’s Encrypt

```bash
sudo certbot --nginx -d api.lexilingo.me -d ai.lexilingo.me --redirect --agree-tos -m admin@lexilingo.me -n
```

Kiểm tra auto renew:

```bash
sudo systemctl status certbot.timer --no-pager
sudo certbot renew --dry-run
```

## 7) Checklist deploy end-to-end (copy chạy nhanh)

## 7.1 Preflight

```bash
# Local check DNS
nslookup api.lexilingo.me
nslookup ai.lexilingo.me
```

```bash
# VPS-1
curl -I http://api.lexilingo.me || true
curl -I http://ai.lexilingo.me || true
```

## 7.2 Service health nội bộ

```bash
# Tại máy chạy backend
curl -sS http://127.0.0.1:8000/health || curl -sS http://127.0.0.1:8000/docs

# Tại máy chạy ai
curl -sS http://127.0.0.1:8001/health || curl -sS http://127.0.0.1:8001/docs
```

## 7.3 Health qua domain public

```bash
curl -sS https://api.lexilingo.me/health || curl -sS https://api.lexilingo.me/docs
curl -sS https://ai.lexilingo.me/health || curl -sS https://ai.lexilingo.me/docs
```

## 7.4 Kiểm tra log realtime

```bash
# Gateway
sudo tail -f /var/log/nginx/error.log

# Backend
sudo journalctl -u lexilingo-backend -f

# AI
sudo journalctl -u lexilingo-ai -f
```

## 7.5 Cập nhật app client endpoint

Set endpoint production:
- Backend base URL: https://api.lexilingo.me
- AI base URL: https://ai.lexilingo.me (hoặc chỉ để backend gọi nội bộ)

## 8) Hardening tối thiểu nên bật ngay

- Tắt password login SSH, chỉ dùng SSH key
- Fail2ban cho SSH và Nginx
- Rate limit ở Nginx cho API public
- Chỉ allow inbound 8000/8001 từ private IP gateway
- Không commit file .env, secrets, service-account keys
- Bật backup DB định kỳ + restore test

## 9) Rollback nhanh

```bash
# Quay lại release cũ (nếu bạn deploy theo thư mục version)
# /opt/releases/<timestamp>

# Restart services
sudo systemctl restart lexilingo-backend
sudo systemctl restart lexilingo-ai
sudo systemctl reload nginx
```

## 10) Gợi ý chọn phương án

- Chọn 2 VPS nếu: cần lên nhanh, lưu lượng chưa lớn
- Chọn 3 VPS nếu: muốn production ổn định, dễ scale và vận hành dài hạn

---

Nếu cần, có thể tách thêm 1 tài liệu riêng cho Docker Compose production (không dùng systemd) để triển khai blue/green đơn giản hơn.

## 11) Docker-first deployment (khuyến nghị theo nhu cầu hiện tại)

Phần này là luồng triển khai Docker hóa end-to-end cho đúng mục tiêu "tách service + Nginx + SSL".

Template có sẵn trong repo:
- [deploy/docker-templates/docker-compose.gateway.yml](../../deploy/docker-templates/docker-compose.gateway.yml)
- [deploy/docker-templates/docker-compose.backend.yml](../../deploy/docker-templates/docker-compose.backend.yml)
- [deploy/docker-templates/docker-compose.ai.yml](../../deploy/docker-templates/docker-compose.ai.yml)
- [deploy/docker-templates/nginx/conf.d/lexilingo.http.conf](../../deploy/docker-templates/nginx/conf.d/lexilingo.http.conf)
- [deploy/docker-templates/nginx/conf.d/lexilingo.https.conf](../../deploy/docker-templates/nginx/conf.d/lexilingo.https.conf)
- [deploy/docker-templates/nginx/snippets/proxy-common.conf](../../deploy/docker-templates/nginx/snippets/proxy-common.conf)

### 11.1 Option 2 VPS (Docker)

- VPS-1: gateway (Nginx + Certbot container) + backend container
- VPS-2: ai container

### 11.2 Option 3 VPS (Docker)

- VPS-1: gateway (Nginx + Certbot container)
- VPS-2: backend container
- VPS-3: ai container

## 12) Checklist copy-run cho Docker

### 12.1 Cài Docker + Compose plugin (mỗi VPS)

```bash
sudo apt update
sudo apt -y install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
   $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
docker --version
docker compose version
```

### 12.2 Chuẩn bị source

```bash
sudo mkdir -p /opt/lexilingo
sudo chown -R $USER:$USER /opt/lexilingo
cd /opt/lexilingo
git clone https://github.com/InfinityZero3000/LexiLingo.git
cd LexiLingo
```

### 12.3 Triển khai AI (VPS ai)

```bash
cd /opt/lexilingo/LexiLingo/deploy/docker-templates
cp ../../../ai-service/.env.example .env.ai 2>/dev/null || touch .env.ai

# Sửa file .env.ai: GEMINI_API_KEY và các biến cần thiết

docker compose -f docker-compose.ai.yml build
docker compose -f docker-compose.ai.yml up -d
docker compose -f docker-compose.ai.yml ps
curl -sS http://127.0.0.1:8001/health || curl -sS http://127.0.0.1:8001/docs
```

### 12.4 Triển khai Backend (VPS backend hoặc VPS-1 nếu 2 VPS)

```bash
cd /opt/lexilingo/LexiLingo/deploy/docker-templates
cp ../../../backend-service/.env.example .env.backend 2>/dev/null || touch .env.backend

# Sửa .env.backend: DATABASE_URL, SECRET_KEY, ALLOWED_ORIGINS, AI_SERVICE_URL
# Nếu backend gọi AI qua private network:
# AI_SERVICE_URL=http://<PRIVATE_IP_AI>:8001/api/v1

docker compose -f docker-compose.backend.yml build
docker compose -f docker-compose.backend.yml up -d
docker compose -f docker-compose.backend.yml ps
curl -sS http://127.0.0.1:8000/health || curl -sS http://127.0.0.1:8000/docs
```

### 12.5 Triển khai Gateway Nginx + Certbot (VPS-1)

```bash
mkdir -p /opt/lexilingo/deploy-gateway
cd /opt/lexilingo/deploy-gateway

cp /opt/lexilingo/LexiLingo/deploy/docker-templates/docker-compose.gateway.yml .
mkdir -p certbot/www certbot/conf nginx/conf.d nginx/snippets
cp /opt/lexilingo/LexiLingo/deploy/docker-templates/nginx/conf.d/lexilingo.http.conf nginx/conf.d/
cp /opt/lexilingo/LexiLingo/deploy/docker-templates/nginx/conf.d/lexilingo.https.conf nginx/conf.d/
cp /opt/lexilingo/LexiLingo/deploy/docker-templates/nginx/snippets/proxy-common.conf nginx/snippets/

# Sửa nginx/conf.d/lexilingo.https.conf:
# <PRIVATE_IP_BACKEND> -> IP private của backend
# <PRIVATE_IP_AI> -> IP private của ai

docker compose -f docker-compose.gateway.yml up -d nginx
docker compose -f docker-compose.gateway.yml ps
```

Cấp chứng chỉ lần đầu:

```bash
cd /opt/lexilingo/deploy-gateway

docker run --rm \
   -v "$(pwd)/certbot/www:/var/www/certbot" \
   -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
   certbot/certbot certonly --webroot \
   -w /var/www/certbot \
   -d api.lexilingo.me \
   -d ai.lexilingo.me \
   --email admin@lexilingo.me \
   --agree-tos \
   --no-eff-email

docker compose -f docker-compose.gateway.yml restart nginx
docker compose -f docker-compose.gateway.yml up -d certbot
```

### 12.6 Verify production

```bash
curl -I https://api.lexilingo.me
curl -I https://ai.lexilingo.me
curl -sS https://api.lexilingo.me/health || curl -sS https://api.lexilingo.me/docs
curl -sS https://ai.lexilingo.me/health || curl -sS https://ai.lexilingo.me/docs
```

### 12.7 Rollback nhanh (Docker)

```bash
cd /opt/lexilingo/deploy-gateway

# Xem log nhanh
docker compose -f docker-compose.gateway.yml logs --tail=200 nginx
docker compose -f /opt/lexilingo/LexiLingo/deploy/docker-templates/docker-compose.backend.yml logs --tail=200 backend
docker compose -f /opt/lexilingo/LexiLingo/deploy/docker-templates/docker-compose.ai.yml logs --tail=200 ai

# Restart service lỗi
docker compose -f /opt/lexilingo/LexiLingo/deploy/docker-templates/docker-compose.backend.yml restart backend
docker compose -f /opt/lexilingo/LexiLingo/deploy/docker-templates/docker-compose.ai.yml restart ai
docker compose -f docker-compose.gateway.yml restart nginx
```

Gợi ý production: khi ổn định, đẩy image lên registry và dùng tag version (vd: 2026.04.17-1) để rollback chuẩn bằng cách đổi tag thay vì build trực tiếp trên VPS.
