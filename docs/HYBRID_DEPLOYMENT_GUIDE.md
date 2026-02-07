# 🚀 Hybrid Deployment Guide - LexiLingo

> **Chiến lược:** AI Service chạy local trên máy bạn, còn lại deploy miễn phí trên cloud

---

## 📊 Kiến trúc Hybrid

```
┌─────────────────────────────────────────────────────────────────┐
│                    INTERNET (Public Access)                      │
└──────────────────────────┬───────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ Flutter Web  │   │ Web Admin    │   │Backend Service│
│   (Vercel)   │   │  (Netlify)   │   │ (Render.com) │
│   FREE       │   │   FREE       │   │    FREE      │
└──────────────┘   └──────────────┘   └──────┬───────┘
                                              │
                                              ▼
                                      ┌──────────────┐
                                      │  PostgreSQL  │
                                      │ (Supabase)   │
                                      │    FREE      │
                                      └──────────────┘
                                              ▲
                                              │
        ┌─────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────────┐
│                  YOUR LOCAL MACHINE (Private)                     │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │            AI Service (localhost:8001)                     │  │
│  │  • Whisper STT (244MB)                                     │  │
│  │  • Qwen NLP (900MB)                                        │  │
│  │  • Piper TTS (63MB)                                        │  │
│  │  • Knowledge Graph (50MB)                                  │  │
│  │  Total RAM: ~2.4GB                                         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                           ▲                                       │
│                           │                                       │
│                  ┌────────┴────────┐                              │
│                  │  Tunnel Service │                              │
│                  │  (Expose to     │                              │
│                  │   Internet)     │                              │
│                  └─────────────────┘                              │
│                     • Ngrok (Free)                                │
│                     • Cloudflare Tunnel (Free)                    │
│                     • Tailscale Funnel (Free)                     │
└───────────────────────────────────────────────────────────────────┘
```

---

## ✅ Ưu điểm của Hybrid Setup

| Aspect | Traditional Cloud | Hybrid Setup |
|--------|------------------|--------------|
| **Chi phí AI Service** | $50-100/month (GPU) | $0 (dùng máy local) |
| **Chi phí tổng** | $50-100/month | $0 (hoàn toàn miễn phí!) |
| **GPU Performance** | Limited (free tier) | Full GPU của bạn |
| **RAM cho AI** | 512MB-1GB | Tùy máy (4-16GB) |
| **Cold start** | 30-60s | 0s (always on) |
| **Latency** | Cloud → Cloud | Cloud → Home (thêm ~50ms) |
| **Scalability** | Auto-scale | Manual/Docker scale |

---

## 🔧 Setup Steps

### **STEP 1: Setup Tunnel cho AI Service**

#### Option A: Cloudflare Tunnel (KHUYẾN NGHỊ ⭐)

**Ưu điểm:**
- ✅ Hoàn toàn miễn phí, không giới hạn bandwidth
- ✅ Tự động SSL/TLS
- ✅ DDoS protection built-in
- ✅ Không cần mở port router
- ✅ Static domain miễn phí (*.trycloudflare.com hoặc custom)

**Setup:**

```bash
# 1. Install cloudflared
brew install cloudflare/cloudflare/cloudflared  # macOS
# hoặc https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/

# 2. Login (lần đầu)
cloudflared tunnel login

# 3. Create tunnel
cloudflared tunnel create lexilingo-ai

# 4. Configure tunnel (tạo file config)
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: lexilingo-ai
credentials-file: ~/.cloudflared/<TUNNEL-ID>.json

ingress:
  - hostname: ai.yourdomain.com  # Hoặc dùng *.trycloudflare.com
    service: http://localhost:8001
  - service: http_status:404
EOF

# 5. Route DNS (nếu dùng custom domain)
cloudflared tunnel route dns lexilingo-ai ai.yourdomain.com

# 6. Run tunnel
cloudflared tunnel run lexilingo-ai
```

**Quick Start (không cần account):**
```bash
# Tạo temporary public URL ngay lập tức
cloudflared tunnel --url http://localhost:8001

# Output: https://random-subdomain.trycloudflare.com
# Copy URL này để config vào backend service
```

---

#### Option B: Ngrok (Đơn giản nhất)

**Ưu điểm:**
- ✅ Cực kỳ đơn giản
- ✅ Free tier: 1 tunnel, 40 connections/minute

**Hạn chế:**
- ⚠️ Random URL mỗi lần restart
- ⚠️ Rate limit 40 req/min

**Setup:**
```bash
# 1. Install
brew install ngrok  # macOS

# 2. Sign up & get auth token
ngrok config add-authtoken <YOUR_TOKEN>

# 3. Expose AI service
ngrok http 8001

# Output:
# Forwarding: https://abc123.ngrok.io -> localhost:8001
```

---

#### Option C: Tailscale Funnel (Bảo mật cao)

**Ưu điểm:**
- ✅ Miễn phí, không rate limit
- ✅ VPN built-in (chỉ authorized users access)
- ✅ No public exposure (secure)

**Setup:**
```bash
# 1. Install
brew install tailscale

# 2. Login
tailscale up

# 3. Enable funnel
tailscale funnel 8001

# Output: https://your-machine.tailnet.ts.net
```

---

### **STEP 2: Deploy Backend Service lên Render.com**

**File: `render.yaml`** (đã tạo tự động ở bước sau)

```yaml
services:
  - type: web
    name: lexilingo-backend
    env: python
    region: singapore  # Chọn gần VN
    plan: free
    buildCommand: "pip install -r requirements.txt"
    startCommand: "uvicorn app.main:app --host 0.0.0.0 --port $PORT"
    envVars:
      - key: DATABASE_URL
        sync: false  # Nhập manual từ Supabase
      - key: AI_SERVICE_URL
        value: https://your-tunnel-url.trycloudflare.com  # Từ Step 1
      - key: JWT_SECRET_KEY
        generateValue: true
      - key: FIREBASE_SERVICE_ACCOUNT
        sync: false
```

---

### **STEP 3: Setup Database trên Supabase**

1. Vào https://supabase.com/dashboard
2. Tạo project mới: "lexilingo"
3. Copy Connection String:
   ```
   postgresql://postgres:[password]@db.xxx.supabase.co:5432/postgres
   ```
4. Chạy migrations:
   ```bash
   # Cập nhật DATABASE_URL trong .env
   export DATABASE_URL="postgresql://..."
   
   cd backend-service
   alembic upgrade head
   ```

---

### **STEP 4: Deploy Flutter Web lên Vercel**

**File: `vercel.json`** (đã tạo ở flutter-app/)

```json
{
  "buildCommand": "flutter build web --release",
  "outputDirectory": "build/web",
  "framework": null,
  "rewrites": [
    {
      "source": "/(.*)",
      "destination": "/index.html"
    }
  ],
  "env": {
    "BACKEND_URL": "https://lexilingo-backend.onrender.com",
    "AI_SERVICE_URL": "https://your-tunnel-url.trycloudflare.com"
  }
}
```

**Deploy:**
```bash
cd flutter-app
flutter build web --release

# Push to GitHub, then:
# 1. Import repo vào Vercel
# 2. Set build command: "flutter build web"
# 3. Set output dir: "build/web"
```

---

### **STEP 5: Deploy Web Admin lên Netlify**

**File: `netlify.toml`** (đã tạo ở web-admin/)

```toml
[build]
  command = "npm run build"
  publish = "dist"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200

[context.production.environment]
  VITE_BACKEND_URL = "https://lexilingo-backend.onrender.com"
```

---

## 🐳 Docker Setup cho AI Service (Local)

**File: `docker-compose.local.yml`**

```yaml
version: '3.8'

services:
  ai-service:
    build: ./ai-service
    ports:
      - "8001:8001"
    environment:
      - GEMINI_API_KEY=${GEMINI_API_KEY}
      - MODEL_CACHE_DIR=/app/models
    volumes:
      - ./ai-service/models:/app/models  # Cache models
      - ./ai-service/data:/app/data
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 2G
```

**Run:**
```bash
docker-compose -f docker-compose.local.yml up -d
```

---

## 🔄 Auto-restart & Monitoring

### Systemd Service (Linux/macOS)

**File: `/etc/systemd/system/lexilingo-ai.service`**

```ini
[Unit]
Description=LexiLingo AI Service with Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=your-username
WorkingDirectory=/path/to/LexiLingo/ai-service
ExecStart=/bin/bash -c 'source /path/to/.venv/bin/activate && python -m uvicorn api.main_lite:app --host 0.0.0.0 --port 8001 & cloudflared tunnel run lexilingo-ai'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Enable:**
```bash
sudo systemctl enable lexilingo-ai
sudo systemctl start lexilingo-ai
sudo systemctl status lexilingo-ai
```

---

### LaunchAgent (macOS - KHUYẾN NGHỊ)

**File: `~/Library/LaunchAgents/com.lexilingo.ai.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lexilingo.ai</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/scripts/start-ai-local.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/logs/ai-local.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/logs/ai-local.error.log</string>
</dict>
</plist>
```

**Load:**
```bash
launchctl load ~/Library/LaunchAgents/com.lexilingo.ai.plist
launchctl start com.lexilingo.ai
```

---

## 📊 Monitoring & Health Check

**Health check endpoint:**
```bash
# Check AI service
curl http://localhost:8001/health

# Check through tunnel
curl https://your-tunnel-url.trycloudflare.com/health
```

**Setup uptime monitoring (free):**
- https://uptimerobot.com (50 monitors free)
- Ping AI service mỗi 5 phút
- Email/SMS alert nếu down

---

## 🔒 Security Considerations

### 1. API Key Protection
```bash
# AI Service chỉ accept requests từ backend
# File: ai-service/api/middleware.py

ALLOWED_ORIGINS = [
    "https://lexilingo-backend.onrender.com",
    "https://your-frontend.vercel.app"
]
```

### 2. Cloudflare Access (Optional)
- Enable Cloudflare Access rules
- Chỉ allow IP của Render.com

### 3. Rate Limiting
```python
# ai-service/api/main_lite.py
from fastapi_limiter import FastAPILimiter
from fastapi_limiter.depends import RateLimiter

@app.on_event("startup")
async def startup():
    redis = await aioredis.create_redis_pool("redis://localhost")
    await FastAPILimiter.init(redis)

@app.post("/chat")
@limiter.limit("10/minute")  # 10 requests per minute
async def chat_endpoint():
    ...
```

---

## 💰 Chi phí Chi tiết

| Service | Platform | Monthly Cost |
|---------|----------|--------------|
| Frontend (Flutter Web) | Vercel | $0 |
| Web Admin | Netlify | $0 |
| Backend | Render.com | $0 (750h free) |
| Database | Supabase | $0 (500MB) |
| AI Service | Local Machine | $0 |
| Tunnel | Cloudflare | $0 |
| **TOTAL** | | **$0/month** 🎉 |

**Electricity cost estimate:**
- AI Service running 24/7: ~100W
- Monthly: 100W × 24h × 30d = 72 kWh
- Cost (VN): 72 × 2,000 VND = **144,000 VND/month** (~$6)

**So sánh với full cloud:**
- Full cloud with GPU: $50-100/month
- Hybrid: $6/month (điện)
- **Tiết kiệm: $44-94/month** 💰

---

## 🚦 Quick Start Commands

**1. Start local AI service:**
```bash
bash scripts/start-ai-local.sh
```

**2. Start tunnel:**
```bash
cloudflared tunnel --url http://localhost:8001
# Copy URL output
```

**3. Update backend config:**
```bash
# On Render.com dashboard:
# Environment Variables → AI_SERVICE_URL → Paste tunnel URL
```

**4. Deploy:**
```bash
git push origin main  # Auto-deploy to Vercel/Render/Netlify
```

---

## 🔧 Troubleshooting

### Tunnel connection failed
```bash
# Check if AI service is running
curl http://localhost:8001/health

# Restart tunnel
pkill cloudflared
cloudflared tunnel run lexilingo-ai
```

### Backend can't reach AI service
```bash
# Test from backend
curl https://your-tunnel-url.trycloudflare.com/health

# Check CORS settings in ai-service
```

### High latency
```bash
# Option 1: Use Cloudflare Argo Tunnel (faster routing)
# Option 2: Deploy AI to cloud when traffic grows
# Option 3: Use Redis cache for common requests
```

---

## 📈 Scaling Strategy

**Khi nào cần scale:**
- Traffic > 1000 users/day
- Response time > 3s
- Máy local không đủ mạnh

**Scale options:**
1. **Vertical scaling (local):**
   - Upgrade RAM/GPU
   - Quantize models thêm (Q4 → Q3)

2. **Horizontal scaling:**
   - Deploy AI service lên cloud (Modal.com $30 credit)
   - Keep local as backup/development

3. **Hybrid caching:**
   - Cache common responses trên Redis (Upstash free tier)
   - CDN for static content

---

## 📝 Next Steps

- [ ] Setup Cloudflare Tunnel
- [ ] Deploy backend to Render.com
- [ ] Setup Supabase database
- [ ] Deploy frontend to Vercel
- [ ] Configure environment variables
- [ ] Test end-to-end flow
- [ ] Setup monitoring
- [ ] Enable auto-restart

**Estimated setup time:** 2-3 hours  
**Result:** $0/month deployment! 🚀
