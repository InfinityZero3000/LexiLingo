# ✅ Hybrid Deployment Checklist

Sử dụng checklist này để đảm bảo hoàn thành đầy đủ các bước deployment.

---

## 📋 Pre-deployment (Chuẩn bị)

- [ ] Đã có tài khoản GitHub (push code lên repo)
- [ ] Code đã được test locally và hoạt động tốt
- [ ] Đã có GEMINI_API_KEY từ Google AI Studio
- [ ] Đã có Firebase Service Account JSON
- [ ] Máy local có ít nhất 4GB RAM free

---

## 🔧 Local AI Service Setup

- [ ] Install cloudflared: `brew install cloudflare/cloudflare/cloudflared`
- [ ] Copy `.env.example` thành `.env` trong `ai-service/`
- [ ] Điền GEMINI_API_KEY vào `.env`
- [ ] Chạy: `bash scripts/start-ai-local.sh`
- [ ] Verify service: `curl http://localhost:8001/health`
- [ ] Copy tunnel URL (https://xxx.trycloudflare.com)
- [ ] Test tunnel: `curl https://xxx.trycloudflare.com/health`

**Tunnel URL:** _________________________

---

## 💾 Database Setup (Supabase)

- [ ] Tạo account tại https://supabase.com
- [ ] Tạo project mới tên "lexilingo"
- [ ] Chọn region: Southeast Asia (Singapore)
- [ ] Copy Database URL từ Settings → Database
- [ ] Format: `postgresql://postgres:[PASSWORD]@db.[PROJECT].supabase.co:5432/postgres`
- [ ] Run migrations: `cd backend-service && alembic upgrade head`

**Database URL:** _________________________

---

## 🚀 Backend Deployment (Render.com)

- [ ] Tạo account tại https://render.com
- [ ] Connect GitHub account
- [ ] New → Blueprint
- [ ] Select repo: InfinityZero3000/LexiLingo
- [ ] Render tự động detect `backend-service/render.yaml`
- [ ] Set Environment Variables:
  - [ ] DATABASE_URL: (từ Supabase)
  - [ ] AI_SERVICE_URL: (tunnel URL)
  - [ ] FIREBASE_SERVICE_ACCOUNT: (paste JSON)
  - [ ] FIREBASE_PROJECT_ID
  - [ ] SECRET_KEY: (auto-generated)
- [ ] Click "Apply" để deploy
- [ ] Đợi ~5-10 phút để build
- [ ] Test: `curl https://[YOUR-APP].onrender.com/health`

**Backend URL:** _________________________

---

## 🎨 Flutter Web Deployment (Vercel)

- [ ] Build Flutter web: `cd flutter-app && flutter build web --release`
- [ ] Verify build: `ls build/web` (phải có index.html)
- [ ] Tạo account tại https://vercel.com
- [ ] Import GitHub repo
- [ ] Configure:
  - [ ] Root Directory: `flutter-app`
  - [ ] Framework Preset: Other
  - [ ] Build Command: `flutter build web --release`
  - [ ] Output Directory: `build/web`
- [ ] Environment Variables:
  - [ ] BACKEND_API_URL: (backend URL)
  - [ ] AI_SERVICE_URL: (tunnel URL)
- [ ] Deploy
- [ ] Test: mở https://[YOUR-APP].vercel.app

**Frontend URL:** _________________________

---

## 📊 Web Admin Deployment (Netlify)

- [ ] Tạo account tại https://netlify.com
- [ ] Import GitHub repo
- [ ] Configure:
  - [ ] Base directory: `web-admin`
  - [ ] Build command: `npm run build`
  - [ ] Publish directory: `web-admin/dist`
- [ ] Environment Variables:
  - [ ] VITE_BACKEND_URL: (backend URL)
  - [ ] VITE_AI_SERVICE_URL: (tunnel URL)
- [ ] Deploy
- [ ] Test: mở https://[YOUR-APP].netlify.app

**Admin URL:** _________________________

---

## 🔒 Security & Configuration

- [ ] Update CORS trên Render backend:
  - [ ] ALLOWED_ORIGINS = `[Frontend URL],[Admin URL]`
- [ ] Test CORS: Thử login từ frontend
- [ ] Enable Cloudflare Access (optional - nâng cao)
- [ ] Setup rate limiting cho AI service
- [ ] Verify Firebase authentication hoạt động

---

## 🤖 Auto-start Setup (macOS)

- [ ] Run: `bash scripts/setup-launchd.sh`
- [ ] Verify: `launchctl list | grep lexilingo`
- [ ] Restart máy để test auto-start
- [ ] Check logs: `tail -f logs/ai-launchd.log`

---

## 📈 Monitoring Setup

- [ ] Tạo account tại https://uptimerobot.com
- [ ] Add monitors:
  - [ ] Backend health: `https://[backend]/health` (5 min interval)
  - [ ] Frontend: `https://[frontend]/` (5 min interval)
  - [ ] AI Service: `https://[tunnel]/health` (5 min interval)
- [ ] Configure alert contacts (email/SMS)
- [ ] Test alerts (pause monitor, check email)

---

## ✅ Final Testing

### Backend
- [ ] `curl https://[backend]/health` → {"status":"ok"}
- [ ] `curl https://[backend]/docs` → Swagger UI mở được
- [ ] Test auth: POST `/auth/register` với email/password

### Frontend
- [ ] Mở app, register account mới
- [ ] Login thành công
- [ ] Xem courses list
- [ ] Start lesson
- [ ] Complete exercise

### AI Features
- [ ] Voice input hoạt động (STT)
- [ ] Chat với AI bot
- [ ] Pronunciation feedback
- [ ] TTS phát âm

### Admin Panel
- [ ] Login với admin account
- [ ] Xem user stats
- [ ] View analytics
- [ ] Manage content

---

## 📝 Post-deployment

- [ ] Commit deployment info: `git add deployment-info.txt && git commit`
- [ ] Update README với deployment URLs
- [ ] Share URLs với team
- [ ] Setup backup strategy (Supabase auto-backup)
- [ ] Document troubleshooting steps
- [ ] Monitor logs trong 24h đầu

---

## 🆘 Troubleshooting

### Backend không connect được AI service
```bash
# Test từ backend
curl https://[tunnel-url]/health

# Check CORS trong ai-service/api/main.py
# Verify AI_SERVICE_URL trong Render environment variables
```

### Frontend không load
```bash
# Check Vercel build logs
# Verify environment variables
# Test: flutter build web --release locally
```

### Tunnel bị disconnect
```bash
# Restart tunnel
bash scripts/stop-ai-local.sh
bash scripts/start-ai-local.sh

# Update tunnel URL trong Render environment variables
```

### Cold start quá lâm (Render)
```bash
# Normal: 30-60s first request sau khi sleep
# Solution: Use uptime monitor để ping mỗi 5 phút (keep alive)
```

---

## 💰 Cost Summary

| Service | Plan | Monthly Cost |
|---------|------|--------------|
| Render (Backend) | Free | $0 |
| Supabase (DB) | Free | $0 |
| Vercel (Frontend) | Free | $0 |
| Netlify (Admin) | Free | $0 |
| Cloudflare Tunnel | Free | $0 |
| Local AI (Electricity) | - | ~$6 |
| **TOTAL** | | **$6/month** |

**Estimate savings vs full cloud:** $44-94/month 💰

---

## 📚 Resources

- [Hybrid Deployment Guide](./RPT-009_HYBRID_DEPLOYMENT_GUIDE.md)
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Render Docs](https://render.com/docs)
- [Supabase Docs](https://supabase.com/docs)
- [Vercel Docs](https://vercel.com/docs)
- [Netlify Docs](https://docs.netlify.com)

---

**Hoàn thành:** _____ / _____ tasks ✅

**Deployment Date:** _______________

**Notes:**
