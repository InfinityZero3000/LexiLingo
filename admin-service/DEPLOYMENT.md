# 🚀 LexiLingo Admin Dashboard - Vercel Deployment Guide

## ✅ Build Successful!

Your admin dashboard has been built successfully and is ready to deploy to Vercel.

---

## 📦 Deployment Options

### **Option 1: Deploy via Vercel CLI (Fastest)** ⚡

```bash
# Install Vercel CLI (if not installed)
npm install -g vercel

# Login to Vercel
vercel login

# Deploy to production
cd web-admin
vercel --prod
```

---

### **Option 2: Deploy via GitHub (Recommended)** 🔄

**Steps:**

1. **Commit and push your code:**
   ```bash
   git add .
   git commit -m "feat: Add admin dashboard v0.5.0"
   git push origin main
   ```

2. **Go to Vercel Dashboard:**
   - https://vercel.com/new

3. **Import Repository:**
   - Click "Import Project"
   - Select your GitHub repository: `InfinityZero3000/LexiLingo`

4. **Configure Project:**
   ```
   Framework Preset: Vite
   Root Directory: web-admin
   Build Command: npm run build
   Output Directory: dist
   Install Command: npm install
   ```

5. **Add Environment Variables:**
   ```env
   VITE_BACKEND_URL=https://lexilingo-backend.onrender.com/api/v1
   VITE_AI_URL=https://your-tunnel-url.trycloudflare.com/api/v1
   VITE_APP_NAME=LexiLingo Admin Dashboard
   VITE_APP_VERSION=0.5.0
   VITE_ADMIN_EMAILS=admin@lexilingo.com
   VITE_SUPER_ADMIN_EMAILS=superadmin@lexilingo.com
   ```

6. **Deploy!**
   - Click "Deploy"
   - Wait ~2-3 minutes
   - Your admin dashboard will be live!

---

### **Option 3: Drag & Drop Deploy** 📤

1. Go to: https://vercel.com/new
2. Drag the `web-admin/dist` folder to upload area
3. Wait for deployment
4. Done!

**⚠️ Note:** This method won't auto-update on git push.

---

## 🔧 After Deployment

### 1. Get Your Vercel URL
```
https://your-app-name.vercel.app
```

### 2. Update Backend CORS
Go to Render.com backend dashboard and update:
```env
ALLOWED_ORIGINS=https://your-frontend.vercel.app,https://your-admin.vercel.app
```

### 3. Test Admin Login
```
URL: https://your-admin.vercel.app
Email: admin@lexilingo.com
Password: admin123
```

### 4. Custom Domain (Optional)
In Vercel dashboard:
- Settings → Domains
- Add your custom domain (e.g., admin.lexilingo.com)

---

## 📊 Build Stats

```
✓ Build completed successfully in 10.53s
✓ Total size: 670 KB (194 KB gzipped)
✓ 816 modules transformed
✓ Ready for production deployment
```

---

## 🔥 Quick Deploy Command

```bash
cd /Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/web-admin
vercel --prod
```

---

## 🛠️ Useful Vercel Commands

```bash
vercel              # Deploy to preview
vercel --prod       # Deploy to production
vercel logs         # View deployment logs
vercel domains      # Manage domains
vercel env          # Manage environment variables
vercel --help       # Show all commands
```

---

## 📝 Deployment Checklist

- [x] Build successful
- [ ] Deploy to Vercel
- [ ] Copy deployment URL
- [ ] Update backend CORS
- [ ] Test admin login
- [ ] Verify all features work
- [ ] Share URL with team

---

## 🎯 Next Steps

1. Choose deployment method above
2. Deploy admin dashboard
3. Test thoroughly
4. Update documentation with live URL
5. Monitor analytics and usage

---

**Ready to deploy!** 🚀

Choose your preferred method above and deploy in minutes!
