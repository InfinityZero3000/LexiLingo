# LexiLingo Admin - Quick Start Guide

## Production Profiles (Gateway/Direct)

Use one of the following production env profiles:

- Gateway mode (recommended): `admin-service/.env.production`
  - `VITE_USE_GATEWAY=true`
  - `VITE_BACKEND_URL=https://api.lexilingo.me/api/v1`
  - `VITE_AI_URL=https://api.lexilingo.me/api/v1`
  - `VITE_AI_ADMIN_URL=https://api.lexilingo.me/api/v1/ai-admin`
  - `VITE_API_KEY=REPLACE_WITH_KONG_ADMIN_WEB_KEY`
  - `VITE_AI_ADMIN_API_KEY=REPLACE_WITH_AI_ADMIN_API_KEY`

- Direct service mode (fallback): `admin-service/.env.production.direct.example`
  - `VITE_USE_GATEWAY=false`
  - Keep direct Render/Cloudflare URLs
  - Fill `VITE_AI_ADMIN_API_KEY` so AI settings page can call `/admin/config`

## Build Without Local npm (Docker)

If machine does not have Node/npm installed, build via Docker:

```bash
cd admin-service
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/app -w /app node:20-alpine sh -lc "npm ci && npm run build"
```

This validates the production frontend build end-to-end and creates `dist/`.

## 🚀 Running the Admin System

### Prerequisites
- Python 3.11+ with venv
- Node.js 18+
- PostgreSQL 14+ running
- Redis (optional, for caching)

### 1. Backend Setup

```bash
# Navigate to backend
cd backend-service

# Activate virtual environment
source venv/bin/activate

# Install dependencies (if not done)
pip install -r requirements.txt

# Set environment variables
cp .env.example .env
# Edit .env with your database credentials

# Run migrations (if needed)
alembic upgrade head

# Start backend
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**Verify backend is running:**
```bash
curl http://localhost:8000/health
# Should return: {"status":"healthy",...}
```

### 2. Frontend Setup

```bash
# Navigate to web-admin
cd web-admin

# Install dependencies (first time only)
npm install

# Configure environment
cp .env.example .env.admin
# Edit .env.admin if needed (default points to localhost:8000)

# Start dev server
npm run dev
```

**Access admin:**
Open http://localhost:5173/

### 3. Create Admin User (if needed)

```bash
# In backend-service directory with venv activated
cd backend-service
source venv/bin/activate

# Run Python script to create admin
python -c "
import asyncio
from app.core.database import get_db_session
from app.crud.user import create_user
from app.schemas.user import UserCreate
from app.models.rbac import Role
from sqlalchemy import select

async def create_admin():
    async with get_db_session() as db:
        # Get admin role
        result = await db.execute(select(Role).where(Role.slug == 'admin'))
        admin_role = result.scalar_one_or_none()
        
        if not admin_role:
            print('❌ Admin role not found. Run: python scripts/seed_rbac.py')
            return
        
        # Create admin user
        user_data = UserCreate(
            email='nhthang312@gmail.com.com',
            username='admin',
            password='admin123',  # Change this!
            display_name='Admin User'
        )
        
        user = await create_user(db, user_data)
        user.role_id = admin_role.id
        await db.commit()
        
        print(f'✅ Admin user created: {user.email}')
        print(f'   Login: nhthang312@gmail.com.com / admin123')

asyncio.run(create_admin())
"
```

---

## 📁 Project Structure

```
LexiLingo/
├── backend-service/          # FastAPI backend
│   ├── app/
│   │   ├── routes/           # API endpoints
│   │   │   ├── analytics.py  # 📊 NEW: Dashboard analytics
│   │   │   ├── rbac.py       # RBAC management
│   │   │   ├── admin.py      # Content management
│   │   │   └── ...
│   │   ├── models/           # SQLAlchemy models
│   │   ├── schemas/          # Pydantic schemas
│   │   ├── crud/             # Database operations
│   │   └── core/             # Config, auth, dependencies
│   └── venv/                 # Python virtual env
│
├── web-admin/                # React admin frontend
│   ├── src/
│   │   ├── pages/            # Page components
│   │   │   ├── EnhancedAdminDashboard.tsx  # 📊 NEW
│   │   │   ├── AdminDashboard.tsx
│   │   │   ├── UsersPage.tsx
│   │   │   └── ...
│   │   ├── components/       # Reusable components
│   │   │   ├── dashboard/    # 📊 NEW: Chart components
│   │   │   │   ├── UserGrowthChart.tsx
│   │   │   │   ├── EngagementChart.tsx
│   │   │   │   ├── CoursePopularityChart.tsx
│   │   │   │   └── CompletionFunnelChart.tsx
│   │   │   ├── AppShell.tsx  # Main layout
│   │   │   └── ...
│   │   ├── lib/              # Utilities
│   │   │   ├── api.ts        # Base API client
│   │   │   ├── analyticsApi.ts  # 📊 NEW: Analytics API
│   │   │   ├── rbacApi.ts    # RBAC API
│   │   │   └── ...
│   │   └── main.tsx          # Entry point (with QueryClient)
│   └── node_modules/
│
├── docs/                     # Documentation
│   ├── ADMIN_IMPLEMENTATION_PHASE1.md  # 📊 NEW
│   └── ...
│
└── flutter-app/              # Flutter mobile app (separate)
```

---

## 🔑 Authentication

### Login Flow
1. Navigate to http://localhost:5173/
2. Redirects to `/login`
3. Enter credentials:
   - **Admin:** `nhthang312@gmail.com.com` / `admin123`
   - **Super Admin:** (if created)
4. JWT token stored in localStorage
5. Redirected to dashboard based on role

### Token Management
- Access token: 30 min expiry
- Refresh token: 7 days expiry
- Auto-refresh on API 401 response

---

## 📊 Dashboard Features

### Current Implementation (Phase 1)
- ✅ KPI Cards (4 metrics)
- ✅ User Growth Chart (30 days)
- ✅ Engagement Chart (12 weeks)
- ✅ Course Popularity (Pie chart)
- ✅ Completion Funnel (4 stages)
- ✅ Recent Admin Activity

### API Endpoints Used
- `GET /api/v1/admin/analytics/dashboard/kpis`
- `GET /api/v1/admin/analytics/dashboard/user-growth?days=30`
- `GET /api/v1/admin/analytics/dashboard/engagement?weeks=12`
- `GET /api/v1/admin/analytics/dashboard/course-popularity`
- `GET /api/v1/admin/analytics/dashboard/completion-funnel`
- `GET /api/v1/admin/rbac/dashboard` (legacy stats)

---

## 🧪 Testing

### Backend API Testing

**Using Swagger UI:**
1. Go to http://localhost:8000/docs
2. Click "Authorize" button
3. Login to get JWT token:
   ```json
   POST /api/v1/auth/login
   {
     "email": "nhthang312@gmail.com.com",
     "password": "admin123"
   }
   ```
4. Copy `access_token` from response
5. Paste into Authorize modal: `Bearer <token>`
6. Test analytics endpoints under "Analytics" section

**Using curl:**
```bash
# Login
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"nhthang312@gmail.com","password":"admin123"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Test KPIs
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/v1/admin/analytics/dashboard/kpis

# Test User Growth
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/v1/admin/analytics/dashboard/user-growth?days=30"
```

### Frontend Testing

**Manual checklist:**
- [ ] Login redirects to dashboard
- [ ] KPI cards display numbers (not dashes)
- [ ] Charts render with data
- [ ] Hover tooltips work
- [ ] Loading spinners appear briefly
- [ ] No console errors
- [ ] Layout responsive (try window resize)

---

## 🐛 Troubleshooting

### Backend won't start
```bash
# Check if port 8000 is in use
lsof -ti:8000

# Kill existing process
lsof -ti:8000 | xargs kill -9

# Check database connection
psql -h localhost -U postgres -d lexilingo -c "SELECT 1;"

# Verify environment variables
cat backend-service/.env
```

### Frontend won't start
```bash
# Clear node_modules and reinstall
cd web-admin
rm -rf node_modules package-lock.json
npm install

# Check if port 5173 is in use
lsof -ti:5173 | xargs kill -9

# Verify .env.admin exists
cat web-admin/.env.admin
```

### Dashboard shows no data
```bash
# Check if backend is running
curl http://localhost:8000/health

# Check if you're logged in as admin
# Open browser DevTools → Application → Local Storage
# Look for auth token

# Verify database has data
psql -h localhost -U postgres -d lexilingo -c "SELECT COUNT(*) FROM users;"

# Check backend logs for errors
tail -f backend-service/logs/app.log
```

### Authentication fails
```bash
# Verify admin role exists
psql -h localhost -U postgres -d lexilingo -c "SELECT * FROM roles WHERE slug='admin';"

# Reset admin user password
python backend-service/scripts/reset_admin_password.py

# Clear browser cache and localStorage
# DevTools → Application → Clear site data
```

---

## 🔧 Development Workflow

### Making Changes

**Backend (API endpoints):**
1. Edit files in `backend-service/app/routes/`
2. Uvicorn auto-reloads on save
3. Test in Swagger docs
4. Update schemas if response format changes

**Frontend (UI):**
1. Edit files in `web-admin/src/`
2. Vite hot-reloads on save
3. Check browser for results
4. Update API types if backend changed

### Adding New Chart

1. **Create chart component:**
   ```bash
   # Create new file
   touch web-admin/src/components/dashboard/MyNewChart.tsx
   ```

2. **Define data type:**
   ```typescript
   export type MyChartData = {
     label: string;
     value: number;
   };
   ```

3. **Implement component:**
   ```typescript
   import { BarChart, Bar, ... } from "recharts";
   
   export const MyNewChart: React.FC<Props> = ({ data, loading }) => {
     // ... implement
   };
   ```

4. **Add to dashboard:**
   ```typescript
   // In EnhancedAdminDashboard.tsx
   import { MyNewChart } from "../components/dashboard/MyNewChart";
   
   const { data: myData } = useQuery({
     queryKey: ["dashboard", "my-data"],
     queryFn: getMyChartData,
   });
   
   // In JSX:
   <MyNewChart data={myData?.data ?? []} loading={isLoading} />
   ```

5. **Create backend endpoint:**
   ```python
   # In backend-service/app/routes/analytics.py
   @router.get("/dashboard/my-chart-data")
   async def get_my_chart_data(
       admin: User = Depends(get_current_admin),
       db: AsyncSession = Depends(get_db),
   ):
       # Query database
       result = await db.execute(...)
       return {"data": [...]}
   ```

6. **Add API function:**
   ```typescript
   // In web-admin/src/lib/analyticsApi.ts
   export const getMyChartData = () =>
     apiFetch<{ data: MyChartData[] }>(`${base()}/dashboard/my-chart-data`);
   ```

---

## 📚 Key Files to Know

### Configuration
- `backend-service/.env` - Backend environment variables
- `web-admin/.env.admin` - Frontend environment variables
- `backend-service/app/core/config.py` - Backend settings

### Authentication
- `backend-service/app/core/dependencies.py` - Auth dependencies
- `web-admin/src/lib/auth.ts` - Frontend auth logic
- `web-admin/src/components/AuthProvider.tsx` - Auth context

### Routing
- `backend-service/app/main.py` - Register all routers here
- `web-admin/src/App.tsx` - Frontend route definitions

### Database
- `backend-service/app/models/` - SQLAlchemy models
- `backend-service/alembic/versions/` - Database migrations

---

## 🎯 Next Development Tasks

Refer to [ADMIN_IMPLEMENTATION_PHASE1.md](ADMIN_IMPLEMENTATION_PHASE1.md) for detailed roadmap.

**Week 3-4:** User Management Module
- User list with filters
- User detail 360° view
- Bulk operations

**Week 5-6:** Content Management  
- Course analytics
- Vocabulary import
- Lesson editor

**Week 7-8:** Settings & Reports
- System configuration
- Feature flags
- Audit log viewer

---

## 💡 Tips

1. **Use Swagger docs** for API testing before writing frontend code
2. **Check browser DevTools** → Network tab for API errors
3. **Use React DevTools** to inspect component state
4. **TanStack Query DevTools** available at bottom of screen (development mode)
5. **Backend logs** in terminal show SQL queries and errors
6. **Use TypeScript** strictly - don't use `any` types
7. **Follow existing patterns** in codebase for consistency

---

## 📞 Resources

- **Backend Docs:** http://localhost:8000/docs
- **Frontend Dev Server:** http://localhost:5173/
- **TanStack Query Docs:** https://tanstack.com/query/latest
- **Recharts Docs:** https://recharts.org/
- **FastAPI Docs:** https://fastapi.tiangolo.com/
- **SQLAlchemy Docs:** https://docs.sqlalchemy.org/

---

**Happy Coding! 🚀**
