# 🚀 Quick Start - Hybrid Deployment

Deploy toàn bộ hệ thống LexiLingo trong **30 phút** với **$0/tháng**!

---

## TL;DR

```bash
# 1. Start AI service locally với public tunnel
bash scripts/start-ai-local.sh

# 2. Copy tunnel URL, sau đó chạy guided deployment
bash scripts/deploy-hybrid.sh

# 3. Done! 🎉
```

---

## Chi tiết từng bước

### 📦 **Bước 1: Chuẩn bị**

```bash
# Clone repo (nếu chưa có)
git clone https://github.com/InfinityZero3000/LexiLingo.git
cd LexiLingo

# Install dependencies
cd backend-service && pip install -r requirements.txt
cd ../flutter-app && flutter pub get
cd ../web-admin && npm install
cd ..

# Setup environment
cp ai-service/.env.example ai-service/.env
# Edit .env và thêm GEMINI_API_KEY
```

### 🤖 **Bước 2: Start Local AI Service**

```bash
bash scripts/start-ai-local.sh
```

Script này sẽ:
- ✅ Start AI service trên port 8001
- ✅ Tạo Cloudflare tunnel (public URL)
- ✅ Output tunnel URL để dùng cho các bước sau

**Output example:**
```
Local URL:  http://localhost:8001
Public URL: https://abc123.trycloudflare.com

⚠ IMPORTANT: Copy the Public URL
```

### ☁️ **Bước 3: Deploy lên Cloud**

#### **Option A: Deployment tự động (khuyên dùng)**

```bash
bash scripts/deploy-hybrid.sh
```

Script sẽ hướng dẫn bạn từng bước deploy:
1. Database (Supabase)
2. Backend (Render.com)
3. Frontend (Vercel)
4. Admin (Netlify)

#### **Option B: Deploy manual**

<details>
<summary>Click để xem hướng dẫn chi tiết</summary>

**3.1. Database - Supabase**

1. Vào https://supabase.com
2. New Project → "lexilingo"
3. Copy connection string
4. Run migrations:
   ```bash
   export DATABASE_URL="postgresql://..."
   cd backend-service
   alembic upgrade head
   ```

**3.2. Backend - Render.com**

1. Vào https://render.com
2. New → Blueprint
3. Connect repo: InfinityZero3000/LexiLingo
4. Set env vars (theo `backend-service/render.yaml`)
5. Deploy

**3.3. Frontend - Vercel**

```bash
cd flutter-app
flutter build web --release
```

1. Vào https://vercel.com
2. Import repo
3. Root: `flutter-app`
4. Build: `flutter build web --release`
5. Output: `build/web`
6. Deploy

**3.4. Admin - Netlify**

1. Vào https://netlify.com
2. Import repo
3. Base: `web-admin`
4. Build: `npm run build`
5. Publish: `web-admin/dist`
6. Deploy

</details>

---

### ✅ **Bước 4: Verify**

```bash
# Test backend
curl https://your-app.onrender.com/health

# Test AI service
curl https://abc123.trycloudflare.com/health

# Open frontend
open https://your-app.vercel.app

# Open admin
open https://your-app.netlify.app
```

---

### 🔄 **Bước 5: Setup Auto-start (Optional)**

Để AI service tự động start khi máy boot:

```bash
bash scripts/setup-launchd.sh
```

---

## 🎯 Architecture Diagram

```
Internet (Free!)
    │
    ├─→ Frontend (Vercel) ──────┐
    ├─→ Admin (Netlify) ────────┤
    └─→ Backend (Render.com) ────┤
           │                     │
           ├─→ Database (Supabase)
           │
           └─→ AI Service (YOUR MACHINE)
                  ↑
            Cloudflare Tunnel (Free!)
```

---

## 💰 Cost Breakdown

| Component | Platform | Cost |
|-----------|----------|------|
| Database | Supabase | $0 |
| Backend | Render | $0 |
| Frontend | Vercel | $0 |
| Admin | Netlify | $0 |
| Tunnel | Cloudflare | $0 |
| AI Service | Local | ~$6/month (electricity) |
| **TOTAL** | | **$6/month** |

**So sánh cloud AI:** $50-100/month → Tiết kiệm **$44-94/month**!

---

## 🛠️ Daily Operations

### Start/Stop AI Service

```bash
# Start
bash scripts/start-ai-local.sh

# Stop
bash scripts/stop-ai-local.sh

# Check status
curl http://localhost:8001/health
```

### View Logs

```bash
# AI service
tail -f logs/ai-local.log

# Tunnel
tail -f logs/tunnel.log
```

### Update Tunnel URL

Nếu tunnel URL thay đổi (restart máy, etc.):

1. Get new URL: `cat logs/tunnel-url.txt`
2. Update trong Render.com:
   - Environment Variables → AI_SERVICE_URL → Save
3. Render sẽ auto-restart backend

---

## 🐛 Troubleshooting

### AI Service không start

```bash
# Check port
lsof -ti:8001

# Check logs
tail -50 logs/ai-local.log

# Restart
bash scripts/stop-ai-local.sh
bash scripts/start-ai-local.sh
```

### Tunnel không connect

```bash
# Reinstall cloudflared
brew reinstall cloudflare/cloudflare/cloudflared

# Try using ngrok instead
ngrok http 8001
```

### Backend timeout connecting AI

```bash
# Verify tunnel is reachable
curl https://[tunnel-url]/health

# Update Render env var
# Dashboard → Environment → AI_SERVICE_URL → Update
```

---

## 📚 Đọc thêm

- **Full Guide:** [docs/HYBRID_DEPLOYMENT_GUIDE.md](./HYBRID_DEPLOYMENT_GUIDE.md)
- **Checklist:** [docs/DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md)
- **Architecture:** [architecture.md](../architecture.md)

---

## 🆘 Cần giúp?

1. Check [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md)
2. View logs: `tail -f logs/*.log`
3. Open issue: https://github.com/InfinityZero3000/LexiLingo/issues

---

**Total setup time:** ~30 minutes  
**Result:** Production-ready app với $0/month! 🎉
