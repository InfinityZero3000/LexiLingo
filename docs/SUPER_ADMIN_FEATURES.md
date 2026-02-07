# 🛡️ Super Admin Features & Permissions

## ✅ Giao diện Super Admin đã có

### 📍 **Routes đã implement:**

| Route | Component | Mô tả | Status |
|-------|-----------|-------|--------|
| `/super` | SuperAdminDashboard | Tổng quan hệ thống | ✅ Hoàn thành |
| `/super/admins` | AdminManagementPage | Quản lý admin users | ✅ UI xong, ⚠️ cần API |
| `/super/ai-chat` | AiChatSettingsPage | Cấu hình AI Chat (Gemini) | ✅ UI xong, ⚠️ cần API |
| `/super/db` | DatabasePage | Quản lý database | ✅ Hoàn thành |
| `/super/ai-models` | AiModelsPage | Quản lý AI models | ✅ Hoàn thành |

### 🎨 **Giao diện có sẵn:**

#### 1️⃣ **Admin Management** (`/super/admins`)
**Tính năng:**
- ✅ Hiển thị danh sách admin users (table với email, role, status, last login)
- ✅ Thêm admin mới (modal với email input + role selector)
- ✅ Toggle activate/deactivate admin
- ✅ Phân biệt admin/super_admin với màu sắc và icon Shield

**API cần implement:**
```typescript
GET  /api/v1/admin/users?role=admin,super_admin
POST /api/v1/admin/promote-user
     Body: { email: string, role: "admin" | "super_admin" }
PATCH /api/v1/admin/users/{id}/status
     Body: { is_active: boolean }
```

#### 2️⃣ **AI Chat Configuration** (`/super/ai-chat`)
**Tính năng:**
- ✅ Chọn Gemini model (2.0 Flash, 1.5 Flash/Pro)
- ✅ Điều chỉnh temperature (0-2) với slider
- ✅ Cấu hình max_tokens (512-8192)
- ✅ Top P / Top K parameters
- ✅ **Gemini API Key Configuration** (mới thêm)
  - Input field với Show/Hide password
  - Lưu trữ an toàn
  - Fallback to environment variable nếu để trống
- ✅ Feature toggles (toggle switches):
  - Voice support (STT/TTS)
  - Grammar check
  - Topic analysis
  - MongoDB integration
- ✅ Chat memory turns (số tin nhắn ghi nhớ)


**API cần implement:**
```typescript
GET /api/v1/admin/config  // hoặc AI service: /api/v1/ai/config
PUT /api/v1/admin/config
    Body: {
      gemini_api_key?: string,     // NEW: Có thể null/empty fallback to env
      gemini_model: string,
      temperature: number,
      max_tokens: number,
      top_p: number,
      top_k: number,
      use_mongodb: boolean,
      enable_voice: boolean,
      enable_grammar: boolean,
      enable_topic: boolean,
      chat_memory_turns: number
    }
```

---

## 🔐 Phân quyền Admin vs Super Admin

### **Role Hierarchy:**
```
Level 0: user (người dùng thường)
Level 1: admin (quản trị viên)
Level 2: super_admin (siêu quản trị)
```

### **Admin (Level 1)** - Quyền hạn:

#### ✅ **Có thể làm:**
1. **User Management:**
   - ✅ Xem danh sách users
   - ✅ Tạo user mới
   - ✅ Cập nhật thông tin user (display_name, avatar)
   - ✅ Kích hoạt/vô hiệu hóa user (is_active)
   - ✅ Filter, search, export users

2. **Content Management:**
   - ✅ Quản lý Courses (tạo, sửa, xóa)
   - ✅ Quản lý Units
   - ✅ Quản lý Lessons
   - ✅ Quản lý Vocabulary
   - ✅ Quản lý Achievements
   - ✅ Quản lý Shop items
   - ✅ Content Lab (grammar test)
   - ✅ Content Analytics

3. **System Management:**
   - ✅ Xem Ads/Banner
   - ✅ Xem Logs
   - ✅ Xem Monitoring (system health)
   - ✅ System settings (chung)

#### ❌ **Không thể làm:**
- ❌ Xóa user (chỉ super_admin)
- ❌ Thay đổi role của user (chỉ super_admin)
- ❌ Promote user thành admin (chỉ super_admin)
- ❌ Quản lý admin accounts (chỉ super_admin)
- ❌ Cấu hình AI Chat (chỉ super_admin)
- ❌ Truy cập Database trực tiếp (chỉ super_admin)
- ❌ Quản lý AI Models (chỉ super_admin)

---

### **Super Admin (Level 2)** - Toàn quyền:

#### ✅ **Có tất cả quyền của Admin +:**

1. **Admin Management:**
   - ✅ Xem danh sách tất cả admin/super_admin
   - ✅ Promote user → admin/super_admin
   - ✅ Demote admin → user
   - ✅ Kích hoạt/vô hiệu hóa admin
   - ✅ Xóa admin (nếu cần)

2. **User Management (Extended):**
   - ✅ Xóa user (soft delete hoặc hard delete)
   - ✅ Thay đổi role của bất kỳ user nào
   - ✅ Bulk operations trên users

3. **System Configuration:**
   - ✅ **Quản lý Gemini API Key** (có thể thay đổi từ UI)
   - ✅ Cấu hình AI Chat (Gemini model, parameters)
   - ✅ Quản lý AI Models (load/unload, config)
   - ✅ Truy cập Database trực tiếp
   - ✅ Xem/Sửa database schema
   - ✅ System-level settings

4. **Advanced Features:**
   - ✅ RBAC Management (roles, permissions)
   - ✅ Feature flags
   - ✅ Environment variables (sensitive)
   - ✅ Security settings

---

## 📋 Backend APIs Status

### ✅ **Đã có (Backend Service):**
```python
# User Management
GET    /api/v1/admin/users              # List users (admin+)
POST   /api/v1/admin/users              # Create user (admin+)
PATCH  /api/v1/admin/users/{id}         # Update user (admin+)
DELETE /api/v1/admin/users/{id}         # Delete user (super_admin only)
PATCH  /api/v1/admin/users/{id}/role    # Change role (super_admin only)

# Content Management
GET/POST/PUT/DELETE /api/v1/admin/courses
GET/POST/PUT/DELETE /api/v1/admin/achievements
GET/POST/PUT/DELETE /api/v1/admin/vocabulary
GET/POST/PUT/DELETE /api/v1/admin/shop

# System
GET  /api/v1/admin/system-info          # System health
GET  /api/v1/admin/logs                 # Activity logs
GET  /api/v1/admin/monitoring           # Monitoring data

# RBAC
GET  /api/v1/rbac/roles                 # List roles (admin+)
POST /api/v1/rbac/roles                 # Create role (super_admin)
GET  /api/v1/rbac/permissions           # List permissions (admin+)
```

### ⚠️ **Cần implement:**

#### **Backend Service** (`backend-service`):
```python
# Admin Management (Super Admin only)
GET  /api/v1/admin/users?role=admin,super_admin
     → Lấy danh sách admin/super_admin users
     → Response: { data: AdminUser[] }

POST /api/v1/admin/promote-user
     → Promote user thành admin/super_admin
     → Body: { email: string, role: "admin" | "super_admin" }
     → Response: { success: true, data: User }

PATCH /api/v1/admin/users/{id}/status
      → Toggle activate/deactivate admin
      → Body: { is_active: boolean }
      → Response: { success: true }
```

#### **AI Service** (`ai-service`):
```python
# AI Configuration (Super Admin only)
GET /api/v1/admin/config
    → Lấy cấu hình AI hiện tại
    → Response:api_key?: string,     # Masked (e.g. "AIza***...***xyz")
        gemini_model: string,
        temperature: float,
        max_tokens: int,
        top_p: float,
        top_k: int,
        use_mongodb: bool,
        enable_voice: bool,
        enable_grammar: bool,
        enable_topic: bool,
        chat_memory_turns: int
      }

PUT /api/v1/admin/config
    → Cập nhật cấu hình AI
    → Body: AiChatConfig (như trên)
    → Note: gemini_api_key có thể null/empty → fallback to GEMINI_API_KEY env var
    → Body: AiChatConfig (như trên)
    → Response: { success: true, data: AiChatConfig }
```

---

## 🔒 Security & Access Control

### **Route Protection:**
```tsx
// Admin routes (admin + super_admin)
<Route element={<RequireRole allowed={["admin", "super_admin"]} />}>
  <Route path="/admin/*" element={<AdminPages />} />
</Route>

// Super Admin routes (super_admin only)
<Route element={<RequireRole allowed={["super_admin"]} />}>
  <Route path="/super/*" element={<SuperAdminPages />} />
</Route>
```

### **Backend Dependencies:**
```python
# Admin or Super Admin
admin: User = Depends(get_current_admin)

# Super Admin only
super_admin: User = Depends(get_current_super_admin)
```

### **Current Super Admins:**
```
✅ nhthang312@gmail.com (super_admin) - Google OAuth
✅ thefirestar312@gmail.com (admin) - Google OAuth
```

---

## 📝 Implementation Roadmap

### **Phase 1: Backend APIs** (⚠️ Cần làm ngay)
1. ✅ User role verification trong `/auth/google` (đã xong)
2. ⚠️ Implement `/admin/users?role=admin,super_admin`
3. ⚠️ Implement `/admin/promote-user`
4. ⚠️ Implement `/admin/users/{id}/status`
5. ⚠️ Implement AI config endpoints (AI service)

### **Phase 2: Testing & Integration**
1. Test admin management flow
2. Test AI config persistence
3. Test role-based access control
4. Security audit

### **Phase 3: Documentation**
1. API documentation (Swagger)
2. User guide cho Super Admin
3. Deployment guide

---

## 🧪 Test URLs

```bash
# Admin Dashboard
http://localhost:5176/admin

# Super Admin Dashboard
http://localhost:5176/super

# Admin Management
http://localhost:5176/super/admins

# AI Chat Config
http://localhost:5176/super/ai-chat

# Database Manager
http://localhost:5176/super/db

# AI Models
http://localhost:5176/super/ai-models
```

---

## 🎯 Next Steps

1. **Implement backend APIs** cho Admin Management
2. **Implement backend APIs** cho AI Configuration
3. **Test với nhthang312@gmail.com** (super_admin)
4. **Verify role restrictions** hoạt động đúng
5. **Add audit logging** cho admin actions
6. **Document APIs** trong Swagger

---

**Last Updated:** 2026-02-07  
**Version:** 1.0.0  
**Status:** ✅ UI Complete, ⚠️ Backend APIs Pending
